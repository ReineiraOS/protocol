// SPDX-License-Identifier: FSL-1.1-ALv2
// Copyright (c) 2026 Reineira Labs Limited All rights reserved.
pragma solidity ^0.8.24;

import {IERC20} from "@openzeppelin/contracts/interfaces/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {SafeCast} from "@openzeppelin/contracts/utils/math/SafeCast.sol";
import {ICoverageManager} from "../interfaces/core/ICoverageManager.sol";
import {IPoolFactory} from "../interfaces/core/IPoolFactory.sol";
import {IRecoursePool} from "../interfaces/core/IRecoursePool.sol";
import {IUnderwriterPolicy} from "@reineira-os/shared/contracts/interfaces/plugins/IUnderwriterPolicy.sol";
import {IEscrow} from "../interfaces/external/IEscrow.sol";
import {TestnetCoreBase} from "@reineira-os/shared/contracts/common/TestnetCoreBase.sol";
import {CoverageLib} from "@reineira-os/shared/contracts/libraries/CoverageLib.sol";
import {CoverageInviteLib} from "@reineira-os/shared/contracts/libraries/CoverageInviteLib.sol";

contract CoverageManager is ICoverageManager, TestnetCoreBase {
    using SafeERC20 for IERC20;

    uint256 public constant MAX_COVERAGES_PER_ESCROW = 5;

    struct Coverage {
        address holder;
        address pool;
        address policy;
        uint256 escrowId;
        uint256 coverageAmount;
        uint256 expiry;
        CoverageStatus status;
    }

    IEscrow private _escrow;
    IPoolFactory private _poolFactory;

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

        _poolFactory = IPoolFactory(poolFactory_);

        emit CoreInitialized(owner_);
    }

    function setEscrow(address escrow_) external onlyOwner {
        if (escrow_ == address(0)) revert ZeroAddress();
        _escrow = IEscrow(escrow_);
    }

    function setPoolFactory(address poolFactory_) external onlyOwner {
        if (poolFactory_ == address(0)) revert ZeroAddress();
        _poolFactory = IPoolFactory(poolFactory_);
    }

    function purchaseCoverage(
        address holder_,
        address pool_,
        address policy_,
        uint256 escrowId,
        uint256 coverageAmount_,
        uint256 coverageExpiry,
        bytes calldata policyData,
        bytes calldata riskProof
    ) external nonReentrant returns (uint256 coverageId) {
        CoverageInviteLib.CoverageInvite memory emptyInvite;
        return
            _purchaseCoverage(
                holder_,
                pool_,
                policy_,
                escrowId,
                coverageAmount_,
                coverageExpiry,
                policyData,
                riskProof,
                emptyInvite,
                ""
            );
    }

    function purchaseCoverage(
        address holder_,
        address pool_,
        address policy_,
        uint256 escrowId,
        uint256 coverageAmount_,
        uint256 coverageExpiry,
        bytes calldata policyData,
        bytes calldata riskProof,
        CoverageInviteLib.CoverageInvite calldata invite,
        bytes calldata inviteSig
    ) external nonReentrant returns (uint256 coverageId) {
        return
            _purchaseCoverage(
                holder_,
                pool_,
                policy_,
                escrowId,
                coverageAmount_,
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
        CoverageLib.validateHolder(cov.holder, _msgSender());

        if (block.timestamp >= cov.expiry) {
            cov.status = CoverageStatus.Expired;
            emit CoverageExpired(coverageId);
            revert CoverageLib.NotActiveStatus();
        }

        if (_coveragePaid[cov.escrowId][coverageId]) revert CoverageLib.CoverageAlreadyPaid();

        cov.status = CoverageStatus.Claimed;
        emit DisputeFiled(coverageId);

        bool valid = IUnderwriterPolicy(cov.policy).judge(coverageId, disputeProof);
        if (!valid) revert CoverageLib.DisputeRejected();

        uint256 actualPayout = IRecoursePool(cov.pool).payClaim(coverageId, cov.coverageAmount);

        _forwardPayout(cov.pool, actualPayout, cov.holder);

        _coveragePaid[cov.escrowId][coverageId] = true;
        emit CoverageClaimed(coverageId);
    }

    function revokeInvite(address pool_, bytes32 digest) external {
        if (_msgSender() != IRecoursePool(pool_).manager()) revert CoverageLib.NotManager();
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

    function _purchaseCoverage(
        address holder_,
        address pool_,
        address policy_,
        uint256 escrowId,
        uint256 coverageAmount_,
        uint256 coverageExpiry,
        bytes calldata policyData,
        bytes calldata riskProof,
        CoverageInviteLib.CoverageInvite memory invite,
        bytes memory inviteSig
    ) private returns (uint256 coverageId) {
        bytes32 digest = _validatePurchase(holder_, pool_, policy_, escrowId, coverageExpiry, invite, inviteSig);

        coverageId = _nextCoverageId++;
        IUnderwriterPolicy(policy_).onPolicySet(coverageId, policyData);

        _finalizePurchase(coverageId, holder_, pool_, policy_, escrowId, coverageAmount_, coverageExpiry, riskProof);
        _escrowCoverages[escrowId].push(coverageId);

        if (digest != bytes32(0)) {
            _consumeInvite(pool_, digest, _msgSender());
        }

        emit CoveragePurchased(coverageId);
    }

    function _validatePurchase(
        address holder_,
        address pool_,
        address policy_,
        uint256 escrowId,
        uint256 coverageExpiry,
        CoverageInviteLib.CoverageInvite memory invite,
        bytes memory inviteSig
    ) private view returns (bytes32 digest) {
        if (address(_escrow) == address(0)) revert CoverageLib.EscrowNotConfigured();
        if (address(_poolFactory) == address(0)) revert CoverageLib.PoolFactoryNotConfigured();
        if (holder_ == address(0)) revert ZeroAddress();
        if (!_poolFactory.isPool(pool_)) revert CoverageLib.InvalidPool();
        if (!IRecoursePool(pool_).isPolicy(policy_)) revert CoverageLib.InvalidPolicy();
        CoverageLib.validateExpiry(coverageExpiry, block.timestamp);
        if (!_escrow.exists(escrowId)) revert CoverageLib.EscrowDoesNotExist();
        if (_escrowCoverages[escrowId].length >= MAX_COVERAGES_PER_ESCROW) revert CoverageLib.MaxCoveragesReached();

        if (!IRecoursePool(pool_).isOpen()) {
            if (invite.pool != pool_) revert CoverageLib.InvitePoolMismatch();
            if (invite.invitee != _msgSender()) revert CoverageLib.InviteeMismatch();
            if (block.timestamp > invite.deadline) revert CoverageLib.InviteExpired();
            if (invite.maxUses == 0) revert CoverageLib.InviteExhausted();

            bytes32 ds = IRecoursePool(pool_).domainSeparator();
            digest = CoverageInviteLib.digest(ds, invite);

            if (_revoked[digest]) revert CoverageLib.InviteAlreadyRevoked();
            if (_usedCount[digest] >= invite.maxUses) revert CoverageLib.InviteExhausted();

            address signer = CoverageInviteLib.recoverSigner(ds, invite, inviteSig);
            if (signer != IRecoursePool(pool_).manager()) revert CoverageLib.InviteSignerMismatch();
        }
    }

    function _consumeInvite(address pool_, bytes32 digest, address invitee) private {
        _usedCount[digest] += 1;
        emit InviteConsumed(pool_, digest, invitee);
    }

    function _finalizePurchase(
        uint256 coverageId,
        address holder_,
        address pool_,
        address policy_,
        uint256 escrowId,
        uint256 coverageAmount_,
        uint256 coverageExpiry,
        bytes calldata riskProof
    ) private {
        uint256 cappedCoverage = _capCoverage(coverageAmount_, escrowId);
        _computeAndSetFee(policy_, escrowId, cappedCoverage, holder_, pool_, riskProof);
        _storeCoverage(coverageId, holder_, pool_, policy_, escrowId, cappedCoverage, coverageExpiry);
    }

    function _capCoverage(uint256 coverageAmount_, uint256 escrowId) private view returns (uint256) {
        uint256 escrowAmount = _escrow.getAmount(escrowId);
        return coverageAmount_ <= escrowAmount ? coverageAmount_ : escrowAmount;
    }

    function _computeAndSetFee(
        address policy_,
        uint256 escrowId,
        uint256 coverageAmount_,
        address holder_,
        address pool_,
        bytes calldata riskProof
    ) private {
        uint256 escrowAmount = _escrow.getAmount(escrowId);
        if (escrowAmount == 0) return;

        uint256 riskScore = IUnderwriterPolicy(policy_).evaluateRisk(escrowId, riskProof);
        uint256 effectiveBps = (coverageAmount_ * riskScore) / escrowAmount;
        if (effectiveBps > 10000) effectiveBps = 10000;

        _escrow.setUnderwriterFee(escrowId, holder_, SafeCast.toUint16(effectiveBps), pool_);
    }

    function _storeCoverage(
        uint256 coverageId,
        address holder_,
        address pool_,
        address policy_,
        uint256 escrowId,
        uint256 coverageAmount_,
        uint256 coverageExpiry
    ) private {
        _coverages[coverageId] = Coverage({
            holder: holder_,
            pool: pool_,
            policy: policy_,
            escrowId: escrowId,
            coverageAmount: coverageAmount_,
            expiry: coverageExpiry,
            status: CoverageStatus.Active
        });
    }

    function _forwardPayout(address pool_, uint256 payout, address recipient) private {
        if (payout == 0) return;
        IERC20 token = IRecoursePool(pool_).paymentToken();
        token.safeTransfer(recipient, payout);
    }
}
