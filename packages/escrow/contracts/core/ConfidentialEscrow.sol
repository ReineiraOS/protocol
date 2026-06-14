// SPDX-License-Identifier: FSL-1.1-ALv2
// Copyright (c) 2026 Reineira Labs Limited All rights reserved.
pragma solidity ^0.8.25;

import {FHE, euint64, ebool, eaddress, InEuint64, InEaddress} from "@fhenixprotocol/cofhe-contracts/FHE.sol";
import {IFHERC20} from "fhenix-confidential-contracts/contracts/interfaces/IFHERC20.sol";
import {IERC165} from "@openzeppelin/contracts/interfaces/IERC165.sol";
import {TestnetCoreBase} from "@reineira-os/shared/contracts/common/TestnetCoreBase.sol";
import {EscrowLib} from "@reineira-os/shared/contracts/libraries/EscrowLib.sol";
import {FeeLib} from "@reineira-os/shared/contracts/libraries/FeeLib.sol";
import {IEscrow} from "@reineira-os/shared/contracts/interfaces/core/IEscrow.sol";
import {IConfidentialEscrow} from "../interfaces/core/IConfidentialEscrow.sol";
import {EscrowCondition} from "../extensions/EscrowCondition.sol";
import {FHEMeta} from "@reineira-os/shared/contracts/common/FHEMeta.sol";
import {IConditionResolver} from "@reineira-os/shared/contracts/interfaces/plugins/IConditionResolver.sol";

contract ConfidentialEscrow is IEscrow, IConfidentialEscrow, EscrowCondition, TestnetCoreBase {
    uint256 public constant MAX_BATCH_SIZE = 20;

    IFHERC20 private _paymentToken;

    uint256 private _nextId;

    address private _coverageManager;

    struct Escrow {
        eaddress owner;
        eaddress caller;
        euint64 amount;
        euint64 paidAmount;
        ebool isRedeemed;
    }

    struct Fee {
        euint64 bps;
        address recipient;
        bool set;
    }

    mapping(uint256 => Escrow) private _escrows;
    mapping(uint256 => Fee[3]) private _fees;
    mapping(uint256 => Fee[]) private _underwriterFees;
    mapping(uint256 => euint64) private _totalStampedBps;

    modifier onlyCoverageManager() {
        if (_msgSender() != _coverageManager) revert EscrowLib.NotCoverageManager();
        _;
    }

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor(address trustedForwarder_) TestnetCoreBase(trustedForwarder_) {
        _disableInitializers();
    }

    function initialize(address owner_, address paymentToken_) external initializer {
        if (paymentToken_ == address(0)) revert ZeroAddress();
        __TestnetCoreBase_init(owner_);
        _paymentToken = IFHERC20(paymentToken_);
        emit CoreInitialized(owner_);
    }

    function create(
        InEaddress calldata encryptedOwner,
        InEuint64 calldata encryptedAmount,
        address resolver,
        bytes calldata resolverData
    ) external nonReentrant returns (uint256 escrowId) {
        address sender = _msgSender();
        eaddress owner = FHEMeta.asEaddress(encryptedOwner, sender);
        euint64 amount = FHEMeta.asEuint64(encryptedAmount, sender);
        eaddress callerEncrypted = FHE.asEaddress(sender);

        escrowId = _nextId++;

        euint64 zeroPaid = FHE.asEuint64(0);
        ebool notRedeemed = FHE.asEbool(false);
        euint64 zeroTotalBps = FHE.asEuint64(0);

        _escrows[escrowId] = Escrow({
            owner: owner,
            caller: callerEncrypted,
            amount: amount,
            paidAmount: zeroPaid,
            isRedeemed: notRedeemed
        });
        _totalStampedBps[escrowId] = zeroTotalBps;

        FHE.allowThis(owner);
        FHE.allowThis(callerEncrypted);
        FHE.allowThis(amount);
        FHE.allowThis(zeroPaid);
        FHE.allowThis(notRedeemed);
        FHE.allowThis(zeroTotalBps);

        FHE.allow(owner, sender);
        FHE.allow(callerEncrypted, sender);
        FHE.allow(amount, sender);
        FHE.allow(zeroPaid, sender);
        FHE.allow(notRedeemed, sender);

        if (resolver != address(0)) {
            _setCondition(escrowId, resolver, resolverData);
            _stampConditionFee(escrowId, resolver);
        }

        if (_coverageManager != address(0)) {
            FHE.allow(amount, _coverageManager);
            FHE.allow(owner, _coverageManager);
            FHE.allow(callerEncrypted, _coverageManager);
        }

        emit EscrowCreated(escrowId);
    }

    function fund(uint256 escrowId, InEuint64 calldata encryptedPayment) external nonReentrant {
        EscrowLib.validateExists(escrowId < _nextId, escrowId);

        address sender = _msgSender();
        Escrow storage escrow = _escrows[escrowId];

        euint64 paymentAmount = FHEMeta.asEuint64(encryptedPayment, sender);

        euint64 balanceBefore = _paymentToken.confidentialBalanceOf(address(this));

        FHE.allowTransient(paymentAmount, address(_paymentToken));

        _paymentToken.confidentialTransferFrom(sender, address(this), paymentAmount);

        euint64 balanceAfter = _paymentToken.confidentialBalanceOf(address(this));
        euint64 actualPayment = FHE.sub(balanceAfter, balanceBefore);

        euint64 newPaidAmount = FHE.add(escrow.paidAmount, actualPayment);
        escrow.paidAmount = newPaidAmount;

        FHE.allowThis(newPaidAmount);

        emit EscrowFunded(escrowId, sender);
    }

    function fundFrom(uint256 escrowId, euint64 amount) external nonReentrant {
        EscrowLib.validateExists(escrowId < _nextId, escrowId);

        address sender = _msgSender();
        Escrow storage escrow = _escrows[escrowId];

        euint64 balanceBefore = _paymentToken.confidentialBalanceOf(address(this));

        FHE.allowTransient(amount, address(_paymentToken));
        _paymentToken.confidentialTransferFrom(sender, address(this), amount);

        euint64 balanceAfter = _paymentToken.confidentialBalanceOf(address(this));
        euint64 actualPayment = FHE.sub(balanceAfter, balanceBefore);

        euint64 newPaidAmount = FHE.add(escrow.paidAmount, actualPayment);
        escrow.paidAmount = newPaidAmount;

        FHE.allowThis(newPaidAmount);

        emit EscrowFunded(escrowId, sender);
    }

    function redeem(uint256 escrowId) external override(IEscrow, IConfidentialEscrow) nonReentrant {
        EscrowLib.validateExists(escrowId < _nextId, escrowId);
        _checkCondition(escrowId);

        address sender = _msgSender();
        Escrow storage escrow = _escrows[escrowId];

        eaddress callerEncrypted = FHE.asEaddress(sender);

        ebool canRedeem = FHE.and(
            FHE.and(FHE.eq(escrow.owner, callerEncrypted), FHE.gte(escrow.paidAmount, escrow.amount)),
            FHE.not(escrow.isRedeemed)
        );

        euint64 zero = FHE.asEuint64(0);
        euint64 redemptionAmount = FHE.select(canRedeem, escrow.paidAmount, zero);

        escrow.isRedeemed = FHE.or(escrow.isRedeemed, canRedeem);
        FHE.allowThis(escrow.isRedeemed);

        euint64 net = _distributeFees(escrowId, redemptionAmount, canRedeem);

        FHE.allowTransient(net, address(_paymentToken));
        _paymentToken.confidentialTransfer(sender, net);

        emit EscrowRedeemed(escrowId);
    }

    function redeemMultiple(uint256[] calldata escrowIds) external override(IEscrow, IConfidentialEscrow) nonReentrant {
        uint256 length = escrowIds.length;
        EscrowLib.validateNonEmpty(length);
        EscrowLib.validateBatchSize(length, MAX_BATCH_SIZE);

        address sender = _msgSender();

        euint64 totalNet = FHE.asEuint64(0);
        FHE.allowThis(totalNet);

        eaddress callerEncrypted = FHE.asEaddress(sender);

        for (uint256 i = 0; i < length; i++) {
            uint256 escrowId = escrowIds[i];

            if (escrowId >= _nextId) continue;
            if (!_isConditionMet(escrowId)) continue;

            Escrow storage escrow = _escrows[escrowId];

            ebool canRedeem = FHE.and(
                FHE.and(FHE.eq(escrow.owner, callerEncrypted), FHE.gte(escrow.paidAmount, escrow.amount)),
                FHE.not(escrow.isRedeemed)
            );

            euint64 zero = FHE.asEuint64(0);
            euint64 redemptionAmount = FHE.select(canRedeem, escrow.paidAmount, zero);

            escrow.isRedeemed = FHE.or(escrow.isRedeemed, canRedeem);
            FHE.allowThis(escrow.isRedeemed);

            euint64 net = _distributeFees(escrowId, redemptionAmount, canRedeem);
            totalNet = FHE.add(totalNet, net);
        }

        FHE.allowThis(totalNet);
        FHE.allowTransient(totalNet, address(_paymentToken));
        _paymentToken.confidentialTransfer(sender, totalNet);

        emit EscrowBatchRedeemed(escrowIds);
    }

    function exists(uint256 escrowId) external view override(IEscrow, IConfidentialEscrow) returns (bool) {
        return escrowId < _nextId;
    }

    function getOwner(uint256 escrowId) external view override(IConfidentialEscrow) returns (eaddress owner) {
        EscrowLib.validateExists(escrowId < _nextId, escrowId);
        return _escrows[escrowId].owner;
    }

    function getAmount(uint256 escrowId) external view override(IConfidentialEscrow) returns (euint64 amount) {
        EscrowLib.validateExists(escrowId < _nextId, escrowId);
        return _escrows[escrowId].amount;
    }

    function getPaidAmount(uint256 escrowId) external view override(IConfidentialEscrow) returns (euint64 paidAmount) {
        EscrowLib.validateExists(escrowId < _nextId, escrowId);
        return _escrows[escrowId].paidAmount;
    }

    function getRedeemedStatus(
        uint256 escrowId
    ) external view override(IConfidentialEscrow) returns (ebool isRedeemed) {
        EscrowLib.validateExists(escrowId < _nextId, escrowId);
        return _escrows[escrowId].isRedeemed;
    }

    function total() external view override(IEscrow, IConfidentialEscrow) returns (uint256 count) {
        return _nextId;
    }

    function setCoverageManager(address coverageManager_) external override(IEscrow, IConfidentialEscrow) onlyOwner {
        if (coverageManager_ == address(0)) revert ZeroAddress();
        _coverageManager = coverageManager_;
        emit CoverageManagerSet(coverageManager_);
    }

    function setUnderwriterFee(
        uint256 escrowId,
        eaddress holder,
        euint64 effectiveBps,
        address recipient
    ) external override(IConfidentialEscrow) nonReentrant onlyCoverageManager {
        EscrowLib.validateExists(escrowId < _nextId, escrowId);
        if (recipient == address(0)) revert ZeroAddress();

        ebool isOwner = FHE.eq(_escrows[escrowId].owner, holder);
        ebool isCaller = FHE.eq(_escrows[escrowId].caller, holder);
        ebool isAuthorized = FHE.or(isOwner, isCaller);

        euint64 finalBps = FHE.select(isAuthorized, effectiveBps, FHE.asEuint64(0));

        _stampFee(escrowId, uint8(FeeLib.FeeKind.Underwriter), finalBps, recipient);
    }

    function getCaller(uint256 escrowId) external view override(IConfidentialEscrow) returns (eaddress) {
        EscrowLib.validateExists(escrowId < _nextId, escrowId);
        return _escrows[escrowId].caller;
    }

    function getFee(
        uint256 escrowId,
        uint8 kind
    ) external view override(IConfidentialEscrow) returns (euint64 bps, address recipient, bool set) {
        if (!FeeLib.isValidKind(kind)) revert EscrowLib.InvalidFeeKind(kind);
        Fee storage f = _fees[escrowId][kind];
        return (f.bps, f.recipient, f.set);
    }

    function getUnderwriterFees(uint256 escrowId) external view returns (Fee[] memory) {
        return _underwriterFees[escrowId];
    }

    function getTotalStampedBps(uint256 escrowId) external view override(IConfidentialEscrow) returns (euint64) {
        return _totalStampedBps[escrowId];
    }

    function coverageManager() external view returns (address) {
        return _coverageManager;
    }

    function supportsInterface(bytes4 interfaceId) external pure returns (bool) {
        return
            interfaceId == type(IEscrow).interfaceId ||
            interfaceId == type(IConfidentialEscrow).interfaceId ||
            interfaceId == type(IERC165).interfaceId;
    }

    function create(
        address,
        uint256,
        address,
        bytes calldata
    ) external override nonReentrant returns (uint256 escrowId) {
        revert("Use IConfidentialEscrow.create or IEscrow.create(bytes, ...) with encrypted parameters");
    }

    function create(
        bytes calldata initData,
        address resolver,
        bytes calldata resolverData
    ) external override nonReentrant returns (uint256 escrowId) {
        (InEaddress memory encryptedOwner, InEuint64 memory encryptedAmount) = abi.decode(
            initData,
            (InEaddress, InEuint64)
        );

        address sender = _msgSender();
        eaddress owner = FHEMeta.asEaddress(encryptedOwner, sender);
        euint64 amount = FHEMeta.asEuint64(encryptedAmount, sender);
        eaddress callerEncrypted = FHE.asEaddress(sender);

        escrowId = _nextId++;

        euint64 zeroPaid = FHE.asEuint64(0);
        ebool notRedeemed = FHE.asEbool(false);
        euint64 zeroTotalBps = FHE.asEuint64(0);

        _escrows[escrowId] = Escrow({
            owner: owner,
            caller: callerEncrypted,
            amount: amount,
            paidAmount: zeroPaid,
            isRedeemed: notRedeemed
        });
        _totalStampedBps[escrowId] = zeroTotalBps;

        FHE.allowThis(owner);
        FHE.allowThis(callerEncrypted);
        FHE.allowThis(amount);
        FHE.allowThis(zeroPaid);
        FHE.allowThis(notRedeemed);
        FHE.allowThis(zeroTotalBps);

        FHE.allow(owner, sender);
        FHE.allow(callerEncrypted, sender);
        FHE.allow(amount, sender);
        FHE.allow(zeroPaid, sender);
        FHE.allow(notRedeemed, sender);

        if (resolver != address(0)) {
            _setCondition(escrowId, resolver, resolverData);
            _stampConditionFee(escrowId, resolver);
        }

        if (_coverageManager != address(0)) {
            FHE.allow(amount, _coverageManager);
            FHE.allow(owner, _coverageManager);
            FHE.allow(callerEncrypted, _coverageManager);
        }

        emit EscrowCreated(escrowId);
    }

    function fund(uint256 escrowId, bytes calldata fundingProof) external nonReentrant {
        EscrowLib.validateExists(escrowId < _nextId, escrowId);

        InEuint64 memory encryptedPayment = abi.decode(fundingProof, (InEuint64));

        address sender = _msgSender();
        Escrow storage escrow = _escrows[escrowId];

        euint64 paymentAmount = FHEMeta.asEuint64(encryptedPayment, sender);

        euint64 balanceBefore = _paymentToken.confidentialBalanceOf(address(this));

        FHE.allowTransient(paymentAmount, address(_paymentToken));

        _paymentToken.confidentialTransferFrom(sender, address(this), paymentAmount);

        euint64 balanceAfter = _paymentToken.confidentialBalanceOf(address(this));
        euint64 actualPayment = FHE.sub(balanceAfter, balanceBefore);

        euint64 newPaidAmount = FHE.add(escrow.paidAmount, actualPayment);
        escrow.paidAmount = newPaidAmount;

        FHE.allowThis(newPaidAmount);

        emit EscrowFunded(escrowId, sender);
    }

    function isFunded(uint256 escrowId) external view override returns (bool) {
        EscrowLib.validateExists(escrowId < _nextId, escrowId);
        return true;
    }

    function budget(uint256 escrowId) external view returns (bytes memory) {
        EscrowLib.validateExists(escrowId < _nextId, escrowId);
        return abi.encode(_escrows[escrowId].amount);
    }

    function release(uint256 escrowId, address recipient, bytes calldata) external nonReentrant {
        EscrowLib.validateExists(escrowId < _nextId, escrowId);
        _checkCondition(escrowId);

        address sender = _msgSender();
        Escrow storage escrow = _escrows[escrowId];

        eaddress callerEncrypted = FHE.asEaddress(sender);

        ebool canRedeem = FHE.and(
            FHE.and(FHE.eq(escrow.owner, callerEncrypted), FHE.gte(escrow.paidAmount, escrow.amount)),
            FHE.not(escrow.isRedeemed)
        );

        euint64 zero = FHE.asEuint64(0);
        euint64 redemptionAmount = FHE.select(canRedeem, escrow.paidAmount, zero);

        escrow.isRedeemed = FHE.or(escrow.isRedeemed, canRedeem);
        FHE.allowThis(escrow.isRedeemed);

        euint64 net = _distributeFees(escrowId, redemptionAmount, canRedeem);

        FHE.allowTransient(net, address(_paymentToken));
        _paymentToken.confidentialTransfer(recipient, net);

        emit EscrowRedeemed(escrowId);
    }

    function status(uint256 escrowId) external view override returns (Phase) {
        EscrowLib.validateExists(escrowId < _nextId, escrowId);
        return Phase.Open;
    }

    function paymentToken() external view override(IConfidentialEscrow) returns (IFHERC20) {
        return _paymentToken;
    }

    function _stampConditionFee(uint256 escrowId, address resolver) private {
        (uint16 bpsPlain, address recipient) = IConditionResolver(resolver).getConditionFee(escrowId);
        if (bpsPlain == 0 || recipient == address(0)) return;

        euint64 bps = FHE.asEuint64(uint64(bpsPlain));
        _stampFee(escrowId, uint8(FeeLib.FeeKind.Condition), bps, recipient);
    }

    function _stampFee(uint256 escrowId, uint8 kind, euint64 bps, address recipient) private {
        if (recipient == address(0)) return;

        euint64 currentTotal = _totalStampedBps[escrowId];
        euint64 newTotal = FHE.add(currentTotal, bps);
        ebool wouldExceedTotal = FHE.gt(newTotal, FHE.asEuint64(uint64(FeeLib.MAX_TOTAL_BPS)));
        euint64 finalBps = FHE.select(wouldExceedTotal, FHE.asEuint64(0), bps);
        euint64 finalTotal = FHE.select(wouldExceedTotal, currentTotal, newTotal);

        FHE.allowThis(finalBps);
        FHE.allowThis(finalTotal);

        if (uint8(FeeLib.FeeKind.Underwriter) == kind) {
            _underwriterFees[escrowId].push(Fee({bps: finalBps, recipient: recipient, set: true}));
            Fee storage existingFee = _fees[escrowId][kind];
            euint64 accumulatedBps = existingFee.set ? FHE.add(existingFee.bps, finalBps) : finalBps;
            FHE.allowThis(accumulatedBps);
            _fees[escrowId][kind] = Fee({bps: accumulatedBps, recipient: recipient, set: true});
        } else {
            _fees[escrowId][kind] = Fee({bps: finalBps, recipient: recipient, set: true});
        }
        _totalStampedBps[escrowId] = finalTotal;

        emit FeeStamped(escrowId, kind, 0, recipient);
    }

    function _distributeFees(uint256 escrowId, euint64 paidAmount, ebool canRedeem) private returns (euint64 net) {
        net = paidAmount;
        euint64 maxBpsEnc = FHE.asEuint64(uint64(FeeLib.MAX_TOTAL_BPS));
        for (uint8 k = 0; k < FeeLib.MAX_FEE_KIND; k++) {
            if (k == uint8(FeeLib.FeeKind.Underwriter)) continue;
            Fee storage f = _fees[escrowId][k];
            if (!f.set) continue;

            euint64 feeAmount = FHE.div(FHE.mul(paidAmount, f.bps), maxBpsEnc);
            euint64 conditionalFee = FHE.select(canRedeem, feeAmount, FHE.asEuint64(0));
            euint64 cappedFee = FHE.select(FHE.lte(conditionalFee, net), conditionalFee, net);
            net = FHE.sub(net, cappedFee);

            FHE.allowTransient(cappedFee, address(_paymentToken));
            _paymentToken.confidentialTransfer(f.recipient, cappedFee);

            emit FeeDistributed(escrowId, k, 0, f.recipient);
        }
        Fee[] storage uwFees = _underwriterFees[escrowId];
        for (uint256 i = 0; i < uwFees.length; i++) {
            Fee storage f = uwFees[i];
            if (!f.set) continue;

            euint64 feeAmount = FHE.div(FHE.mul(paidAmount, f.bps), maxBpsEnc);
            euint64 conditionalFee = FHE.select(canRedeem, feeAmount, FHE.asEuint64(0));
            euint64 cappedFee = FHE.select(FHE.lte(conditionalFee, net), conditionalFee, net);
            net = FHE.sub(net, cappedFee);

            FHE.allowTransient(cappedFee, address(_paymentToken));
            _paymentToken.confidentialTransfer(f.recipient, cappedFee);

            emit FeeDistributed(escrowId, uint8(FeeLib.FeeKind.Underwriter), 0, f.recipient);
        }
        FHE.allowThis(net);
    }
}
