// SPDX-License-Identifier: FSL-1.1-ALv2
// Copyright (c) 2026 Reineira Labs Limited All rights reserved.
pragma solidity ^0.8.25;

/// @title ICCTPV2EscrowReceiver
/// @notice Receives cross-chain USDC via CCTP V2 and settles escrow payments
interface ICCTPV2ConfidentialEscrowReceiver {
    /// @notice Thrown when the referenced escrow does not exist
    /// @param escrowId The escrow identifier that was not found
    error EscrowNotFound(uint256 escrowId);

    /// @notice Thrown when an address parameter is the zero address
    error ZeroAddress();

    /// @notice Thrown when an amount parameter is zero
    error ZeroAmount();

    /// @notice Thrown when the CCTP message receive call fails
    error MessageReceiveFailed();

    /// @notice Thrown when hook data cannot be decoded
    error MalformedHookData();

    /// @notice Emitted when an escrow is settled via a cross-chain USDC transfer
    /// @param escrowId The settled escrow identifier
    /// @param relayer The address that relayed the settlement
    /// @param usdcReceived The amount of USDC received from the source chain
    /// @param confidentialAmountPaid The encrypted amount credited to the escrow
    event EscrowSettled(
        uint256 indexed escrowId,
        address indexed relayer,
        uint256 usdcReceived,
        uint64 confidentialAmountPaid
    );

    /// @notice Settles an escrow by receiving a CCTP V2 message and attestation
    /// @param message The CCTP message bytes from the source chain
    /// @param attestation The Circle attestation proving message validity
    function settle(bytes calldata message, bytes calldata attestation) external;

    /// @notice Encodes an escrow identifier into hook data for CCTP V2 messages
    /// @param escrowId The escrow identifier to encode
    /// @return The ABI-encoded hook data
    function buildHookData(uint256 escrowId) external pure returns (bytes memory);
}
