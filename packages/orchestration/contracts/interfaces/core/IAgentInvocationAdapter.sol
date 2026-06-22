// SPDX-License-Identifier: FSL-1.1-ALv2
// Copyright (c) 2026 Reineira Labs Limited All rights reserved.
pragma solidity ^0.8.24;

import {IAgenticJob} from "./IAgenticJob.sol";

/// @title IAgentInvocationAdapter — Orchestration core primitive for agent invocation
/// @notice Extends IAgenticJob with configuration setters and view methods.
///         Lives in orchestration core; sibling to EIP8183Adapter (no inheritance).
interface IAgentInvocationAdapter is IAgenticJob {
    /// @notice Emitted when the AgentConfigRegistry address is updated
    /// @param oldRegistry The previous registry address
    /// @param newRegistry The new registry address
    event RegistryUpdated(address indexed oldRegistry, address indexed newRegistry);

    /// @notice Emitted when the IEscrow engine address is updated
    /// @param oldEscrow The previous escrow address
    /// @param newEscrow The new escrow address
    event EscrowUpdated(address indexed oldEscrow, address indexed newEscrow);

    /// @notice Emitted when the coverage manager address is updated
    /// @param oldManager The previous manager address
    /// @param newManager The new manager address
    event CoverageManagerUpdated(address indexed oldManager, address indexed newManager);

    /// @notice Emitted when a PayoutManifest schema is registered for an escrow
    /// @param escrowId The escrow the schema applies to
    /// @param schemaHash keccak256 of the schema bytes
    event PayoutManifestRegistered(uint256 indexed escrowId, bytes32 schemaHash);

    /// @notice Thrown when a zero address is provided where a non-zero address is required
    error ZeroAddress();

    /// @notice Thrown when an empty coverage parameter array is provided
    error EmptyCoverageParams();

    /// @notice Returns the AgentConfigRegistry used to read agent configurations
    function agentRegistry() external view returns (address);

    /// @notice Returns the IEscrow engine used to create and fund escrows
    function escrow() external view returns (address);

    /// @notice Returns the coverage manager used to attach coverages
    function coverageManager() external view returns (address);

    /// @notice Returns the invocation state for a given identifier
    /// @param invocationId The invocation to query
    /// @return agent The agent address
    /// @return client The client address
    /// @return escrowId The backing escrow identifier
    /// @return status The current invocation status
    function getInvocation(uint256 invocationId)
        external
        view
        returns (address agent, address client, uint256 escrowId, InvocationStatus status);

    /// @notice Returns the coverage IDs attached to an invocation
    /// @param invocationId The invocation to query
    /// @return coverageIds Array of coverage identifiers
    function getCoverages(uint256 invocationId) external view returns (uint256[] memory coverageIds);

    /// @notice Returns the registered PayoutManifest schema for an escrow
    /// @param escrowId The escrow to query
    /// @return schema The opaque schema bytes
    function getPayoutManifest(uint256 escrowId) external view returns (bytes memory schema);

    /// @notice Sets the AgentConfigRegistry address (owner only)
    /// @param registry_ The new registry address
    function setAgentRegistry(address registry_) external;

    /// @notice Sets the IEscrow engine address (owner only)
    /// @param escrow_ The new escrow address
    function setEscrow(address escrow_) external;

    /// @notice Sets the coverage manager address (owner only)
    /// @param manager_ The new manager address
    function setCoverageManager(address manager_) external;
}
