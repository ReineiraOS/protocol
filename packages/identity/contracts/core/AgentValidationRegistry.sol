// SPDX-License-Identifier: BUSL-1.1
// Copyright (c) 2026 Reineira Labs Limited All rights reserved.
pragma solidity ^0.8.24;

import {IERC721} from "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import {TestnetCoreBase} from "@reineira-os/shared/contracts/common/TestnetCoreBase.sol";
import {IAgentIdentityRegistry} from "../interfaces/core/IAgentIdentityRegistry.sol";
import {IAgentValidationRegistry} from "../interfaces/core/IAgentValidationRegistry.sol";

contract AgentValidationRegistry is IAgentValidationRegistry, TestnetCoreBase {
    struct ValidationRequestData {
        address validatorAddress;
        uint256 agentId;
        string requestURI;
        bytes32 requestHash;
        uint256 requestedAt;
    }

    struct ValidationResponseData {
        uint8 response;
        string responseURI;
        bytes32 responseHash;
        string tag;
        uint256 respondedAt;
    }

    IAgentIdentityRegistry public identityRegistry;

    mapping(bytes32 => ValidationRequestData) private _requests;
    mapping(bytes32 => ValidationResponseData) private _responses;
    mapping(uint256 => bytes32[]) private _agentValidations;
    mapping(address => bytes32[]) private _validatorRequests;

    uint256[50] private __gap;

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor(address trustedForwarder_) TestnetCoreBase(trustedForwarder_) {
        _disableInitializers();
    }

    function initialize(address owner_, address identityRegistry_) external initializer {
        if (owner_ == address(0)) revert ZeroAddress();
        if (identityRegistry_ == address(0)) revert ZeroAddress();
        __TestnetCoreBase_init(owner_);
        identityRegistry = IAgentIdentityRegistry(identityRegistry_);
        emit CoreInitialized(owner_);
    }

    // --- validation request ---

    function validationRequest(
        address validatorAddress,
        uint256 agentId,
        string calldata requestURI,
        bytes32 requestHash
    ) external {
        if (validatorAddress == address(0)) revert InvalidValidator();
        if (requestHash == bytes32(0)) revert ZeroHash();
        if (_requests[requestHash].requestedAt != 0) revert DuplicateRequest();

        address caller = _msgSender();
        address agentOwner;
        try IERC721(address(identityRegistry)).ownerOf(agentId) returns (address o) {
            agentOwner = o;
        } catch {
            revert AgentNotFound();
        }
        if (caller != agentOwner) revert Unauthorized();

        _requests[requestHash] = ValidationRequestData({
            validatorAddress: validatorAddress,
            agentId: agentId,
            requestURI: requestURI,
            requestHash: requestHash,
            requestedAt: block.timestamp
        });

        _agentValidations[agentId].push(requestHash);
        _validatorRequests[validatorAddress].push(requestHash);

        emit ValidationRequest(validatorAddress, agentId, requestURI, requestHash);
    }

    // --- validation response ---

    function validationResponse(
        bytes32 requestHash,
        uint8 response,
        string calldata responseURI,
        bytes32 responseHash,
        string calldata tag
    ) external {
        if (requestHash == bytes32(0)) revert RequestNotFound();
        ValidationRequestData storage req = _requests[requestHash];
        if (req.requestedAt == 0) revert RequestNotFound();
        if (_msgSender() != req.validatorAddress) revert NotValidator();
        if (response > 100) revert InvalidResponse();

        _responses[requestHash] = ValidationResponseData({
            response: response,
            responseURI: responseURI,
            responseHash: responseHash,
            tag: tag,
            respondedAt: block.timestamp
        });

        emit ValidationResponse(
            req.validatorAddress,
            req.agentId,
            requestHash,
            response,
            responseURI,
            responseHash,
            tag
        );
    }

    // --- views ---

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
        )
    {
        ValidationRequestData storage req = _requests[requestHash];
        if (req.requestedAt == 0) revert RequestNotFound();
        ValidationResponseData storage resp = _responses[requestHash];
        return (req.validatorAddress, req.agentId, resp.response, resp.responseHash, resp.tag, resp.respondedAt);
    }

    function getAgentValidations(uint256 agentId) external view returns (bytes32[] memory requestHashes) {
        return _agentValidations[agentId];
    }

    function getValidatorRequests(address validatorAddress) external view returns (bytes32[] memory requestHashes) {
        return _validatorRequests[validatorAddress];
    }

    function getIdentityRegistry() external view returns (address) {
        return address(identityRegistry);
    }
}
