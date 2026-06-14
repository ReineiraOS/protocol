// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 Reineira Labs Limited All rights reserved.
pragma solidity ^0.8.24;

/// @title IPoolFactoryEvents
/// @notice Events emitted by both plain and confidential pool factories.
/// @dev Centralized to keep event signatures aligned across IPoolFactory and IConfidentialPoolFactory.
interface IPoolFactoryEvents {
    /// @notice Emitted when a new pool is deployed
    /// @param poolId The newly assigned pool identifier
    /// @param pool The deployed pool address
    /// @param creator Immutable Pool Creator (factory caller)
    /// @param manager Pool Manager (defaults to creator when initialManager == address(0))
    /// @param guardian Pool Guardian (zero address allowed; no in-pool powers in v1)
    /// @param isOpen True for open pools (any buyer); false for private (voucher-gated)
    event PoolCreated(
        uint256 indexed poolId,
        address indexed pool,
        address indexed creator,
        address manager,
        address guardian,
        bool isOpen
    );

    /// @notice Emitted when a token is added to the allowlist
    /// @param token The token address that was allowed
    event TokenAllowed(address indexed token);

    /// @notice Emitted when a token is removed from the allowlist
    /// @param token The token address that was removed
    event TokenRemoved(address indexed token);
}
