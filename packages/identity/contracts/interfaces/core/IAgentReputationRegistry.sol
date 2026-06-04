// SPDX-License-Identifier: BUSL-1.1
// Copyright (c) 2026 Reineira Labs Limited All rights reserved.
pragma solidity ^0.8.24;

import {ICore} from "@reineira-os/shared/contracts/interfaces/core/ICore.sol";

/// @title IAgentReputationRegistry — ERC-8004 Reputation Registry
/// @notice Stores signed feedback and counter-evidence responses for agents.
interface IAgentReputationRegistry is ICore {
    /// @notice Emitted when new feedback is submitted for an agent
    event NewFeedback(
        uint256 indexed agentId,
        address indexed clientAddress,
        uint64 feedbackIndex,
        int128 value,
        uint8 valueDecimals,
        string indexed indexedTag1,
        string tag1,
        string tag2,
        string endpoint,
        string feedbackURI,
        bytes32 feedbackHash
    );

    /// @notice Emitted when feedback is revoked by its original author
    event FeedbackRevoked(uint256 indexed agentId, address indexed clientAddress, uint64 indexed feedbackIndex);

    /// @notice Emitted when a response is appended to existing feedback
    event ResponseAppended(
        uint256 indexed agentId,
        address indexed clientAddress,
        uint64 feedbackIndex,
        address indexed responder,
        string responseURI,
        bytes32 responseHash
    );

    /// @notice Thrown when the referenced agent does not exist in the identity registry
    error AgentNotFound();

    /// @notice Thrown when valueDecimals is outside the 0–18 range
    error InvalidValueDecimals();

    /// @notice Thrown when the agent owner tries to give feedback on their own agent
    error AgentOwnerCannotFeedback();

    /// @notice Thrown when the requested feedback does not exist
    error FeedbackNotFound();

    /// @notice Thrown when trying to revoke already-revoked feedback
    error AlreadyRevoked();

    /// @notice Submits feedback for an agent
    /// @param agentId The agent being reviewed
    /// @param value Signed fixed-point value
    /// @param valueDecimals Number of decimal places (0–18)
    /// @param tag1 Optional categorization tag
    /// @param tag2 Optional secondary tag
    /// @param endpoint Optional endpoint URI related to the feedback
    /// @param feedbackURI Optional URI to off-chain feedback file
    /// @param feedbackHash KECCAK-256 hash of the off-chain file (0 for IPFS)
    function giveFeedback(
        uint256 agentId,
        int128 value,
        uint8 valueDecimals,
        string calldata tag1,
        string calldata tag2,
        string calldata endpoint,
        string calldata feedbackURI,
        bytes32 feedbackHash
    ) external;

    /// @notice Revokes previously submitted feedback
    /// @param agentId The agent the feedback was for
    /// @param feedbackIndex The 1-based index of the feedback to revoke
    function revokeFeedback(uint256 agentId, uint64 feedbackIndex) external;

    /// @notice Appends counter-evidence or a response to existing feedback
    /// @param agentId The agent the feedback was for
    /// @param clientAddress The original feedback author
    /// @param feedbackIndex The 1-based index of the feedback
    /// @param responseURI Optional URI to off-chain response file
    /// @param responseHash KECCAK-256 hash of the off-chain file (0 for IPFS)
    function appendResponse(
        uint256 agentId,
        address clientAddress,
        uint64 feedbackIndex,
        string calldata responseURI,
        bytes32 responseHash
    ) external;

    /// @notice Reads a single feedback entry
    /// @param agentId The agent the feedback was for
    /// @param clientAddress The feedback author
    /// @param feedbackIndex The 1-based index
    /// @return value The signed fixed-point value
    /// @return valueDecimals Number of decimal places
    /// @return tag1 The primary tag
    /// @return tag2 The secondary tag
    /// @return isRevoked Whether the feedback has been revoked
    function readFeedback(
        uint256 agentId,
        address clientAddress,
        uint64 feedbackIndex
    ) external view returns (int128 value, uint8 valueDecimals, string memory tag1, string memory tag2, bool isRevoked);

    /// @notice Returns the number of feedback entries a client has given for an agent
    /// @param agentId The agent
    /// @param clientAddress The client
    /// @return The 1-based highest index (0 if none)
    function getLastIndex(uint256 agentId, address clientAddress) external view returns (uint64);

    /// @notice Returns the number of responses appended to a feedback entry
    /// @param agentId The agent
    /// @param clientAddress The feedback author
    /// @param feedbackIndex The feedback index
    /// @return The number of responses
    function getResponseCount(
        uint256 agentId,
        address clientAddress,
        uint64 feedbackIndex
    ) external view returns (uint64);

    /// @notice Returns the identity registry address used for agent validation
    function getIdentityRegistry() external view returns (address);
}
