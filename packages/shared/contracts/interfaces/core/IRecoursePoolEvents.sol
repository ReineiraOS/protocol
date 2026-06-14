// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 Reineira Labs Limited All rights reserved.
pragma solidity ^0.8.24;

/// @title IRecoursePoolEvents
/// @notice Events emitted by both plain and confidential recourse pools.
/// @dev Centralized to keep event signatures aligned across IRecoursePool and IConfidentialRecoursePool.
interface IRecoursePoolEvents {
    /// @notice Emitted when a new stake position is created
    /// @param stakeId The newly assigned stake identifier
    event Staked(uint256 indexed stakeId);

    /// @notice Emitted when a stake position is withdrawn
    /// @param stakeId The withdrawn stake identifier
    event Unstaked(uint256 indexed stakeId);

    /// @notice Emitted when a claim is paid out from the pool
    event ClaimPaid();

    /// @notice Emitted when a premium is received into the pool
    event PremiumReceived();

    /// @notice Emitted when a policy is added to the pool
    /// @param policy The policy contract address that was added
    event PolicyAdded(address indexed policy);

    /// @notice Emitted when a policy is removed from the pool
    /// @param policy The policy contract address that was removed
    event PolicyRemoved(address indexed policy);

    /// @notice Emitted when an LP claims their earned rewards
    /// @param stakeId The stake position the rewards were claimed for
    event RewardsClaimed(uint256 indexed stakeId);

    /// @notice Emitted when the pool Manager role is transferred to a new address
    /// @param previous Address that held the Manager role before this transfer
    /// @param next Address that now holds the Manager role
    event ManagerTransferred(address indexed previous, address indexed next);
}
