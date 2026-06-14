// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 Reineira Labs Limited All rights reserved.
pragma solidity ^0.8.24;

/// @title IPolicyRegistryEvents
/// @notice Events emitted by both plain and confidential policy registries.
/// @dev Centralized to keep event signatures aligned across IPolicyRegistry and IConfidentialPolicyRegistry.
interface IPolicyRegistryEvents {
    /// @notice Emitted when a policy is registered
    /// @param policyId The newly assigned policy identifier
    /// @param policy The registered policy contract address
    /// @param creator The address that registered the policy
    event PolicyRegistered(uint256 indexed policyId, address indexed policy, address indexed creator);
}
