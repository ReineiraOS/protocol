// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.25;

import {Test} from "forge-std/Test.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {AgentIdentityRegistry} from "../../contracts/core/AgentIdentityRegistry.sol";
import {AgentReputationRegistry} from "../../contracts/core/AgentReputationRegistry.sol";
import {IAgentReputationRegistry} from "../../contracts/interfaces/core/IAgentReputationRegistry.sol";

contract AgentReputationRegistryTest is Test {
    AgentIdentityRegistry public identity;
    AgentReputationRegistry public reputation;

    address owner = makeAddr("owner");
    address agentOwner = makeAddr("agentOwner");
    address client1 = makeAddr("client1");
    address client2 = makeAddr("client2");
    address responder = makeAddr("responder");
    address operator = makeAddr("operator");

    function setUp() public {
        vm.startPrank(owner);
        AgentIdentityRegistry identityImpl = new AgentIdentityRegistry(address(0));
        bytes memory identityInit = abi.encodeCall(AgentIdentityRegistry.initialize, (owner));
        ERC1967Proxy identityProxy = new ERC1967Proxy(address(identityImpl), identityInit);
        identity = AgentIdentityRegistry(address(identityProxy));

        AgentReputationRegistry reputationImpl = new AgentReputationRegistry(address(0));
        bytes memory reputationInit = abi.encodeCall(AgentReputationRegistry.initialize, (owner, address(identity)));
        ERC1967Proxy reputationProxy = new ERC1967Proxy(address(reputationImpl), reputationInit);
        reputation = AgentReputationRegistry(address(reputationProxy));
        vm.stopPrank();
    }

    function _registerAgent(address registrant) internal returns (uint256) {
        vm.prank(registrant);
        return identity.register("ipfs://agent");
    }

    // --- giveFeedback ---

    function test_giveFeedback_storesFeedback() public {
        uint256 agentId = _registerAgent(agentOwner);

        vm.prank(client1);
        reputation.giveFeedback(
            agentId,
            87,
            0,
            "quality",
            "v1",
            "https://api.example.com",
            "ipfs://feedback",
            bytes32(0)
        );

        (int128 value, uint8 decimals, string memory tag1, string memory tag2, bool isRevoked) = reputation
            .readFeedback(agentId, client1, 1);

        assertEq(value, 87);
        assertEq(decimals, 0);
        assertEq(tag1, "quality");
        assertEq(tag2, "v1");
        assertFalse(isRevoked);
    }

    function test_giveFeedback_incrementsLastIndex() public {
        uint256 agentId = _registerAgent(agentOwner);

        vm.prank(client1);
        reputation.giveFeedback(agentId, 87, 0, "", "", "", "", bytes32(0));
        assertEq(reputation.getLastIndex(agentId, client1), 1);

        vm.prank(client1);
        reputation.giveFeedback(agentId, 92, 0, "", "", "", "", bytes32(0));
        assertEq(reputation.getLastIndex(agentId, client1), 2);
    }

    function test_giveFeedback_emitsNewFeedbackEvent() public {
        uint256 agentId = _registerAgent(agentOwner);

        vm.prank(client1);
        vm.expectEmit(true, true, false, true);
        emit IAgentReputationRegistry.NewFeedback(
            agentId,
            client1,
            1,
            87,
            0,
            "quality",
            "quality",
            "v1",
            "https://api.example.com",
            "ipfs://feedback",
            bytes32(0)
        );
        reputation.giveFeedback(
            agentId,
            87,
            0,
            "quality",
            "v1",
            "https://api.example.com",
            "ipfs://feedback",
            bytes32(0)
        );
    }

    function test_giveFeedback_revertsForAgentOwner() public {
        uint256 agentId = _registerAgent(agentOwner);

        vm.prank(agentOwner);
        vm.expectRevert(IAgentReputationRegistry.AgentOwnerCannotFeedback.selector);
        reputation.giveFeedback(agentId, 87, 0, "", "", "", "", bytes32(0));
    }

    function test_giveFeedback_revertsForApprovedForAllOperator() public {
        uint256 agentId = _registerAgent(agentOwner);

        vm.prank(agentOwner);
        identity.setApprovalForAll(operator, true);

        vm.prank(operator);
        vm.expectRevert(IAgentReputationRegistry.AgentOperatorCannotFeedback.selector);
        reputation.giveFeedback(agentId, 87, 0, "", "", "", "", bytes32(0));
    }

    function test_giveFeedback_revertsForApprovedOperator() public {
        uint256 agentId = _registerAgent(agentOwner);

        vm.prank(agentOwner);
        identity.approve(operator, agentId);

        vm.prank(operator);
        vm.expectRevert(IAgentReputationRegistry.AgentOperatorCannotFeedback.selector);
        reputation.giveFeedback(agentId, 87, 0, "", "", "", "", bytes32(0));
    }

    function test_giveFeedback_revertsForInvalidDecimals() public {
        uint256 agentId = _registerAgent(agentOwner);

        vm.prank(client1);
        vm.expectRevert(IAgentReputationRegistry.InvalidValueDecimals.selector);
        reputation.giveFeedback(agentId, 87, 19, "", "", "", "", bytes32(0));
    }

    function test_giveFeedback_revertsForNonExistentAgent() public {
        vm.prank(client1);
        vm.expectRevert(IAgentReputationRegistry.AgentNotFound.selector);
        reputation.giveFeedback(99, 87, 0, "", "", "", "", bytes32(0));
    }

    // --- revokeFeedback ---

    function test_revokeFeedback_marksAsRevoked() public {
        uint256 agentId = _registerAgent(agentOwner);

        vm.prank(client1);
        reputation.giveFeedback(agentId, 87, 0, "", "", "", "", bytes32(0));

        vm.prank(client1);
        reputation.revokeFeedback(agentId, 1);

        (, , , , bool isRevoked) = reputation.readFeedback(agentId, client1, 1);
        assertTrue(isRevoked);
    }

    function test_revokeFeedback_emitsEvent() public {
        uint256 agentId = _registerAgent(agentOwner);

        vm.prank(client1);
        reputation.giveFeedback(agentId, 87, 0, "", "", "", "", bytes32(0));

        vm.prank(client1);
        vm.expectEmit(true, true, true, false);
        emit IAgentReputationRegistry.FeedbackRevoked(agentId, client1, 1);
        reputation.revokeFeedback(agentId, 1);
    }

    function test_revokeFeedback_revertsForNonAuthor() public {
        uint256 agentId = _registerAgent(agentOwner);

        vm.prank(client1);
        reputation.giveFeedback(agentId, 87, 0, "", "", "", "", bytes32(0));

        vm.prank(client2);
        vm.expectRevert(IAgentReputationRegistry.FeedbackNotFound.selector);
        reputation.revokeFeedback(agentId, 1);
    }

    function test_revokeFeedback_revertsForAlreadyRevoked() public {
        uint256 agentId = _registerAgent(agentOwner);

        vm.prank(client1);
        reputation.giveFeedback(agentId, 87, 0, "", "", "", "", bytes32(0));

        vm.prank(client1);
        reputation.revokeFeedback(agentId, 1);

        vm.prank(client1);
        vm.expectRevert(IAgentReputationRegistry.AlreadyRevoked.selector);
        reputation.revokeFeedback(agentId, 1);
    }

    function test_revokeFeedback_revertsForIndexZero() public {
        uint256 agentId = _registerAgent(agentOwner);

        vm.prank(client1);
        vm.expectRevert(IAgentReputationRegistry.FeedbackNotFound.selector);
        reputation.revokeFeedback(agentId, 0);
    }

    function test_revokeFeedback_revertsForOutOfBounds() public {
        uint256 agentId = _registerAgent(agentOwner);

        vm.prank(client1);
        vm.expectRevert(IAgentReputationRegistry.FeedbackNotFound.selector);
        reputation.revokeFeedback(agentId, 1);
    }

    // --- appendResponse ---

    function test_appendResponse_addsResponse() public {
        uint256 agentId = _registerAgent(agentOwner);

        vm.prank(client1);
        reputation.giveFeedback(agentId, 87, 0, "", "", "", "", bytes32(0));

        vm.prank(responder);
        reputation.appendResponse(agentId, client1, 1, "ipfs://response", bytes32(0));

        assertEq(reputation.getResponseCount(agentId, client1, 1), 1);
    }

    function test_appendResponse_emitsEvent() public {
        uint256 agentId = _registerAgent(agentOwner);

        vm.prank(client1);
        reputation.giveFeedback(agentId, 87, 0, "", "", "", "", bytes32(0));

        vm.prank(responder);
        vm.expectEmit(true, true, true, false);
        emit IAgentReputationRegistry.ResponseAppended(agentId, client1, 1, responder, "ipfs://response", bytes32(0));
        reputation.appendResponse(agentId, client1, 1, "ipfs://response", bytes32(0));
    }

    function test_appendResponse_revertsForIndexZero() public {
        uint256 agentId = _registerAgent(agentOwner);

        vm.prank(responder);
        vm.expectRevert(IAgentReputationRegistry.FeedbackNotFound.selector);
        reputation.appendResponse(agentId, client1, 0, "ipfs://response", bytes32(0));
    }

    function test_appendResponse_revertsForOutOfBounds() public {
        uint256 agentId = _registerAgent(agentOwner);

        vm.prank(responder);
        vm.expectRevert(IAgentReputationRegistry.FeedbackNotFound.selector);
        reputation.appendResponse(agentId, client1, 1, "ipfs://response", bytes32(0));
    }

    function test_appendResponse_allowsMultipleResponses() public {
        uint256 agentId = _registerAgent(agentOwner);

        vm.prank(client1);
        reputation.giveFeedback(agentId, 87, 0, "", "", "", "", bytes32(0));

        vm.prank(responder);
        reputation.appendResponse(agentId, client1, 1, "ipfs://r1", bytes32(0));

        vm.prank(agentOwner);
        reputation.appendResponse(agentId, client1, 1, "ipfs://r2", bytes32(0));

        assertEq(reputation.getResponseCount(agentId, client1, 1), 2);
    }

    // --- views ---

    function test_readFeedback_revertsForIndexZero() public {
        uint256 agentId = _registerAgent(agentOwner);

        vm.expectRevert(IAgentReputationRegistry.FeedbackNotFound.selector);
        reputation.readFeedback(agentId, client1, 0);
    }

    function test_readFeedback_revertsForOutOfBounds() public {
        uint256 agentId = _registerAgent(agentOwner);

        vm.expectRevert(IAgentReputationRegistry.FeedbackNotFound.selector);
        reputation.readFeedback(agentId, client1, 1);
    }

    function test_getLastIndex_returnsZeroForNewClient() public {
        uint256 agentId = _registerAgent(agentOwner);

        assertEq(reputation.getLastIndex(agentId, client1), 0);
    }

    function test_getResponseCount_returnsZeroForNoResponses() public {
        uint256 agentId = _registerAgent(agentOwner);

        vm.prank(client1);
        reputation.giveFeedback(agentId, 87, 0, "", "", "", "", bytes32(0));

        assertEq(reputation.getResponseCount(agentId, client1, 1), 0);
    }

    function test_getResponseCount_returnsZeroForIndexZero() public {
        uint256 agentId = _registerAgent(agentOwner);
        assertEq(reputation.getResponseCount(agentId, client1, 0), 0);
    }

    function test_getIdentityRegistry_returnsCorrectAddress() public view {
        assertEq(reputation.getIdentityRegistry(), address(identity));
    }

    function test_getClients_returnsFeedbackProviders() public {
        uint256 agentId = _registerAgent(agentOwner);

        vm.prank(client1);
        reputation.giveFeedback(agentId, 87, 0, "", "", "", "", bytes32(0));

        vm.prank(client2);
        reputation.giveFeedback(agentId, 92, 0, "", "", "", "", bytes32(0));

        address[] memory clients = reputation.getClients(agentId);
        assertEq(clients.length, 2);
        assertEq(clients[0], client1);
        assertEq(clients[1], client2);
    }
}
