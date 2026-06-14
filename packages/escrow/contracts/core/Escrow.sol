// SPDX-License-Identifier: FSL-1.1-ALv2
// Copyright (c) 2026 Reineira Labs Limited All rights reserved.
pragma solidity ^0.8.25;

import {IERC20} from "@openzeppelin/contracts/interfaces/IERC20.sol";
import {IERC165} from "@openzeppelin/contracts/interfaces/IERC165.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {TestnetCoreBase} from "@reineira-os/shared/contracts/common/TestnetCoreBase.sol";
import {EscrowLib} from "@reineira-os/shared/contracts/libraries/EscrowLib.sol";
import {FeeLib} from "@reineira-os/shared/contracts/libraries/FeeLib.sol";
import {IEscrow} from "@reineira-os/shared/contracts/interfaces/core/IEscrow.sol";
import {IConditionResolver} from "@reineira-os/shared/contracts/interfaces/plugins/IConditionResolver.sol";
import {EscrowCondition} from "../extensions/EscrowCondition.sol";

contract Escrow is IEscrow, EscrowCondition, TestnetCoreBase {
    using SafeERC20 for IERC20;

    uint256 public constant MAX_BATCH_SIZE = 20;

    IERC20 public paymentToken;

    uint256 private _nextId;

    address private _coverageManager;

    struct EscrowData {
        address owner;
        address caller;
        uint256 amount;
        uint256 paidAmount;
        bool isRedeemed;
    }

    struct Fee {
        uint16 bps;
        address recipient;
        bool set;
    }

    mapping(uint256 => EscrowData) private _escrows;
    mapping(uint256 => Fee[3]) private _fees;
    mapping(uint256 => Fee[]) private _underwriterFees;
    mapping(uint256 => uint16) private _totalStampedBps;

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
        paymentToken = IERC20(paymentToken_);
        emit CoreInitialized(owner_);
    }

    function create(
        address owner_,
        uint256 amount_,
        address resolver,
        bytes calldata resolverData
    ) external nonReentrant returns (uint256 escrowId) {
        if (owner_ == address(0)) revert ZeroAddress();

        address sender = _msgSender();
        escrowId = _nextId++;

        _escrows[escrowId] = EscrowData({
            owner: owner_,
            caller: sender,
            amount: amount_,
            paidAmount: 0,
            isRedeemed: false
        });

        if (resolver != address(0)) {
            _setCondition(escrowId, resolver, resolverData);
            _stampConditionFee(escrowId, resolver);
        }

        emit EscrowCreated(escrowId);
    }

    function fund(uint256 escrowId, uint256 amount) external nonReentrant {
        EscrowLib.validateExists(escrowId < _nextId, escrowId);

        address sender = _msgSender();
        EscrowData storage e = _escrows[escrowId];

        uint256 balanceBefore = paymentToken.balanceOf(address(this));
        paymentToken.safeTransferFrom(sender, address(this), amount);
        uint256 actualPayment = paymentToken.balanceOf(address(this)) - balanceBefore;

        e.paidAmount += actualPayment;

        emit EscrowFunded(escrowId, sender);
    }

    function redeem(uint256 escrowId) external nonReentrant {
        EscrowLib.validateExists(escrowId < _nextId, escrowId);
        _checkCondition(escrowId);

        address sender = _msgSender();
        EscrowData storage e = _escrows[escrowId];

        if (e.owner != sender) revert NotOwner();
        if (e.paidAmount < e.amount) revert NotFullyPaid();
        if (e.isRedeemed) revert AlreadyRedeemed();

        e.isRedeemed = true;

        uint256 net = _distributeFees(escrowId, e.paidAmount);
        if (net > 0) paymentToken.safeTransfer(sender, net);

        emit EscrowRedeemed(escrowId);
    }

    function redeemMultiple(uint256[] calldata escrowIds) external nonReentrant {
        EscrowLib.validateNonEmpty(escrowIds.length);
        EscrowLib.validateBatchSize(escrowIds.length, MAX_BATCH_SIZE);

        address sender = _msgSender();
        uint256 totalNet = 0;

        for (uint256 i = 0; i < escrowIds.length; i++) {
            uint256 escrowId = escrowIds[i];

            if (escrowId >= _nextId) continue;
            if (!_isConditionMet(escrowId)) continue;

            EscrowData storage e = _escrows[escrowId];

            if (e.owner != sender) continue;
            if (e.paidAmount < e.amount) continue;
            if (e.isRedeemed) continue;

            e.isRedeemed = true;

            uint256 net = _distributeFees(escrowId, e.paidAmount);
            totalNet += net;
        }

        if (totalNet > 0) {
            paymentToken.safeTransfer(sender, totalNet);
        }

        emit EscrowBatchRedeemed(escrowIds);
    }

    function exists(uint256 escrowId) external view returns (bool) {
        return escrowId < _nextId;
    }

    function getOwner(uint256 escrowId) external view returns (address) {
        EscrowLib.validateExists(escrowId < _nextId, escrowId);
        return _escrows[escrowId].owner;
    }

    function getAmount(uint256 escrowId) external view returns (uint256) {
        EscrowLib.validateExists(escrowId < _nextId, escrowId);
        return _escrows[escrowId].amount;
    }

    function getPaidAmount(uint256 escrowId) external view returns (uint256) {
        EscrowLib.validateExists(escrowId < _nextId, escrowId);
        return _escrows[escrowId].paidAmount;
    }

    function getRedeemedStatus(uint256 escrowId) external view returns (bool) {
        EscrowLib.validateExists(escrowId < _nextId, escrowId);
        return _escrows[escrowId].isRedeemed;
    }

    function total() external view returns (uint256) {
        return _nextId;
    }

    function getCaller(uint256 escrowId) external view returns (address) {
        EscrowLib.validateExists(escrowId < _nextId, escrowId);
        return _escrows[escrowId].caller;
    }

    function setCoverageManager(address coverageManager_) external onlyOwner {
        if (coverageManager_ == address(0)) revert ZeroAddress();
        _coverageManager = coverageManager_;
        emit CoverageManagerSet(coverageManager_);
    }

    function setUnderwriterFee(
        uint256 escrowId,
        address holder,
        uint16 effectiveBps,
        address recipient
    ) external nonReentrant onlyCoverageManager {
        EscrowLib.validateExists(escrowId < _nextId, escrowId);
        if (recipient == address(0)) revert ZeroAddress();

        EscrowData storage e = _escrows[escrowId];
        bool isAuthorized = (e.owner == holder) || (e.caller == holder);
        uint16 finalBps = isAuthorized ? effectiveBps : 0;

        _stampFee(escrowId, uint8(FeeLib.FeeKind.Underwriter), finalBps, recipient);
    }

    function getFee(uint256 escrowId, uint8 kind) external view returns (uint16 bps, address recipient, bool set) {
        if (!FeeLib.isValidKind(kind)) revert EscrowLib.InvalidFeeKind(kind);
        Fee storage f = _fees[escrowId][kind];
        return (f.bps, f.recipient, f.set);
    }

    function getUnderwriterFees(uint256 escrowId) external view returns (Fee[] memory) {
        return _underwriterFees[escrowId];
    }

    function getTotalStampedBps(uint256 escrowId) external view returns (uint16) {
        return _totalStampedBps[escrowId];
    }

    function coverageManager() external view returns (address) {
        return _coverageManager;
    }

    function supportsInterface(bytes4 interfaceId) external pure returns (bool) {
        return interfaceId == type(IEscrow).interfaceId || interfaceId == type(IERC165).interfaceId;
    }

    function create(
        bytes calldata initData,
        address resolver,
        bytes calldata resolverData
    ) external nonReentrant returns (uint256 escrowId) {
        (address owner_, uint256 amount_) = abi.decode(initData, (address, uint256));

        if (owner_ == address(0)) revert ZeroAddress();

        address sender = _msgSender();
        escrowId = _nextId++;

        _escrows[escrowId] = EscrowData({
            owner: owner_,
            caller: sender,
            amount: amount_,
            paidAmount: 0,
            isRedeemed: false
        });

        if (resolver != address(0)) {
            _setCondition(escrowId, resolver, resolverData);
            _stampConditionFee(escrowId, resolver);
        }

        emit EscrowCreated(escrowId);
    }

    function fund(uint256 escrowId, bytes calldata fundingProof) external nonReentrant {
        EscrowLib.validateExists(escrowId < _nextId, escrowId);

        uint256 amount = abi.decode(fundingProof, (uint256));

        address sender = _msgSender();
        EscrowData storage e = _escrows[escrowId];

        uint256 balanceBefore = paymentToken.balanceOf(address(this));
        paymentToken.safeTransferFrom(sender, address(this), amount);
        uint256 actualPayment = paymentToken.balanceOf(address(this)) - balanceBefore;

        e.paidAmount += actualPayment;

        emit EscrowFunded(escrowId, sender);
    }

    function isFunded(uint256 escrowId) external view returns (bool) {
        EscrowLib.validateExists(escrowId < _nextId, escrowId);
        EscrowData storage e = _escrows[escrowId];
        return e.paidAmount >= e.amount;
    }

    function budget(uint256 escrowId) external view returns (bytes memory) {
        EscrowLib.validateExists(escrowId < _nextId, escrowId);
        return abi.encode(_escrows[escrowId].amount);
    }

    function release(uint256 escrowId, address recipient, bytes calldata) external nonReentrant {
        EscrowLib.validateExists(escrowId < _nextId, escrowId);
        _checkCondition(escrowId);

        address sender = _msgSender();
        EscrowData storage e = _escrows[escrowId];

        if (e.owner != sender) revert NotOwner();
        if (e.paidAmount < e.amount) revert NotFullyPaid();
        if (e.isRedeemed) revert AlreadyRedeemed();

        e.isRedeemed = true;

        uint256 net = _distributeFees(escrowId, e.paidAmount);
        if (net > 0) paymentToken.safeTransfer(recipient, net);

        emit EscrowRedeemed(escrowId);
    }

    function status(uint256 escrowId) external view returns (Phase) {
        EscrowLib.validateExists(escrowId < _nextId, escrowId);
        EscrowData storage e = _escrows[escrowId];

        if (e.isRedeemed) {
            return Phase.Released;
        }

        if (e.paidAmount >= e.amount) {
            return Phase.Funded;
        }

        return Phase.Open;
    }

    function _stampConditionFee(uint256 escrowId, address resolver) private {
        (uint16 bps, address recipient) = IConditionResolver(resolver).getConditionFee(escrowId);
        if (bps == 0 || recipient == address(0)) return;

        _stampFee(escrowId, uint8(FeeLib.FeeKind.Condition), bps, recipient);
    }

    function _stampFee(uint256 escrowId, uint8 kind, uint16 bps, address recipient) private {
        if (bps == 0 || recipient == address(0)) return;

        uint16 newTotal = _totalStampedBps[escrowId] + bps;
        if (newTotal > FeeLib.MAX_TOTAL_BPS) {
            revert EscrowLib.FeeBudgetExceeded(_totalStampedBps[escrowId], bps, FeeLib.MAX_TOTAL_BPS);
        }

        if (uint8(FeeLib.FeeKind.Underwriter) == kind) {
            _underwriterFees[escrowId].push(Fee({bps: bps, recipient: recipient, set: true}));
            Fee storage existingFee = _fees[escrowId][kind];
            uint16 accumulatedBps = existingFee.set ? existingFee.bps + bps : bps;
            _fees[escrowId][kind] = Fee({bps: accumulatedBps, recipient: recipient, set: true});
        } else {
            _fees[escrowId][kind] = Fee({bps: bps, recipient: recipient, set: true});
        }
        _totalStampedBps[escrowId] = newTotal;

        emit FeeStamped(escrowId, kind, bps, recipient);
    }

    function _distributeFees(uint256 escrowId, uint256 paidAmount) private returns (uint256 net) {
        net = paidAmount;
        for (uint8 k = 0; k < FeeLib.MAX_FEE_KIND; k++) {
            if (k == uint8(FeeLib.FeeKind.Underwriter)) continue;
            Fee storage f = _fees[escrowId][k];
            if (!f.set || f.bps == 0) continue;
            uint256 feeAmount = (paidAmount * f.bps) / FeeLib.MAX_TOTAL_BPS;
            if (feeAmount == 0) continue;
            if (feeAmount > net) feeAmount = net;
            net -= feeAmount;
            paymentToken.safeTransfer(f.recipient, feeAmount);
            emit FeeDistributed(escrowId, k, feeAmount, f.recipient);
        }
        Fee[] storage uwFees = _underwriterFees[escrowId];
        for (uint256 i = 0; i < uwFees.length; i++) {
            Fee storage f = uwFees[i];
            if (!f.set || f.bps == 0) continue;
            uint256 feeAmount = (paidAmount * f.bps) / FeeLib.MAX_TOTAL_BPS;
            if (feeAmount == 0) continue;
            if (feeAmount > net) feeAmount = net;
            net -= feeAmount;
            paymentToken.safeTransfer(f.recipient, feeAmount);
            emit FeeDistributed(escrowId, uint8(FeeLib.FeeKind.Underwriter), feeAmount, f.recipient);
        }
    }
}
