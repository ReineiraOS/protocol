// SPDX-License-Identifier: FSL-1.1-ALv2
// Copyright (c) 2026 Reineira Labs Limited All rights reserved.
pragma solidity ^0.8.24;

import {ICore} from "@reineira-os/shared/contracts/interfaces/core/ICore.sol";
import {ICoverageManagerEvents} from "@reineira-os/shared/contracts/interfaces/core/ICoverageManagerEvents.sol";
import {CoverageInviteLib} from "@reineira-os/shared/contracts/libraries/CoverageInviteLib.sol";

/// @title ICoverageManager — Coverage purchase and dispute hub (plain variant)
/// @notice Buyers purchase coverage permissionlessly against any open RecoursePool.
///         Private (closed) pools require an EIP-712 voucher signed by the pool Manager
///         per whitepaper §7.10. The pool's IUnderwriterPolicy gates risk evaluation
///         and dispute resolution. For the confidential variant, see IConfidentialCoverageManager.
interface ICoverageManager is ICore, ICoverageManagerEvents {
    /// @notice Lifecycle states of a coverage position
    enum CoverageStatus {
        None,
        Active,
        Disputed,
        Claimed,
        Expired
    }

    /// @notice Purchases coverage for an escrow (open-pool entry point)
    /// @dev Thin wrapper that calls the voucher-aware overload with an empty invite.
    ///      Pools where `isOpen() == false` will revert via the voucher-aware overload's
    ///      signer-mismatch check — closed-pool buyers must use the 10-arg overload.
    function purchaseCoverage(
        address holder,
        address pool,
        address policy,
        uint256 escrowId,
        uint256 coverageAmount,
        uint256 coverageExpiry,
        bytes calldata policyData,
        bytes calldata riskProof
    ) external returns (uint256 coverageId);

    /// @notice Purchases coverage for an escrow with optional closed-pool voucher
    /// @dev Validation flow:
    ///      1. Standard checks: escrow exists & uncovered; pool is factory-deployed; policy allowed.
    ///      2. If `pool.isOpen() == false`: validate voucher. Build EIP-712 digest from
    ///         `pool.domainSeparator()` and `invite`; require `invite.pool == pool`,
    ///         `invite.invitee == _msgSender()`, `block.timestamp <= invite.deadline`,
    ///         `invite.maxUses > 0`, `!isInviteRevoked(digest)`,
    ///         `usedCount(digest) < invite.maxUses`, and
    ///         `CoverageInviteLib.recoverSigner(...) == pool.manager()`.
    ///         Increments `_usedCount[digest]` and emits `InviteConsumed`.
    ///      3. Calls `policy.onPolicySet`, `policy.evaluateRisk`, stamps escrow underwriter fee,
    ///         registers coverage.
    /// @param holder Address of the coverage holder
    /// @param pool The RecoursePool backing this coverage
    /// @param policy The IUnderwriterPolicy to evaluate risk (must be allowed on pool)
    /// @param escrowId The escrow being insured
    /// @param coverageAmount Coverage amount
    /// @param coverageExpiry Timestamp when coverage expires
    /// @param policyData Policy-specific data passed to policy.onPolicySet() (e.g., dispute identifier)
    /// @param riskProof Proof data passed to policy.evaluateRisk() (e.g., zkFetch attestation)
    /// @param invite EIP-712 coverage-invite struct (ignored when `pool.isOpen() == true`)
    /// @param inviteSig Manager's signature over `invite` (ignored when `pool.isOpen() == true`)
    /// @return coverageId Coverage identifier
    function purchaseCoverage(
        address holder,
        address pool,
        address policy,
        uint256 escrowId,
        uint256 coverageAmount,
        uint256 coverageExpiry,
        bytes calldata policyData,
        bytes calldata riskProof,
        CoverageInviteLib.CoverageInvite calldata invite,
        bytes calldata inviteSig
    ) external returns (uint256 coverageId);

    /// @notice Files a dispute against active coverage
    /// @dev Calls policy.judge(). If valid: pool pays claim, escrow blocked.
    ///      If invalid: reverts with DisputeRejected.
    /// @param coverageId The coverage to dispute
    /// @param disputeProof Opaque proof bytes passed to the policy judge
    function dispute(uint256 coverageId, bytes calldata disputeProof) external;

    /// @notice Revokes a previously-signed coverage invite (Pool Manager only)
    /// @dev Idempotent: revoking an already-revoked digest reverts with `InviteAlreadyRevoked`.
    /// @param pool The pool the invite was authorized against
    /// @param digest The EIP-712 digest identifying the invite (as returned by
    ///        `CoverageInviteLib.digest(pool.domainSeparator(), invite)`)
    function revokeInvite(address pool, bytes32 digest) external;

    /// @notice Returns the escrow contract address
    function escrow() external view returns (address);

    /// @notice Sets the escrow contract address
    /// @dev Set via setter (not initialize) to resolve circular dependency with Escrow
    /// @param escrow_ The escrow contract address
    function setEscrow(address escrow_) external;

    /// @notice Sets the pool factory contract address
    /// @param poolFactory_ The pool factory contract address
    function setPoolFactory(address poolFactory_) external;

    /// @notice Returns the PoolFactory used to validate pools
    function poolFactory() external view returns (address);

    /// @notice Returns the current status of a coverage position
    /// @param coverageId The coverage to query
    function coverageStatus(uint256 coverageId) external view returns (CoverageStatus);

    /// @notice Returns the number of times a coverage invite (identified by its EIP-712
    ///         digest) has been consumed via `purchaseCoverage`
    /// @param digest The EIP-712 digest identifying the invite
    function usedCount(bytes32 digest) external view returns (uint256);

    /// @notice Returns true if a coverage invite has been revoked by the Pool Manager
    /// @param digest The EIP-712 digest identifying the invite
    function isInviteRevoked(bytes32 digest) external view returns (bool);
}
