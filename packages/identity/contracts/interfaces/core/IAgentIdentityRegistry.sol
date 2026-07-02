// SPDX-License-Identifier: BUSL-1.1
// Copyright (c) 2026 Reineira Labs Limited All rights reserved.
pragma solidity ^0.8.24;

import {ICore} from "@reineira-os/shared/contracts/interfaces/core/ICore.sol";

/// @title IAgentIdentityRegistry — ERC-8004 Identity Registry
/// @notice Minimal ERC-721 + URIStorage registry for trustless agent identity.
/// @dev Each agent is a globally unique ERC-721 token with optional on-chain metadata.
interface IAgentIdentityRegistry is ICore {
    /// @notice On-chain metadata entry for an agent
    struct MetadataEntry {
        string metadataKey;
        bytes metadataValue;
    }

    /// @notice Emitted when a new agent is registered
    /// @param agentId The ERC-721 tokenId assigned to the agent
    /// @param agentURI The initial URI pointing to the agent registration file
    /// @param owner The address that owns the newly minted token
    event Registered(uint256 indexed agentId, string agentURI, address indexed owner);

    /// @notice Emitted when an agent's URI is updated
    /// @param agentId The agent whose URI changed
    /// @param newURI The new URI
    /// @param updatedBy The address that triggered the update
    event URIUpdated(uint256 indexed agentId, string newURI, address indexed updatedBy);

    /// @notice Emitted when on-chain metadata is set
    /// @param agentId The agent whose metadata changed
    /// @param indexedMetadataKey Indexed metadata key for filtering
    /// @param metadataKey The metadata key
    /// @param metadataValue The metadata value
    event MetadataSet(
        uint256 indexed agentId,
        string indexed indexedMetadataKey,
        string metadataKey,
        bytes metadataValue
    );

    /// @notice Emitted when an agent's wallet address is set or verified
    /// @param agentId The agent whose wallet changed
    /// @param wallet The verified wallet address
    event AgentWalletSet(uint256 indexed agentId, address indexed wallet);

    /// @notice Emitted when an agent's wallet address is cleared
    /// @param agentId The agent whose wallet was cleared
    event AgentWalletCleared(uint256 indexed agentId);

    /// @notice Thrown when the queried agent does not exist
    error AgentNotFound();

    /// @notice Thrown when a non-owner tries to modify agent data
    error NotAgentOwner();

    /// @notice Thrown when `agentWallet` is used as a metadata key
    error ReservedMetadataKey();

    /// @notice Thrown when the provided signature is invalid or expired
    error InvalidSignature();

    /// @notice Thrown when the signature deadline has passed
    error SignatureExpired();

    /// @notice Thrown when the wallet is already set to the same address
    error WalletAlreadySet();

    /// @notice Thrown when the wallet has not been set
    error WalletNotSet();

    /// @notice Registers a new agent with URI and optional metadata
    /// @param agentURI The URI for the agent registration file
    /// @param metadata Array of on-chain metadata entries (may be empty)
    /// @return agentId The newly minted ERC-721 tokenId
    function register(string calldata agentURI, MetadataEntry[] calldata metadata) external returns (uint256 agentId);

    /// @notice Registers a new agent with only a URI
    /// @param agentURI The URI for the agent registration file
    /// @return agentId The newly minted ERC-721 tokenId
    function register(string calldata agentURI) external returns (uint256 agentId);

    /// @notice Registers a new agent without an initial URI
    /// @return agentId The newly minted ERC-721 tokenId
    function register() external returns (uint256 agentId);

    /// @notice Updates the URI for an existing agent
    /// @param agentId The agent to update
    /// @param newURI The new URI
    function setAgentURI(uint256 agentId, string calldata newURI) external;

    /// @notice Sets on-chain metadata for an agent
    /// @param agentId The agent to update
    /// @param metadataKey The metadata key
    /// @param metadataValue The metadata value
    function setMetadata(uint256 agentId, string calldata metadataKey, bytes calldata metadataValue) external;

    /// @notice Returns on-chain metadata for an agent
    /// @param agentId The agent to query
    /// @param metadataKey The metadata key
    /// @return The metadata value
    function getMetadata(uint256 agentId, string calldata metadataKey) external view returns (bytes memory);

    /// @notice Sets the verified wallet address for an agent using EIP-712 / ERC-1271
    /// @param agentId The agent to update
    /// @param newWallet The wallet address to verify
    /// @param deadline Signature expiry timestamp
    /// @param signature EIP-712 signature from `newWallet`
    function setAgentWallet(uint256 agentId, address newWallet, uint256 deadline, bytes calldata signature) external;

    /// @notice Returns the verified wallet address for an agent
    /// @param agentId The agent to query
    /// @return The verified wallet address, or address(0) if none is set
    function getAgentWallet(uint256 agentId) external view returns (address);

    /// @notice Clears the verified wallet address for an agent
    /// @param agentId The agent to update
    function unsetAgentWallet(uint256 agentId) external;

    /// @notice Returns the total number of registered agents
    function agentCount() external view returns (uint256);
}
