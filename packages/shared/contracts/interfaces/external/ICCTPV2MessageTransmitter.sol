// SPDX-License-Identifier: BSD-3-Clause-Clear
pragma solidity ^0.8.24;

/// @title ICCTPV2MessageTransmitter
/// @notice Interface for Circle's CCTP V2 MessageTransmitter contract
/// @dev Used to receive and validate cross-chain messages attested by Circle
interface ICCTPV2MessageTransmitter {
    /// @notice Receives and validates a cross-chain CCTP message
    /// @param message The encoded CCTP message from the source chain
    /// @param attestation The Circle attestation proving the message was sent
    /// @return success True if the message was successfully received and processed
    function receiveMessage(bytes calldata message, bytes calldata attestation) external returns (bool success);
}
