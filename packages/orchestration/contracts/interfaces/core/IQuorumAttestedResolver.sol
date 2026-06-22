// SPDX-License-Identifier: FSL-1.1-ALv2
// Copyright (c) 2026 Reineira Labs Limited All rights reserved.
pragma solidity ^0.8.24;

import {IConditionResolver} from "@reineira-os/shared/contracts/interfaces/plugins/IConditionResolver.sol";

/// @title IQuorumAttestedResolver — Dual-gate condition resolver with quorum attestation
/// @notice Extends IConditionResolver with an input gate and an output gate.
///         Both gates must be triggered before `isConditionMet` returns true,
///         allowing escrow redemption only after full pipeline completion.
interface IQuorumAttestedResolver is IConditionResolver {
    /// @notice Emitted when the input gate is triggered for an escrow
    /// @param escrowId The escrow whose input gate was triggered
    event InputGateTriggered(uint256 indexed escrowId);

    /// @notice Emitted when the output gate is triggered for an escrow
    /// @param escrowId The escrow whose output gate was triggered
    event OutputGateTriggered(uint256 indexed escrowId);

    /// @notice Thrown when attempting to trigger a gate that is already set
    error GateAlreadyTriggered();

    /// @notice Thrown when the quorum signatures do not meet the threshold
    error InvalidQuorum();

    /// @notice Thrown when the message hash does not match the expected value
    error InvalidMessage();

    /// @notice Triggers the input gate for an escrow (step 3 of pipeline)
    /// @dev Called by AgentInvocationAdapter after input conditions validate
    /// @param escrowId The escrow identifier
    function triggerInputGate(uint256 escrowId) external;

    /// @notice Triggers the output gate for an escrow (step 9 of pipeline)
    /// @dev Called by AgentInvocationAdapter after output conditions validate
    ///      and quorum signatures are verified.
    /// @param escrowId The escrow identifier
    /// @param verdict The opaque verdict bytes
    /// @param quorumSigs Aggregated quorum signatures over keccak256(abi.encode(escrowId, verdict))
    function triggerOutputGate(uint256 escrowId, bytes calldata verdict, bytes calldata quorumSigs) external;

    /// @notice Returns true if the input gate has been triggered
    /// @param escrowId The escrow identifier
    /// @return True if triggered
    function isInputGateTriggered(uint256 escrowId) external view returns (bool);

    /// @notice Returns true if the output gate has been triggered
    /// @param escrowId The escrow identifier
    /// @return True if triggered
    function isOutputGateTriggered(uint256 escrowId) external view returns (bool);

    /// @notice Verifies a set of quorum signatures against a message
    /// @param message The message that was signed
    /// @param quorumSigs The aggregated signatures
    /// @return True if quorum is valid
    function verifyQuorum(bytes calldata message, bytes calldata quorumSigs) external view returns (bool);
}
