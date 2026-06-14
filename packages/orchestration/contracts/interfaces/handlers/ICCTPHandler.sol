// SPDX-License-Identifier: FSL-1.1-ALv2
// Copyright (c) 2026 Reineira Labs Limited All rights reserved.
pragma solidity ^0.8.24;

import {ITaskHandler} from "../core/ITaskHandler.sol";
import {ICCTPV2EscrowReceiver} from "@reineira-os/shared/contracts/interfaces/external/ICCTPV2EscrowReceiver.sol";

/// @title ICCTPHandler
/// @notice Interface for the CCTP relay task handler
/// @dev Extends ITaskHandler to settle escrows via Circle's CCTP V2 cross-chain transfers
interface ICCTPHandler is ITaskHandler {
    /// @notice The decoded payload structure for CCTP relay tasks
    /// @param message The CCTP V2 message bytes
    /// @param attestation The Circle attestation bytes
    struct CCTPPayload {
        bytes message;
        bytes attestation;
    }

    /// @notice Emitted when an escrow is settled through a CCTP relay task
    /// @param messageHash The keccak256 hash of the CCTP message
    /// @param escrowId The escrow that was settled
    /// @param amount The USDC amount transferred
    event EscrowSettled(bytes32 indexed messageHash, uint256 indexed escrowId, uint256 amount);

    /// @notice Emitted when the escrow receiver contract is updated
    /// @param oldReceiver The previous escrow receiver address
    /// @param newReceiver The new escrow receiver address
    event EscrowReceiverUpdated(address indexed oldReceiver, address indexed newReceiver);

    /// @notice Emitted when the executor authorized to call executeTask is updated
    /// @param oldExecutor The previous executor address
    /// @param newExecutor The new executor address
    event ExecutorUpdated(address indexed oldExecutor, address indexed newExecutor);

    /// @notice Thrown when the settlement call to the escrow receiver fails
    error SettlementFailed();

    /// @notice Sets the escrow receiver contract address
    /// @param receiver The new escrow receiver address
    function setEscrowReceiver(address receiver) external;

    /// @notice Returns the current escrow receiver contract
    function escrowReceiver() external view returns (ICCTPV2EscrowReceiver);
}
