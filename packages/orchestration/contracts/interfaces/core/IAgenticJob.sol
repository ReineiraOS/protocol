// SPDX-License-Identifier: FSL-1.1-ALv2
// Copyright (c) 2026 Reineira Labs Limited All rights reserved.
pragma solidity ^0.8.24;

/// @title IAgenticJob — Core interface for agent invocation lifecycle
/// @notice Defines the 9-step agent invocation pipeline. Implementations must
///         validate input/output conditions, create escrow, attach coverages,
///         and coordinate verdict submission with quorum attestation.
interface IAgenticJob {
    /// @notice Lifecycle phases of an agent invocation
    enum InvocationStatus {
        None,
        Opened,
        VerdictSubmitted,
        Completed,
        Failed
    }

    /// @notice Emitted when a new agent invocation is opened (step 5)
    /// @param invocationId The assigned invocation identifier
    /// @param escrowId The escrow backing this invocation
    /// @param agent The agent address
    /// @param client The client address that opened the invocation
    event InvocationOpened(
        uint256 indexed invocationId,
        uint256 indexed escrowId,
        address indexed agent,
        address client
    );

    /// @notice Emitted when a final verdict is submitted (step 7)
    /// @param invocationId The invocation receiving the verdict
    /// @param verdictHash keccak256(verdict) for off-chain verification
    event VerdictSubmitted(uint256 indexed invocationId, bytes32 verdictHash);

    /// @notice Emitted when the invocation pipeline completes successfully
    /// @param invocationId The completed invocation
    /// @param escrowId The escrow that can now be released
    event InvocationCompleted(uint256 indexed invocationId, uint256 indexed escrowId);

    /// @notice Emitted when the invocation fails and is marked as Failed
    /// @param invocationId The failed invocation
    /// @param reason Human-readable failure reason
    event InvocationFailed(uint256 indexed invocationId, string reason);

    /// @notice Thrown when the agent is not registered in AgentConfigRegistry
    error InvalidAgent();

    /// @notice Thrown when an input condition resolver reports false
    /// @param invocationId The invocation being validated
    /// @param resolver The resolver that rejected the condition
    error InputConditionsNotMet(uint256 invocationId, address resolver);

    /// @notice Thrown when an output condition resolver reports false
    /// @param invocationId The invocation being validated
    /// @param resolver The resolver that rejected the condition
    error OutputConditionsNotMet(uint256 invocationId, address resolver);

    /// @notice Thrown when the verdict is empty or malformed
    error InvalidVerdict();

    /// @notice Thrown when the agent signature is invalid
    error InvalidSignature();

    /// @notice Thrown when the invocation identifier does not exist
    error InvocationNotFound();

    /// @notice Thrown when the invocation is not in the Opened state
    error InvocationNotOpen();

    /// @notice Thrown when a verdict has already been submitted
    error AlreadySubmitted();

    /// @notice Thrown when quorum signatures are insufficient
    error QuorumNotReached();

    /// @notice Thrown when escrow creation returns an invalid identifier
    error EscrowCreationFailed();

    /// @notice Thrown when one or more coverages could not be attached
    error CoverageAttachmentFailed();

    /// @notice Opens a new agent invocation and runs steps 1-5 of the pipeline
    /// @param agent The registered agent to invoke
    /// @param escrowInitData Opaque init data forwarded to IEscrow.create(bytes,address,bytes)
    /// @param fundingProof Opaque funding proof forwarded to IEscrow.fund
    /// @param resolverData Encoded configuration forwarded to QuorumAttestedResolver.onConditionSet
    /// @param coverageParams Array of coverage purchase parameters
    /// @return invocationId The assigned invocation identifier
    function openInvocation(
        address agent,
        bytes calldata escrowInitData,
        bytes calldata fundingProof,
        bytes calldata resolverData,
        CoverageParam[] calldata coverageParams
    ) external returns (uint256 invocationId);

    /// @notice Receives the final verdict and runs steps 7-9 of the pipeline
    /// @param invocationId The invocation to close
    /// @param verdict Opaque verdict bytes (off-chain agent output)
    /// @param agentSig Agent signature over keccak256(abi.encode(invocationId, verdict))
    /// @param quorumSigs Aggregated quorum signatures attesting to the verdict
    function submitFinalVerdict(
        uint256 invocationId,
        bytes calldata verdict,
        bytes calldata agentSig,
        bytes calldata quorumSigs
    ) external;

    /// @notice Coverage purchase parameters for a single coverage attachment
    struct CoverageParam {
        address pool;
        address policy;
        uint256 coverageAmount;
        uint256 coverageExpiry;
        bytes policyData;
        bytes riskProof;
    }
}
