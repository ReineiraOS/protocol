// SPDX-License-Identifier: BUSL-1.1
// Copyright (c) 2026 Reineira Labs Limited All rights reserved.
pragma solidity ^0.8.24;

import {IERC721} from "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import {EnumerableSet} from "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import {TestnetCoreBase} from "@reineira-os/shared/contracts/common/TestnetCoreBase.sol";
import {IAgentIdentityRegistry} from "../interfaces/core/IAgentIdentityRegistry.sol";
import {IAgentReputationRegistry} from "../interfaces/core/IAgentReputationRegistry.sol";

contract AgentReputationRegistry is IAgentReputationRegistry, TestnetCoreBase {
    using EnumerableSet for EnumerableSet.AddressSet;

    struct Feedback {
        int128 value;
        uint8 valueDecimals;
        string tag1;
        string tag2;
        bool isRevoked;
    }

    struct ResponseEntry {
        address responder;
        string responseURI;
        bytes32 responseHash;
        uint256 timestamp;
    }

    IAgentIdentityRegistry public identityRegistry;

    // agentId => client => feedbackIndex => Feedback
    mapping(bytes32 => Feedback) private _feedback;
    // agentId => client => lastIndex
    mapping(bytes32 => uint64) private _feedbackCount;
    // agentId => client => feedbackIndex => responses
    mapping(bytes32 => ResponseEntry[]) private _responses;
    // agentId => set of clients
    mapping(uint256 => EnumerableSet.AddressSet) private _clients;

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

    // --- feedback ---

    function giveFeedback(
        uint256 agentId,
        int128 value,
        uint8 valueDecimals,
        string calldata tag1,
        string calldata tag2,
        string calldata endpoint,
        string calldata feedbackURI,
        bytes32 feedbackHash
    ) external {
        if (agentId >= identityRegistry.agentCount()) revert AgentNotFound();
        if (valueDecimals > 18) revert InvalidValueDecimals();

        address caller = _msgSender();
        address agentOwner;
        try IERC721(address(identityRegistry)).ownerOf(agentId) returns (address o) {
            agentOwner = o;
        } catch {
            revert AgentNotFound();
        }
        if (caller == agentOwner) revert AgentOwnerCannotFeedback();
        if (IERC721(address(identityRegistry)).isApprovedForAll(agentOwner, caller)) revert AgentOperatorCannotFeedback();
        if (IERC721(address(identityRegistry)).getApproved(agentId) == caller) revert AgentOperatorCannotFeedback();

        bytes32 countKey = _feedbackKey(agentId, caller);
        uint64 index = ++_feedbackCount[countKey];
        Feedback storage fb = _feedback[_feedbackIndexKey(agentId, caller, index)];
        fb.value = value;
        fb.valueDecimals = valueDecimals;
        fb.tag1 = tag1;
        fb.tag2 = tag2;
        fb.isRevoked = false;

        _clients[agentId].add(caller);

        _emitNewFeedback(agentId, caller, index, value, valueDecimals, tag1, tag2, endpoint, feedbackURI, feedbackHash);
    }

    function _emitNewFeedback(
        uint256 agentId,
        address caller,
        uint64 index,
        int128 value,
        uint8 valueDecimals,
        string calldata tag1,
        string calldata tag2,
        string calldata endpoint,
        string calldata feedbackURI,
        bytes32 feedbackHash
    ) internal {
        emit NewFeedback(
            agentId,
            caller,
            index,
            value,
            valueDecimals,
            tag1,
            tag1,
            tag2,
            endpoint,
            feedbackURI,
            feedbackHash
        );
    }

    function revokeFeedback(uint256 agentId, uint64 feedbackIndex) external {
        if (feedbackIndex == 0) revert FeedbackNotFound();
        if (_feedbackCount[_feedbackKey(agentId, _msgSender())] < feedbackIndex) revert FeedbackNotFound();

        bytes32 key = _feedbackIndexKey(agentId, _msgSender(), feedbackIndex);
        if (_feedback[key].isRevoked) revert AlreadyRevoked();

        _feedback[key].isRevoked = true;
        emit FeedbackRevoked(agentId, _msgSender(), feedbackIndex);
    }

    function appendResponse(
        uint256 agentId,
        address clientAddress,
        uint64 feedbackIndex,
        string calldata responseURI,
        bytes32 responseHash
    ) external {
        if (feedbackIndex == 0) revert FeedbackNotFound();
        if (_feedbackCount[_feedbackKey(agentId, clientAddress)] < feedbackIndex) revert FeedbackNotFound();

        _responses[_feedbackIndexKey(agentId, clientAddress, feedbackIndex)].push(
            ResponseEntry({
                responder: _msgSender(),
                responseURI: responseURI,
                responseHash: responseHash,
                timestamp: block.timestamp
            })
        );

        emit ResponseAppended(agentId, clientAddress, feedbackIndex, _msgSender(), responseURI, responseHash);
    }

    // --- views ---

    function readFeedback(
        uint256 agentId,
        address clientAddress,
        uint64 feedbackIndex
    )
        external
        view
        returns (int128 value, uint8 valueDecimals, string memory tag1, string memory tag2, bool isRevoked)
    {
        if (feedbackIndex == 0) revert FeedbackNotFound();
        if (_feedbackCount[_feedbackKey(agentId, clientAddress)] < feedbackIndex) revert FeedbackNotFound();
        Feedback storage fb = _feedback[_feedbackIndexKey(agentId, clientAddress, feedbackIndex)];
        return (fb.value, fb.valueDecimals, fb.tag1, fb.tag2, fb.isRevoked);
    }

    function getLastIndex(uint256 agentId, address clientAddress) external view returns (uint64) {
        return _feedbackCount[_feedbackKey(agentId, clientAddress)];
    }

    function getResponseCount(
        uint256 agentId,
        address clientAddress,
        uint64 feedbackIndex
    ) external view returns (uint64) {
        if (feedbackIndex == 0) return 0;
        return uint64(_responses[_feedbackIndexKey(agentId, clientAddress, feedbackIndex)].length);
    }

    function getIdentityRegistry() external view returns (address) {
        return address(identityRegistry);
    }

    function getClients(uint256 agentId) external view returns (address[] memory) {
        return _clients[agentId].values();
    }

    // --- internal ---

    function _feedbackKey(uint256 agentId, address client) internal pure returns (bytes32) {
        return keccak256(abi.encodePacked(agentId, client));
    }

    function _feedbackIndexKey(uint256 agentId, address client, uint64 index) internal pure returns (bytes32) {
        return keccak256(abi.encodePacked(agentId, client, index));
    }
}
