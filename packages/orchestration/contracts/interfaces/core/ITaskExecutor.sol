// SPDX-License-Identifier: FSL-1.1-ALv2
// Copyright (c) 2026 Reineira Labs Limited All rights reserved.
pragma solidity ^0.8.24;

import {IOperatorRegistry} from "./IOperatorRegistry.sol";

/// @title ITaskExecutor
/// @notice Interface for the central task routing and execution engine
/// @dev Routes tasks to domain-specific handlers, enforces operator authorization, and collects fees
interface ITaskExecutor {
    /// @notice Emitted when a task is successfully executed
    /// @param taskType The type identifier of the executed task
    /// @param taskHash The unique hash of the executed task
    /// @param operator The operator who executed the task
    /// @param operatorFee The fee paid to the operator for execution
    event TaskExecuted(
        bytes32 indexed taskType,
        bytes32 indexed taskHash,
        address indexed operator,
        uint256 operatorFee
    );

    /// @notice Emitted when a new handler is registered for a task type
    /// @param taskType The task type the handler is registered for
    /// @param handler The handler contract address
    event HandlerRegistered(bytes32 indexed taskType, address indexed handler);

    /// @notice Emitted when a handler is removed for a task type
    /// @param taskType The task type whose handler was removed
    event HandlerRemoved(bytes32 indexed taskType);

    /// @notice Emitted when the operator registry is updated
    /// @param oldRegistry The previous registry address
    /// @param newRegistry The new registry address
    event RegistryUpdated(address indexed oldRegistry, address indexed newRegistry);

    /// @notice Emitted when the fee manager is updated
    /// @param oldFeeManager The previous fee manager address
    /// @param newFeeManager The new fee manager address
    event FeeManagerUpdated(address indexed oldFeeManager, address indexed newFeeManager);

    /// @notice Thrown when the caller is not an authorized operator for the task
    error NotAuthorizedOperator();

    /// @notice Thrown when no handler is registered for the given task type
    error UnknownTaskType();

    /// @notice Thrown when the handler's taskType() does not match the registered type
    error InvalidHandler();

    /// @notice Thrown when a zero address is provided where a valid address is required
    error ZeroAddress();

    /// @notice Thrown when handler execution reverts
    error HandlerExecutionFailed();

    /// @notice Executes a task by routing it to the appropriate handler
    /// @param taskType The type identifier selecting the handler
    /// @param payload The task-specific payload passed to the handler
    /// @return result The handler's return data
    function executeTask(bytes32 taskType, bytes calldata payload) external returns (bytes memory result);

    /// @notice Registers a handler contract for a specific task type
    /// @param taskType The task type to register the handler for
    /// @param handler The handler contract address (must implement ITaskHandler)
    function registerHandler(bytes32 taskType, address handler) external;

    /// @notice Removes the handler for a specific task type
    /// @param taskType The task type to remove the handler for
    function removeHandler(bytes32 taskType) external;

    /// @notice Updates the operator registry contract
    /// @param registry_ The new registry address
    function setRegistry(address registry_) external;

    /// @notice Updates the fee manager contract
    /// @param feeManager The new fee manager address
    function setFeeManager(address feeManager) external;

    /// @notice Returns the handler address for a given task type
    /// @param taskType The task type to query
    /// @return The handler contract address (zero address if none registered)
    function getHandler(bytes32 taskType) external view returns (address);

    /// @notice Returns the operator registry contract
    function registry() external view returns (IOperatorRegistry);
}
