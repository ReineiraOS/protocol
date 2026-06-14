// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 Reineira Labs Limited All rights reserved.
pragma solidity ^0.8.24;

/// @title ICore — Base interface for all upgradeable protocol contracts
/// @notice Defines the shared `CoreInitialized` event and the common errors that every
///         protocol contract emits on initialization. All concrete contract interfaces
///         (escrow, recourse, orchestration) inherit this interface to advertise the
///         shared lifecycle signal and error surface.
/// @dev Implementations emit `CoreInitialized(owner)` from their `initialize` function
///      (named distinctly from OpenZeppelin's `Initialized(uint8)` to avoid ABI conflict).
interface ICore {
    /// @notice Emitted when the protocol contract is initialized
    /// @param owner The initial owner address that received `OwnableUpgradeable` ownership
    event CoreInitialized(address indexed owner);

    /// @notice Thrown when a zero address is provided where a non-zero address is required
    error ZeroAddress();

    /// @notice Thrown when caller lacks the role / permission required for the operation
    error Unauthorized();
}
