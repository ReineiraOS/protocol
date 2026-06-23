// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 Reineira Labs Limited All rights reserved.
pragma solidity ^0.8.24;

/// @title IEscrowEvents
/// @notice Events emitted by both plain and confidential escrow engines.
/// @dev Centralized to keep event signatures aligned across IEscrow and IConfidentialEscrow.
interface IEscrowEvents {
    /// @notice Emitted when a new escrow is opened via `create`
    /// @param escrowId The newly assigned escrow identifier
    event EscrowCreated(uint256 indexed escrowId);

    /// @notice Emitted when an escrow receives a (possibly partial) deposit
    /// @param escrowId The funded escrow identifier
    /// @param payer The address that supplied the funds
    event EscrowFunded(uint256 indexed escrowId, address indexed payer);

    /// @notice Emitted when an escrow is redeemed
    /// @param escrowId The redeemed escrow identifier
    event EscrowRedeemed(uint256 indexed escrowId);

    /// @notice Emitted after a successful batch redemption
    /// @param escrowIds The escrow identifiers included in the batch
    event EscrowBatchRedeemed(uint256[] escrowIds);

    /// @notice Emitted when the coverage manager address is set or rotated
    /// @param coverageManager The newly assigned coverage manager
    event CoverageManagerSet(address indexed coverageManager);

    /// @notice Emitted when a payment token is added to the per-escrow allow-list
    /// @param token The token address that is now allowed at create
    event TokenAllowed(address indexed token);

    /// @notice Emitted when a payment token is removed from the per-escrow allow-list
    /// @param token The token address that is no longer allowed at create
    event TokenRemoved(address indexed token);

    /// @notice Emitted when a fee is stamped onto an escrow
    /// @dev For the confidential branch, `bps` is emitted as 0 (encrypted state cannot be in events).
    /// @param escrowId The escrow identifier
    /// @param kind The fee kind (FeeKind enum cast to uint8)
    /// @param bps The fee in basis points
    /// @param recipient The address that will receive the fee at redemption
    event FeeStamped(uint256 indexed escrowId, uint8 indexed kind, uint16 bps, address recipient);

    /// @notice Emitted on each fee transfer during redemption
    /// @dev For the confidential branch, `amount` is emitted as 0 (encrypted state cannot be in events).
    /// @param escrowId The escrow identifier
    /// @param kind The fee kind (FeeKind enum cast to uint8)
    /// @param amount The transferred fee amount
    /// @param recipient The address that received the fee
    event FeeDistributed(uint256 indexed escrowId, uint8 indexed kind, uint256 amount, address recipient);
}
