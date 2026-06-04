// SPDX-License-Identifier: BUSL-1.1
// Copyright (c) 2026 Reineira Labs Limited All rights reserved.
pragma solidity ^0.8.24;

import {ICore} from "@reineira-os/shared/contracts/interfaces/core/ICore.sol";

/// @title IAgentValidationRegistry — ERC-8004 Validation Registry
/// @notice Enables agents to request verification and validators to provide on-chain responses.
interface IAgentValidationRegistry is ICore {
    /// @notice Emitted when a validation request is created
    event ValidationRequest(
        address indexed validatorAddress,
        uint256 indexed agentId,
        string requestURI,
        bytes32 indexed requestHash
    );

    /// @notice Emitted when a validator responds to a request
    event ValidationResponse(
        address indexed validatorAddress,
        uint256 indexed agentId,
        bytes32 indexed requestHash,
        uint8 response,
        string responseURI,
        bytes32 responseHash,
        string tag
    );

    /// @notice Thrown when the referenced agent does not exist
    error AgentNotFound();

    /// @notice Thrown when the validator address is zero
    error InvalidValidator();

    /// @notice Thrown when the request hash is not found
    error RequestNotFound();

    /// @notice Thrown when the caller is not the specified validator
    error NotValidator();

    /// @notice Thrown when the response value exceeds 100
    error InvalidResponse();

    /// @notice Creates a validation request for an agent
    /// @param validatorAddress The validator expected to respond
    /// @param agentId The agent to validate
    /// @param requestURI URI to off-chain validation data
    /// @param requestHash KECCAK-256 hash of the request payload
    function validationRequest(
        address validatorAddress,
        uint256 agentId,
        string calldata requestURI,
        bytes32 requestHash
    ) external;

    /// @notice Submits a validator response to a request
    /// @param requestHash The hash identifying the original request
    /// @param response Score from 0–100 (binary or spectrum)
    /// @param responseURI Optional URI to off-chain evidence
    /// @param responseHash KECCAK-256 hash of the response file (0 for IPFS)
    /// @param tag Optional categorization tag
    function validationResponse(
        bytes32 requestHash,
        uint8 response,
        string calldata responseURI,
        bytes32 responseHash,
        string calldata tag
    ) external;

    /// @notice Returns the stored status for a validation request
    /// @param requestHash The request hash
    /// @return validatorAddress The validator assigned to the request
    /// @return agentId The agent being validated
    /// @return response The latest response value (0 if none)
    /// @return responseHash The hash of the latest response evidence
    /// @return tag The latest response tag
    /// @return lastUpdate The timestamp of the latest response (0 if none)
    function getValidationStatus(
        bytes32 requestHash
    )
        external
        view
        returns (
            address validatorAddress,
            uint256 agentId,
            uint8 response,
            bytes32 responseHash,
            string memory tag,
            uint256 lastUpdate
        );

    /// @notice Returns all request hashes for a given agent
    /// @param agentId The agent to query
    /// @return requestHashes Array of request hashes
    function getAgentValidations(uint256 agentId) external view returns (bytes32[] memory requestHashes);

    /// @notice Returns all request hashes for a given validator
    /// @param validatorAddress The validator to query
    /// @return requestHashes Array of request hashes
    function getValidatorRequests(address validatorAddress) external view returns (bytes32[] memory requestHashes);

    /// @notice Returns the identity registry address used for agent validation
    function getIdentityRegistry() external view returns (address);
}
