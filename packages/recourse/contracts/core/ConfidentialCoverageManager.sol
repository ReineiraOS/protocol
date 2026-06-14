// SPDX-License-Identifier: FSL-1.1-ALv2
// Copyright (c) 2026 Reineira Labs Limited All rights reserved.
pragma solidity ^0.8.24;

import {FHE, euint64, ebool, eaddress, InEuint64} from "@fhenixprotocol/cofhe-contracts/FHE.sol";
import {InEaddress} from "@fhenixprotocol/cofhe-contracts/ICofhe.sol";
import {IFHERC20} from "fhenix-confidential-contracts/contracts/interfaces/IFHERC20.sol";
import {IConfidentialCoverageManager} from "../interfaces/core/IConfidentialCoverageManager.sol";
import {IConfidentialPoolFactory} from "../interfaces/core/IConfidentialPoolFactory.sol";
import {IConfidentialRecoursePool} from "../interfaces/core/IConfidentialRecoursePool.sol";
import {IConfidentialUnderwriterPolicy} from "@reineira-os/shared/contracts/interfaces/plugins/IConfidentialUnderwriterPolicy.sol";
import {IEscrow} from "@reineira-os/shared/contracts/interfaces/core/IEscrow.sol";
import {IConfidentialEscrow} from "../interfaces/external/IConfidentialEscrow.sol";
import {TestnetCoreBase} from "@reineira-os/shared/contracts/common/TestnetCoreBase.sol";
import {FHEMeta} from "@reineira-os/shared/contracts/common/FHEMeta.sol";
import {CoverageLib} from "@reineira-os/shared/contracts/libraries/CoverageLib.sol";
import {CoverageInviteLib} from "@reineira-os/shared/contracts/libraries/CoverageInviteLib.sol";

contract ConfidentialCoverageManager is IConfidentialCoverageManager, TestnetCoreBase {
    uint256 public constant MAX_COVERAGES_PER_ESCROW = 5;

    struct Coverage {
        eaddress holder;
        address plaintextHolder;
        address pool;
        address policy;
        uint256 escrowId;
        euint64 coverageAmount;
        uint256 expiry;
        CoverageStatus status;
    }

    IEscrow private _escrow;
    IConfidentialPoolFactory private _poolFactory;

    uint256 private _nextCoverageId;
    mapping(uint256 => Coverage) private _coverages;
    mapping(uint256 => uint256[]) private _escrowCoverages;
    mapping(uint256 => mapping(uint256 => bool)) private _coveragePaid;

    mapping(bytes32 => uint256) private _usedCount;
    mapping(bytes32 => bool) private _revoked;

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor(address trustedForwarder_) TestnetCoreBase(trustedForwarder_) {
        _disableInitializers();
    }

    function initialize(address owner_, address poolFactory_) external initializer {
        if (owner_ == address(0)) revert ZeroAddress();
        if (poolFactory_ == address(0)) revert ZeroAddress();

        __TestnetCoreBase_init(owner_);

        _poolFactory = IConfidentialPoolFactory(poolFactory_);

        emit CoreInitialized(owner_);
    }

    function setEscrow(address escrow_) external onlyOwner {
        if (escrow_ == address(0)) revert ZeroAddress();
        _escrow = IEscrow(escrow_);
    }

    function setPoolFactory(address poolFactory_) external onlyOwner {
        if (poolFactory_ == address(0)) revert ZeroAddress();
        _poolFactory = IConfidentialPoolFactory(poolFactory_);
    }

    function purchaseCoverage(
        InEaddress calldata encryptedHolder,
        address pool_,
        address policy_,
        uint256 escrowId,
        InEuint64 calldata encryptedCoverageAmount,
        uint256 coverageExpiry,
        bytes calldata policyData,
        bytes calldata riskProof
    ) external nonReentrant returns (uint256 coverageId) {
        CoverageInviteLib.CoverageInvite memory emptyInvite;
        return
            _doPurchase(
                encryptedHolder,
                pool_,
                policy_,
                escrowId,
                encryptedCoverageAmount,
                coverageExpiry,
                policyData,
                riskProof,
                emptyInvite,
                ""
            );
    }

    function purchaseCoverage(
        InEaddress calldata encryptedHolder,
        address pool_,
        address policy_,
        uint256 escrowId,
        InEuint64 calldata encryptedCoverageAmount,
        uint256 coverageExpiry,
        bytes calldata policyData,
        bytes calldata riskProof,
        CoverageInviteLib.CoverageInvite calldata invite,
        bytes calldata inviteSig
    ) external nonReentrant returns (uint256 coverageId) {
        return
            _doPurchase(
                encryptedHolder,
                pool_,
                policy_,
                escrowId,
                encryptedCoverageAmount,
                coverageExpiry,
                policyData,
                riskProof,
                invite,
                inviteSig
            );
    }

    function dispute(uint256 coverageId, bytes calldata disputeProof) external nonReentrant {
        Coverage storage cov = _coverages[coverageId];
        if (cov.status == CoverageStatus.None) revert CoverageLib.CoverageDoesNotExist();
        if (cov.status != CoverageStatus.Active) revert CoverageLib.NotActiveStatus();
        CoverageLib.validateHolder(cov.plaintextHolder, _msgSender());

        if (block.timestamp >= cov.expiry) {
            cov.status = CoverageStatus.Expired;
            emit CoverageExpired(coverageId);
            revert CoverageLib.NotActiveStatus();
        }

        if (_coveragePaid[cov.escrowId][coverageId]) revert CoverageLib.CoverageAlreadyPaid();

        cov.status = CoverageStatus.Disputed;
        emit DisputeFiled(coverageId);

        ebool valid = IConfidentialUnderwriterPolicy(cov.policy).judge(coverageId, disputeProof);
        ebool canPay = valid;

        euint64 payout = FHE.select(canPay, cov.coverageAmount, FHE.asEuint64(0));
        FHE.allowThis(payout);
        FHE.allow(payout, cov.pool);

        euint64 actualPayout = IConfidentialRecoursePool(cov.pool).payClaim(coverageId, payout);
        FHE.allowThis(actualPayout);

        _forwardPayout(cov.pool, actualPayout, cov.plaintextHolder);

        _coveragePaid[cov.escrowId][coverageId] = true;
        cov.status = CoverageStatus.Claimed;
        emit CoverageClaimed(coverageId);
    }

    function revokeInvite(address pool_, bytes32 digest) external {
        if (_msgSender() != IConfidentialRecoursePool(pool_).manager()) revert CoverageLib.NotManager();
        if (_revoked[digest]) revert CoverageLib.InviteAlreadyRevoked();
        _revoked[digest] = true;
        emit InviteRevoked(pool_, digest, _msgSender());
    }

    function escrow() external view returns (address) {
        return address(_escrow);
    }

    function poolFactory() external view returns (address) {
        return address(_poolFactory);
    }

    function coverageStatus(uint256 coverageId) external view returns (CoverageStatus) {
        return _coverages[coverageId].status;
    }

    function usedCount(bytes32 digest) external view returns (uint256) {
        return _usedCount[digest];
    }

    function isInviteRevoked(bytes32 digest) external view returns (bool) {
        return _revoked[digest];
    }

    function getCoveragesForEscrow(uint256 escrowId) external view returns (uint256[] memory) {
        return _escrowCoverages[escrowId];
    }

    function isCoveragePaid(uint256 escrowId, uint256 coverageId) external view returns (bool) {
        return _coveragePaid[escrowId][coverageId];
    }

    function _doPurchase(
        InEaddress calldata encryptedHolder,
        address pool_,
        address policy_,
        uint256 escrowId,
        InEuint64 calldata encryptedCoverageAmount,
        uint256 coverageExpiry,
        bytes calldata policyData,
        bytes calldata riskProof,
        CoverageInviteLib.CoverageInvite memory invite,
        bytes memory inviteSig
    ) private returns (uint256 coverageId) {
        bytes32 digest = _validatePurchase(pool_, policy_, escrowId, coverageExpiry, invite, inviteSig);

        coverageId = _nextCoverageId++;
        IConfidentialUnderwriterPolicy(policy_).onPolicySet(coverageId, policyData);

        _finalizePurchase(
            coverageId,
            encryptedHolder,
            pool_,
            policy_,
            escrowId,
            encryptedCoverageAmount,
            coverageExpiry,
            riskProof
        );
        _escrowCoverages[escrowId].push(coverageId);

        if (digest != bytes32(0)) {
            _consumeInvite(pool_, digest, _msgSender());
        }

        emit CoveragePurchased(coverageId);
    }

    function _validatePurchase(
        address pool_,
        address policy_,
        uint256 escrowId,
        uint256 coverageExpiry,
        CoverageInviteLib.CoverageInvite memory invite,
        bytes memory inviteSig
    ) private view returns (bytes32 digest) {
        if (address(_escrow) == address(0)) revert CoverageLib.EscrowNotConfigured();
        if (address(_poolFactory) == address(0)) revert CoverageLib.PoolFactoryNotConfigured();
        if (!_poolFactory.isPool(pool_)) revert CoverageLib.InvalidPool();
        if (!IConfidentialRecoursePool(pool_).isPolicy(policy_)) revert CoverageLib.InvalidPolicy();
        if (coverageExpiry <= block.timestamp) revert CoverageLib.InvalidExpiry();
        if (!_escrow.exists(escrowId)) revert CoverageLib.EscrowDoesNotExist();
        if (_escrowCoverages[escrowId].length >= MAX_COVERAGES_PER_ESCROW) revert CoverageLib.MaxCoveragesReached();

        if (!IConfidentialRecoursePool(pool_).isOpen()) {
            if (invite.pool != pool_) revert CoverageLib.InvitePoolMismatch();
            if (invite.invitee != _msgSender()) revert CoverageLib.InviteeMismatch();
            if (block.timestamp > invite.deadline) revert CoverageLib.InviteExpired();
            if (invite.maxUses == 0) revert CoverageLib.InviteExhausted();

            bytes32 ds = IConfidentialRecoursePool(pool_).domainSeparator();
            digest = CoverageInviteLib.digest(ds, invite);

            if (_revoked[digest]) revert CoverageLib.InviteAlreadyRevoked();
            if (_usedCount[digest] >= invite.maxUses) revert CoverageLib.InviteExhausted();

            address signer = CoverageInviteLib.recoverSigner(ds, invite, inviteSig);
            if (signer != IConfidentialRecoursePool(pool_).manager()) revert CoverageLib.InviteSignerMismatch();
        }
    }

    function _consumeInvite(address pool_, bytes32 digest, address invitee) private {
        _usedCount[digest] += 1;
        emit InviteConsumed(pool_, digest, invitee);
    }

    struct PurchaseParams {
        uint256 coverageId;
        address pool_;
        address policy_;
        uint256 escrowId;
        uint256 coverageExpiry;
    }

    function _finalizePurchase(
        uint256 coverageId,
        InEaddress calldata encryptedHolder,
        address pool_,
        address policy_,
        uint256 escrowId,
        InEuint64 calldata encryptedCoverageAmount,
        uint256 coverageExpiry,
        bytes calldata riskProof
    ) private {
        eaddress holder = FHEMeta.asEaddress(encryptedHolder, _msgSender());
        euint64 cappedCoverage = _capCoverage(escrowId, encryptedCoverageAmount);

        PurchaseParams memory p = PurchaseParams({
            coverageId: coverageId,
            pool_: pool_,
            policy_: policy_,
            escrowId: escrowId,
            coverageExpiry: coverageExpiry
        });

        _computeAndSetFee(p.policy_, p.escrowId, cappedCoverage, holder, p.pool_, riskProof);
        _storeCoverage(
            p.coverageId,
            holder,
            _msgSender(),
            _msgSender(),
            p.pool_,
            p.policy_,
            p.escrowId,
            cappedCoverage,
            p.coverageExpiry
        );
    }

    function _capCoverage(uint256 escrowId, InEuint64 calldata encryptedCoverageAmount) private returns (euint64) {
        euint64 escrowAmount = IConfidentialEscrow(address(_escrow)).getAmount(escrowId);
        euint64 coverageAmount = FHEMeta.asEuint64(encryptedCoverageAmount, _msgSender());
        euint64 cappedCoverage = FHE.select(FHE.lte(coverageAmount, escrowAmount), coverageAmount, escrowAmount);
        FHE.allowThis(cappedCoverage);
        return cappedCoverage;
    }

    function _computeAndSetFee(
        address policy_,
        uint256 escrowId,
        euint64 coverageAmount,
        eaddress holder,
        address pool_,
        bytes calldata riskProof
    ) private {
        euint64 escrowAmount = IConfidentialEscrow(address(_escrow)).getAmount(escrowId);
        euint64 riskScore = IConfidentialUnderwriterPolicy(policy_).evaluateRisk(escrowId, riskProof);

        euint64 maxBps = FHE.asEuint64(10000);
        ebool isZero = FHE.eq(escrowAmount, FHE.asEuint64(0));
        euint64 divisor = FHE.select(isZero, FHE.asEuint64(1), escrowAmount);
        euint64 rawBps = FHE.div(FHE.mul(coverageAmount, riskScore), divisor);
        euint64 zeroIfNoEscrow = FHE.select(isZero, FHE.asEuint64(0), rawBps);
        ebool overCap = FHE.gt(zeroIfNoEscrow, maxBps);
        euint64 effectiveBps = FHE.select(overCap, maxBps, zeroIfNoEscrow);

        FHE.allowThis(effectiveBps);
        FHE.allowTransient(effectiveBps, address(_escrow));
        FHE.allow(holder, address(_escrow));
        IConfidentialEscrow(address(_escrow)).setUnderwriterFee(escrowId, holder, effectiveBps, pool_);
    }

    function _storeCoverage(
        uint256 coverageId,
        eaddress holder,
        address plaintextHolder,
        address sender,
        address pool_,
        address policy_,
        uint256 escrowId,
        euint64 coverageAmount,
        uint256 coverageExpiry
    ) private {
        _coverages[coverageId] = Coverage({
            holder: holder,
            plaintextHolder: plaintextHolder,
            pool: pool_,
            policy: policy_,
            escrowId: escrowId,
            coverageAmount: coverageAmount,
            expiry: coverageExpiry,
            status: CoverageStatus.Active
        });

        FHE.allowThis(holder);
        FHE.allow(holder, sender);
        FHE.allowThis(coverageAmount);
        FHE.allow(coverageAmount, sender);
    }

    function _forwardPayout(address pool_, euint64 payout, address recipient) private {
        IFHERC20 token = IConfidentialRecoursePool(pool_).paymentToken();
        FHE.allowTransient(payout, address(token));
        token.confidentialTransfer(recipient, payout);
    }
}
