// SPDX-License-Identifier: FSL-1.1-ALv2
// Copyright (c) 2026 Reineira Labs Limited All rights reserved.
pragma solidity ^0.8.24;

/// @title IAgentConfigRegistry — Agent configuration registry
/// @notice Stores and serves agent invocation configurations. Each registered agent
///         defines input/output condition resolvers, the quorum resolver, coverage
///         pools/policies, and the minimum quorum size required for attestation.
interface IAgentConfigRegistry {
    /// @notice On-chain configuration for a registered agent
    /// @param agent The agent address (key; must match query address)
    /// @param inputResolvers IConditionResolver addresses for input validation
    /// @param outputResolvers IConditionResolver addresses for output validation
    /// @param quorumResolver The QuorumAttestedResolver gating escrow release
    /// @param payoutSchema Opaque PayoutManifest schema bytes
    /// @param minQuorum Minimum number of quorum signatures required
    /// @param coveragePools Pool addresses for coverage attachment
    /// @param coveragePolicies Policy addresses for coverage attachment
    struct AgentConfig {
        address agent;
        address[] inputResolvers;
        address[] outputResolvers;
        address quorumResolver;
        bytes payoutSchema;
        uint256 minQuorum;
        address[] coveragePools;
        address[] coveragePolicies;
    }

    /// @notice Thrown when querying an unregistered agent
    error AgentNotRegistered();

    /// @notice Returns the full configuration for a registered agent
    /// @param agent The agent address to query
    /// @return config The agent configuration struct
    function getAgentConfig(address agent) external view returns (AgentConfig memory config);

    /// @notice Returns true if the agent is registered
    /// @param agent The agent address to check
    /// @return True if registered
    function isRegisteredAgent(address agent) external view returns (bool);
}
