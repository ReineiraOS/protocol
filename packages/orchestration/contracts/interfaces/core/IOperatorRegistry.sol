// SPDX-License-Identifier: FSL-1.1-ALv2
// Copyright (c) 2026 Reineira Labs Limited All rights reserved.
pragma solidity ^0.8.24;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/// @title IOperatorRegistry
/// @notice Interface for operator registration, staking, task claiming, and slashing
/// @dev Manages the lifecycle of operators in the Reineira orchestration network
interface IOperatorRegistry {
    /// @notice On-chain state for a registered operator
    /// @param stake The amount of tokens staked by the operator
    /// @param unbondRequestTime The timestamp when unbonding was requested (0 if not unbonding)
    /// @param isActive Whether the operator is currently active and eligible for tasks
    /// @param slashed Whether the operator has been permanently slashed
    struct OperatorInfo {
        uint256 stake;
        uint256 unbondRequestTime;
        bool isActive;
        bool slashed;
    }

    /// @notice On-chain state for a claimed task
    /// @param operator The operator who claimed the task
    /// @param claimTime The timestamp when the task was claimed
    /// @param executed Whether the task has been executed
    struct TaskClaim {
        address operator;
        uint256 claimTime;
        bool executed;
    }

    /// @notice Emitted when a new operator registers with a stake
    /// @param operator The address of the newly registered operator
    /// @param stake The amount of tokens staked at registration
    event OperatorRegistered(address indexed operator, uint256 stake);

    /// @notice Emitted when an operator adds additional stake
    /// @param operator The operator adding stake
    /// @param amount The additional amount staked
    event StakeAdded(address indexed operator, uint256 amount);

    /// @notice Emitted when an operator requests to unbond their stake
    /// @param operator The operator requesting unbonding
    /// @param unlockTime The timestamp after which stake can be withdrawn
    event UnbondRequested(address indexed operator, uint256 unlockTime);

    /// @notice Emitted when an operator withdraws their unbonded stake
    /// @param operator The operator withdrawing
    /// @param amount The amount of tokens withdrawn
    event StakeWithdrawn(address indexed operator, uint256 amount);

    /// @notice Emitted when an operator claims a task for exclusive execution
    /// @param taskHash The hash identifying the claimed task
    /// @param operator The operator claiming the task
    event TaskClaimed(bytes32 indexed taskHash, address indexed operator);

    /// @notice Emitted when a claimed task is marked as executed
    /// @param taskHash The hash identifying the executed task
    /// @param operator The operator who executed the task
    event TaskExecuted(bytes32 indexed taskHash, address indexed operator);

    /// @notice Emitted when an operator is slashed
    /// @param operator The slashed operator
    /// @param amount The amount of stake slashed
    /// @param evidence The evidence hash justifying the slash
    event OperatorSlashed(address indexed operator, uint256 amount, bytes32 indexed evidence);

    /// @notice Emitted when the monitor address is updated
    /// @param oldMonitor The previous monitor address
    /// @param newMonitor The new monitor address
    event MonitorUpdated(address indexed oldMonitor, address indexed newMonitor);

    /// @notice Emitted when the slashing manager address is updated
    /// @param oldManager The previous slashing manager address
    /// @param newManager The new slashing manager address
    event SlashingManagerUpdated(address indexed oldManager, address indexed newManager);

    /// @notice Emitted when operator system configuration is updated
    /// @param minStake The new minimum stake requirement
    /// @param exclusiveWindow The new exclusive claim window in seconds
    /// @param permissionlessDelay The new permissionless delay in seconds
    event ConfigUpdated(uint256 minStake, uint256 exclusiveWindow, uint256 permissionlessDelay);

    /// @notice Thrown when the provided stake is below the minimum requirement
    error InsufficientStake();

    /// @notice Thrown when an operator tries to register but is already registered
    error AlreadyRegistered();

    /// @notice Thrown when an action requires a registered operator but the caller is not
    error NotRegistered();

    /// @notice Thrown when an action requires an active operator but the caller is not
    error NotActive();

    /// @notice Thrown when an operator tries to unbond while already unbonding
    error UnbondingInProgress();

    /// @notice Thrown when an operator tries to withdraw before the unbond period completes
    error UnbondingNotComplete();

    /// @notice Thrown when an operator tries to withdraw without an active unbond request
    error NoUnbondRequest();

    /// @notice Thrown when a task has already been claimed by another operator
    error TaskAlreadyClaimed();

    /// @notice Thrown when the caller is not authorized for the requested action
    error NotAuthorized();

    /// @notice Thrown when a non-claiming operator tries to execute during the exclusive window
    error ExclusiveWindowActive();

    /// @notice Thrown when trying to execute a task that has already been executed
    error TaskAlreadyExecuted();

    /// @notice Thrown when a zero address is provided where a valid address is required
    error ZeroAddress();

    /// @notice Thrown when a zero amount is provided where a positive amount is required
    error ZeroAmount();

    /// @notice Thrown when a slashed operator tries to re-register
    error PermanentlySlashed();

    /// @notice Thrown when a sanctioned address attempts to register
    error Sanctioned();

    /// @notice Registers a new operator with the specified stake amount
    /// @param amount The amount of staking tokens to deposit
    function registerOperator(uint256 amount) external;

    /// @notice Adds additional stake to an existing operator's position
    /// @param amount The additional amount to stake
    function addStake(uint256 amount) external;

    /// @notice Initiates the unbonding process for the caller's stake
    function requestUnbond() external;

    /// @notice Withdraws stake after the unbond period has completed
    function withdrawStake() external;

    /// @notice Claims a task for exclusive execution during the exclusive window
    /// @param taskHash The hash identifying the task to claim
    function claimTask(bytes32 taskHash) external;

    /// @notice Marks a task as executed (called by TaskExecutor)
    /// @param taskHash The hash identifying the executed task
    /// @param operator The operator who executed the task
    function markExecuted(bytes32 taskHash, address operator) external;

    /// @notice Slashes an operator's stake (called by SlashingManager)
    /// @param operator The operator to slash
    /// @param amount The amount of stake to slash
    /// @param evidence The evidence hash justifying the slash
    function slash(address operator, uint256 amount, bytes32 evidence) external;

    /// @notice Sets the monitor address (typically TaskExecutor)
    /// @param monitor The new monitor address
    function setMonitor(address monitor) external;

    /// @notice Sets the slashing manager contract address
    /// @param slashingManager The new slashing manager address
    function setSlashingManager(address slashingManager) external;

    /// @notice Updates the operator system configuration
    /// @param minStake The new minimum stake requirement
    /// @param exclusiveWindow The new exclusive claim window in seconds
    /// @param permissionlessDelay The new permissionless delay in seconds
    function setConfig(uint256 minStake, uint256 exclusiveWindow, uint256 permissionlessDelay) external;

    /// @notice Sets the sanctions oracle contract for compliance checks
    /// @param oracle The new sanctions oracle address
    function setSanctionsOracle(address oracle) external;

    /// @notice Returns the full operator info for a given address
    /// @param operator The operator address to query
    /// @return The OperatorInfo struct for the operator
    function getOperatorInfo(address operator) external view returns (OperatorInfo memory);

    /// @notice Returns the task claim info for a given task hash
    /// @param taskHash The task hash to query
    /// @return The TaskClaim struct for the task
    function getTaskClaim(bytes32 taskHash) external view returns (TaskClaim memory);

    /// @notice Checks whether an operator is currently active
    /// @param operator The operator address to check
    /// @return True if the operator is active
    function isOperatorActive(address operator) external view returns (bool);

    /// @notice Checks whether a caller can execute a specific task based on authorization tiers
    /// @param caller The address attempting to execute
    /// @param taskHash The task hash to check authorization for
    /// @return True if the caller is authorized to execute the task
    function canExecuteTask(address caller, bytes32 taskHash) external view returns (bool);

    /// @notice Returns the list of all active operator addresses
    /// @return An array of active operator addresses
    function getActiveOperators() external view returns (address[] memory);

    /// @notice Returns the number of currently active operators
    /// @return The active operator count
    function activeOperatorCount() external view returns (uint256);

    /// @notice Returns the ERC20 token used for staking
    function stakingToken() external view returns (IERC20);
}
