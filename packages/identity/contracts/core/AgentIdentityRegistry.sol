// SPDX-License-Identifier: BUSL-1.1
// Copyright (c) 2026 Reineira Labs Limited All rights reserved.
pragma solidity ^0.8.24;

import {IERC1271} from "@openzeppelin/contracts/interfaces/IERC1271.sol";
import {ECDSA} from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import {ContextUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/ContextUpgradeable.sol";
import {ERC2771ContextUpgradeable} from "@openzeppelin/contracts-upgradeable/metatx/ERC2771ContextUpgradeable.sol";
import {ERC721Upgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC721/ERC721Upgradeable.sol";
import {ERC721URIStorageUpgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC721/extensions/ERC721URIStorageUpgradeable.sol";
import {EIP712Upgradeable} from "@openzeppelin/contracts-upgradeable/utils/cryptography/EIP712Upgradeable.sol";
import {TestnetCoreBase} from "@reineira-os/shared/contracts/common/TestnetCoreBase.sol";
import {IAgentIdentityRegistry} from "../interfaces/core/IAgentIdentityRegistry.sol";

contract AgentIdentityRegistry is
    IAgentIdentityRegistry,
    TestnetCoreBase,
    ERC721Upgradeable,
    ERC721URIStorageUpgradeable,
    EIP712Upgradeable
{
    using ECDSA for bytes32;

    bytes32 private constant SET_AGENT_WALLET_TYPEHASH =
        keccak256("SetAgentWallet(uint256 agentId,address newWallet,uint256 nonce,uint256 deadline)");

    uint256 private _nextAgentId;
    mapping(uint256 => address) private _agentWallets;
    mapping(uint256 => uint256) private _walletNonces;
    mapping(uint256 => mapping(string => bytes)) private _metadata;

    uint256[50] private __gap;

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor(address trustedForwarder_) TestnetCoreBase(trustedForwarder_) {
        _disableInitializers();
    }

    function initialize(address owner_) external initializer {
        if (owner_ == address(0)) revert ZeroAddress();
        __TestnetCoreBase_init(owner_);
        __ERC721_init("Reineira Agent Identity", "RAI");
        __ERC721URIStorage_init();
        __EIP712_init("Reineira Agent Identity", "1");
        emit CoreInitialized(owner_);
    }

    // --- ERC-721 + URIStorage overrides ---

    function tokenURI(
        uint256 tokenId
    ) public view override(ERC721Upgradeable, ERC721URIStorageUpgradeable) returns (string memory) {
        return super.tokenURI(tokenId);
    }

    function supportsInterface(
        bytes4 interfaceId
    ) public view override(ERC721Upgradeable, ERC721URIStorageUpgradeable) returns (bool) {
        return super.supportsInterface(interfaceId);
    }

    function _msgSender() internal view virtual override(ContextUpgradeable, TestnetCoreBase) returns (address) {
        return ERC2771ContextUpgradeable._msgSender();
    }

    function _msgData() internal view virtual override(ContextUpgradeable, TestnetCoreBase) returns (bytes calldata) {
        return ERC2771ContextUpgradeable._msgData();
    }

    function _contextSuffixLength()
        internal
        view
        virtual
        override(ContextUpgradeable, TestnetCoreBase)
        returns (uint256)
    {
        return ERC2771ContextUpgradeable._contextSuffixLength();
    }

    function _update(address to, uint256 tokenId, address auth) internal override(ERC721Upgradeable) returns (address) {
        address from = super._update(to, tokenId, auth);
        // Clear agentWallet on any transfer (including mint/burn)
        if (from != address(0) && to != address(0) && _agentWallets[tokenId] != address(0)) {
            delete _agentWallets[tokenId];
            emit AgentWalletCleared(tokenId);
        }
        return from;
    }

    // --- registration ---

    function register(string calldata agentURI, MetadataEntry[] calldata metadata) external returns (uint256 agentId) {
        agentId = _nextAgentId++;
        address caller = _msgSender();
        _safeMint(caller, agentId);
        _setTokenURI(agentId, agentURI);

        // Emit reserved agentWallet metadata as owner address
        emit MetadataSet(agentId, "agentWallet", "agentWallet", abi.encode(caller));

        for (uint256 i = 0; i < metadata.length; i++) {
            _setMetadata(agentId, metadata[i].metadataKey, metadata[i].metadataValue);
        }

        emit Registered(agentId, agentURI, caller);
    }

    function register(string calldata agentURI) external returns (uint256 agentId) {
        agentId = _nextAgentId++;
        address caller = _msgSender();
        _safeMint(caller, agentId);
        _setTokenURI(agentId, agentURI);

        emit MetadataSet(agentId, "agentWallet", "agentWallet", abi.encode(caller));
        emit Registered(agentId, agentURI, caller);
    }

    function register() external returns (uint256 agentId) {
        agentId = _nextAgentId++;
        address caller = _msgSender();
        _safeMint(caller, agentId);

        emit MetadataSet(agentId, "agentWallet", "agentWallet", abi.encode(caller));
        emit Registered(agentId, "", caller);
    }

    // --- URI ---

    function setAgentURI(uint256 agentId, string calldata newURI) external {
        if (!_exists(agentId)) revert AgentNotFound();
        if (ownerOf(agentId) != _msgSender()) revert NotAgentOwner();

        _setTokenURI(agentId, newURI);
        emit URIUpdated(agentId, newURI, _msgSender());
    }

    // --- metadata ---

    function setMetadata(uint256 agentId, string calldata metadataKey, bytes calldata metadataValue) external {
        if (!_exists(agentId)) revert AgentNotFound();
        if (ownerOf(agentId) != _msgSender()) revert NotAgentOwner();
        _setMetadata(agentId, metadataKey, metadataValue);
    }

    function getMetadata(uint256 agentId, string calldata metadataKey) external view returns (bytes memory) {
        if (!_exists(agentId)) revert AgentNotFound();
        return _metadata[agentId][metadataKey];
    }

    // --- agent wallet ---

    function setAgentWallet(uint256 agentId, address newWallet, uint256 deadline, bytes calldata signature) external {
        if (!_exists(agentId)) revert AgentNotFound();
        if (ownerOf(agentId) != _msgSender()) revert NotAgentOwner();
        if (newWallet == address(0)) revert InvalidSignature();
        if (block.timestamp > deadline) revert SignatureExpired();
        if (_agentWallets[agentId] == newWallet) revert WalletAlreadySet();

        uint256 nonce = _walletNonces[agentId]++;
        bytes32 structHash = keccak256(abi.encode(SET_AGENT_WALLET_TYPEHASH, agentId, newWallet, nonce, deadline));
        bytes32 digest = _hashTypedDataV4(structHash);

        if (!_verifySignature(newWallet, digest, signature)) revert InvalidSignature();

        _agentWallets[agentId] = newWallet;
        emit AgentWalletSet(agentId, newWallet);
    }

    function getAgentWallet(uint256 agentId) external view returns (address) {
        if (!_exists(agentId)) revert AgentNotFound();
        return _agentWallets[agentId];
    }

    function unsetAgentWallet(uint256 agentId) external {
        if (!_exists(agentId)) revert AgentNotFound();
        if (ownerOf(agentId) != _msgSender()) revert NotAgentOwner();
        if (_agentWallets[agentId] == address(0)) revert WalletNotSet();

        delete _agentWallets[agentId];
        emit AgentWalletCleared(agentId);
    }

    // --- views ---

    function agentCount() external view returns (uint256) {
        return _nextAgentId;
    }

    // --- internal ---

    function _setMetadata(uint256 agentId, string calldata metadataKey, bytes calldata metadataValue) internal {
        if (keccak256(bytes(metadataKey)) == keccak256(bytes("agentWallet"))) revert ReservedMetadataKey();
        _metadata[agentId][metadataKey] = metadataValue;
        emit MetadataSet(agentId, metadataKey, metadataKey, metadataValue);
    }

    function _verifySignature(address signer, bytes32 digest, bytes calldata signature) internal view returns (bool) {
        if (signature.length == 65) {
            (address recovered, ECDSA.RecoverError error, ) = ECDSA.tryRecover(digest, signature);
            return error == ECDSA.RecoverError.NoError && recovered == signer;
        }

        // ERC-1271 smart contract wallet
        try IERC1271(signer).isValidSignature(digest, signature) returns (bytes4 magicValue) {
            return magicValue == IERC1271.isValidSignature.selector;
        } catch {
            return false;
        }
    }

    function _exists(uint256 tokenId) internal view returns (bool) {
        return _ownerOf(tokenId) != address(0);
    }
}
