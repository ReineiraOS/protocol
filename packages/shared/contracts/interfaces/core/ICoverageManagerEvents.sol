// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 Reineira Labs Limited All rights reserved.
pragma solidity ^0.8.24;

/// @title ICoverageManagerEvents
/// @notice Events emitted by both plain and confidential coverage managers.
/// @dev Centralized to keep event signatures aligned across ICoverageManager and IConfidentialCoverageManager.
interface ICoverageManagerEvents {
    /// @notice Emitted when coverage is successfully purchased
    /// @param coverageId The newly assigned coverage identifier
    event CoveragePurchased(uint256 indexed coverageId);

    /// @notice Emitted when a dispute is filed against a coverage position
    /// @param coverageId The disputed coverage identifier
    event DisputeFiled(uint256 indexed coverageId);

    /// @notice Emitted when a dispute succeeds and the claim is paid
    /// @param coverageId The claimed coverage identifier
    event CoverageClaimed(uint256 indexed coverageId);

    /// @notice Emitted when coverage transitions to expired
    /// @param coverageId The expired coverage identifier
    event CoverageExpired(uint256 indexed coverageId);

    /// @notice Emitted when a closed-pool coverage invite is consumed
    /// @param pool The pool the invite authorizes purchase on
    /// @param digest The EIP-712 digest used as the invite usage-tracking key
    /// @param invitee The address consuming the invite (matches signed `invite.invitee`)
    event InviteConsumed(address indexed pool, bytes32 indexed digest, address indexed invitee);

    /// @notice Emitted when a closed-pool coverage invite is revoked
    /// @param pool The pool the invite authorized purchase on
    /// @param digest The EIP-712 digest identifying the invite
    /// @param by The address that revoked the invite (must be `pool.manager()`)
    event InviteRevoked(address indexed pool, bytes32 indexed digest, address by);
}
