// SPDX-License-Identifier: FSL-1.1-ALv2
// Copyright (c) 2026 Reineira Labs Limited All rights reserved.
pragma solidity ^0.8.24;

/// @title ITaskHandler
/// @notice Interface for domain-specific task execution handlers
/// @dev Each handler implements a single task type (e.g., CCTP relay, automation, agent calls)
interface ITaskHandler {
    /// @notice Executes the task with the given payload
    /// @param payload The task-specific encoded data
    /// @return result The encoded execution result
    function executeTask(bytes calldata payload) external returns (bytes memory result);

    /// @notice Validates whether a payload is well-formed for this handler
    /// @param payload The task-specific encoded data to validate
    /// @return valid True if the payload is valid
    function validateTask(bytes calldata payload) external view returns (bool valid);

    /// @notice Computes the unique task hash from the payload
    /// @param payload The task-specific encoded data
    /// @return taskHash The unique hash identifying this task
    function getTaskHash(bytes calldata payload) external pure returns (bytes32 taskHash);

    /// @notice Returns the task type identifier this handler supports
    /// @return The bytes32 task type constant
    function taskType() external view returns (bytes32);
}
