// SPDX-License-Identifier: FSL-1.1-ALv2
// Copyright (c) 2026 Reineira Labs Limited All rights reserved.
pragma solidity ^0.8.25;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ICCTPV2MessageTransmitter} from "@reineira-os/shared/contracts/interfaces/external/ICCTPV2MessageTransmitter.sol";

/// @title ICCTPV2Forwarder
/// @notice Interface for receiving cross-chain USDC via CCTP V2 and forwarding to recipients
/// @dev Used on non-FHE chains to receive CCTP transfers and forward USDC to specified recipients
interface ICCTPV2Forwarder {
    /// @notice Emitted when a CCTP message is successfully received
    /// @param messageHash The hash of the received CCTP message
    /// @param recipient The address that will receive the forwarded tokens
    /// @param amount The amount of USDC received
    event MessageReceived(bytes32 indexed messageHash, address indexed recipient, uint256 amount);

    /// @notice Emitted when tokens are forwarded to the recipient
    /// @param recipient The address that received the tokens
    /// @param amount The amount of USDC forwarded
    event TokensForwarded(address indexed recipient, uint256 amount);

    /// @notice Thrown when an invalid CCTP transmitter address is provided
    error InvalidTransmitter();

    /// @notice Thrown when an invalid USDC token address is provided
    error InvalidUsdc();

    /// @notice Thrown when the CCTP message receive operation fails
    error MessageReceiveFailed();

    /// @notice Thrown when a zero address is provided where a valid address is required
    error ZeroAddress();

    /// @notice Thrown when a zero amount is provided where a positive amount is required
    error ZeroAmount();

    /// @notice Receives a CCTP V2 message and forwards the USDC to the specified recipient
    /// @param message The CCTP message containing the transfer details
    /// @param attestation The Circle attestation proving the message validity
    /// @param recipient The address to forward the received USDC to
    /// @return amount The amount of USDC received and forwarded
    function receiveAndForward(
        bytes calldata message,
        bytes calldata attestation,
        address recipient
    ) external returns (uint256 amount);

    /// @notice Returns the CCTP V2 message transmitter contract
    /// @return The ICCTPV2MessageTransmitter contract used for receiving messages
    function cctpV2Transmitter() external view returns (ICCTPV2MessageTransmitter);

    /// @notice Returns the USDC token contract
    /// @return The IERC20 USDC token contract
    function usdc() external view returns (IERC20);
}
