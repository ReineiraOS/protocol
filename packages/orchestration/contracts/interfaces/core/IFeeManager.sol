// SPDX-License-Identifier: FSL-1.1-ALv2
// Copyright (c) 2026 Reineira Labs Limited All rights reserved.
pragma solidity ^0.8.24;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/// @title IFeeManager
/// @notice Interface for operator fee calculation and collection
/// @dev Pays the executing operator on each task. The protocol takes no fee.
interface IFeeManager {
    /// @notice Emitted when the operator fee is collected for a completed task
    /// @param taskHash The unique hash identifying the executed task
    /// @param operator The operator who executed the task and receives the fee
    /// @param operatorFee The fee amount paid to the operator
    event FeeCollected(bytes32 indexed taskHash, address indexed operator, uint256 operatorFee);

    /// @notice Emitted when the operator fee basis points configuration is updated
    /// @param operatorFeeBps The new operator fee in basis points
    event FeeConfigUpdated(uint256 operatorFeeBps);

    /// @notice Emitted when the authorized fee collector address is updated
    /// @param oldCollector The previous fee collector address
    /// @param newCollector The new fee collector address
    event FeeCollectorUpdated(address indexed oldCollector, address indexed newCollector);

    /// @notice Emitted when the fee token is updated
    /// @param oldToken The previous fee token address
    /// @param newToken The new fee token address
    event FeeTokenUpdated(address indexed oldToken, address indexed newToken);

    /// @notice Thrown when fee basis points exceed the maximum allowed (10000 = 100%)
    error InvalidFeeConfig();

    /// @notice Thrown when a zero address is provided where a valid address is required
    error ZeroAddress();

    /// @notice Calculates the operator fee for a given amount
    /// @param amount The base amount to calculate the fee on
    /// @return operatorFee The operator's fee
    function calculateFee(uint256 amount) external view returns (uint256 operatorFee);

    /// @notice Collects the operator fee for a completed task, transferring it immediately
    /// @param taskHash The unique hash identifying the task
    /// @param operator The operator address to receive the fee
    /// @param amount The base amount to calculate and collect the fee on
    function collectFee(bytes32 taskHash, address operator, uint256 amount) external;

    /// @notice Updates the operator fee basis points
    /// @param operatorFeeBps_ The new operator fee in basis points
    function setFeeConfig(uint256 operatorFeeBps_) external;

    /// @notice Sets the address authorized to call collectFee
    /// @param collector The new fee collector address (typically TaskExecutor)
    function setFeeCollector(address collector) external;

    /// @notice Sets the ERC20 token used for fee payments
    /// @param token The new fee token address
    function setFeeToken(address token) external;

    /// @notice Returns the ERC20 token used for fee payments
    function feeToken() external view returns (IERC20);

    /// @notice Returns the address authorized to collect fees
    function feeCollector() external view returns (address);

    /// @notice Returns the operator fee in basis points
    function operatorFeeBps() external view returns (uint256);
}
