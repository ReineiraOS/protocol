// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 Reineira Labs Limited All rights reserved.
pragma solidity ^0.8.24;

import {IERC165} from "@openzeppelin/contracts/utils/introspection/IERC165.sol";

/// @title IAgenticJob — Neutral lifecycle interface for agentic job execution
/// @notice Defines a standard-agnostic lifecycle that all job adapters implement.
///         Adapters (EIP8183Adapter, ARSAdapter, AgentInvocationAdapter) carry the
///         standards-specific opinion; this interface remains neutral.
/// @dev Implementations must support ERC-165 so callers can validate the interface.
///      The JobView struct is designed to be compatible with the multi-coverage
///      extension (AP-15): `coverageIds` is an array to accommodate multiple
///      coverage positions per escrow.
interface IAgenticJob is IERC165 {
    /// @notice Lifecycle phases of an agentic job
    enum Phase {
        Open,
        Accepted,
        Submitted,
        Evaluated,
        Settled,
        Refunded
    }

    /// @notice Immutable snapshot of a job's identity and current phase
    /// @dev `coverageIds` is an array to support multi-coverage per escrow (AP-15).
    ///      An empty array indicates no coverage has been purchased.
    struct JobView {
        address client;
        address provider;
        uint256 escrowId;
        uint256[] coverageIds;
        bytes32 standard;
        Phase phase;
    }

    /// @notice Emitted when a job transitions to a new phase
    /// @param jobId The unique job identifier
    /// @param phase The new phase
    event JobPhaseChanged(bytes32 indexed jobId, Phase indexed phase);

    /// @notice Returns the immutable view of a job
    /// @param jobId The job identifier to query
    /// @return The JobView struct for the given jobId
    function jobView(bytes32 jobId) external view returns (JobView memory);
}
