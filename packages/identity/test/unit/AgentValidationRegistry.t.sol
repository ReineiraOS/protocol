// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.25;

import {Test} from "forge-std/Test.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {AgentIdentityRegistry} from "../../contracts/core/AgentIdentityRegistry.sol";
import {AgentValidationRegistry} from "../../contracts/core/AgentValidationRegistry.sol";
import {IAgentValidationRegistry} from "../../contracts/interfaces/core/IAgentValidationRegistry.sol";
import {ICore} from "@reineira-os/shared/contracts/interfaces/core/ICore.sol";

contract AgentValidationRegistryTest is Test {
    AgentIdentityRegistry public identity;
    AgentValidationRegistry public validation;

    address owner = makeAddr("owner");
    address agentOwner = makeAddr("agentOwner");
    address validator = makeAddr("validator");
    address other = makeAddr("other");

    function setUp() public {
        vm.startPrank(owner);
        AgentIdentityRegistry identityImpl = new AgentIdentityRegistry(address(0));
        bytes memory identityInit = abi.encodeCall(AgentIdentityRegistry.initialize, (owner));
        ERC1967Proxy identityProxy = new ERC1967Proxy(address(identityImpl), identityInit);
        identity = AgentIdentityRegistry(address(identityProxy));

        AgentValidationRegistry validationImpl = new AgentValidationRegistry(address(0));
        bytes memory validationInit = abi.encodeCall(AgentValidationRegistry.initialize, (owner, address(identity)));
        ERC1967Proxy validationProxy = new ERC1967Proxy(address(validationImpl), validationInit);
        validation = AgentValidationRegistry(address(validationProxy));
        vm.stopPrank();
    }

    function _registerAgent(address registrant) internal returns (uint256) {
        vm.prank(registrant);
        return identity.register("ipfs://agent");
    }

    // --- validationRequest ---

    function test_validationRequest_createsRequest() public {
        uint256 agentId = _registerAgent(agentOwner);
        bytes32 requestHash = keccak256("request1");

        vm.prank(agentOwner);
        validation.validationRequest(validator, agentId, "ipfs://request", requestHash);

        (address v, , uint8 response, bytes32 responseHash, string memory tag, uint256 lastUpdate) = validation
            .getValidationStatus(requestHash);

        assertEq(v, validator);
        assertEq(response, 0);
        assertEq(responseHash, bytes32(0));
        assertEq(tag, "");
        assertEq(lastUpdate, 0);
    }

    function test_validationRequest_emitsEvent() public {
        uint256 agentId = _registerAgent(agentOwner);
        bytes32 requestHash = keccak256("request1");

        vm.prank(agentOwner);
        vm.expectEmit(true, true, false, true);
        emit IAgentValidationRegistry.ValidationRequest(validator, agentId, "ipfs://request", requestHash);
        validation.validationRequest(validator, agentId, "ipfs://request", requestHash);
    }

    function test_validationRequest_tracksAgentValidations() public {
        uint256 agentId = _registerAgent(agentOwner);
        bytes32 requestHash = keccak256("request1");

        vm.prank(agentOwner);
        validation.validationRequest(validator, agentId, "ipfs://request", requestHash);

        bytes32[] memory hashes = validation.getAgentValidations(agentId);
        assertEq(hashes.length, 1);
        assertEq(hashes[0], requestHash);
    }

    function test_validationRequest_tracksValidatorRequests() public {
        uint256 agentId = _registerAgent(agentOwner);
        bytes32 requestHash = keccak256("request1");

        vm.prank(agentOwner);
        validation.validationRequest(validator, agentId, "ipfs://request", requestHash);

        bytes32[] memory hashes = validation.getValidatorRequests(validator);
        assertEq(hashes.length, 1);
        assertEq(hashes[0], requestHash);
    }

    function test_validationRequest_revertsForNonOwner() public {
        uint256 agentId = _registerAgent(agentOwner);
        bytes32 requestHash = keccak256("request1");

        vm.prank(other);
        vm.expectRevert(ICore.Unauthorized.selector);
        validation.validationRequest(validator, agentId, "ipfs://request", requestHash);
    }

    function test_validationRequest_revertsForZeroValidator() public {
        uint256 agentId = _registerAgent(agentOwner);
        bytes32 requestHash = keccak256("request1");

        vm.prank(agentOwner);
        vm.expectRevert(IAgentValidationRegistry.InvalidValidator.selector);
        validation.validationRequest(address(0), agentId, "ipfs://request", requestHash);
    }

    function test_validationRequest_revertsForZeroHash() public {
        uint256 agentId = _registerAgent(agentOwner);

        vm.prank(agentOwner);
        vm.expectRevert(IAgentValidationRegistry.ZeroHash.selector);
        validation.validationRequest(validator, agentId, "ipfs://request", bytes32(0));
    }

    function test_validationRequest_revertsForDuplicateHash() public {
        uint256 agentId = _registerAgent(agentOwner);
        bytes32 requestHash = keccak256("request1");

        vm.prank(agentOwner);
        validation.validationRequest(validator, agentId, "ipfs://request", requestHash);

        vm.prank(agentOwner);
        vm.expectRevert(IAgentValidationRegistry.DuplicateRequest.selector);
        validation.validationRequest(validator, agentId, "ipfs://request2", requestHash);
    }

    // --- validationResponse ---

    function test_validationResponse_storesResponse() public {
        uint256 agentId = _registerAgent(agentOwner);
        bytes32 requestHash = keccak256("request1");

        vm.prank(agentOwner);
        validation.validationRequest(validator, agentId, "ipfs://request", requestHash);

        vm.prank(validator);
        validation.validationResponse(requestHash, 100, "ipfs://response", bytes32(0), "passed");

        (, , uint8 response, , string memory tag, uint256 lastUpdate) = validation.getValidationStatus(requestHash);

        assertEq(response, 100);
        assertEq(tag, "passed");
        assertGt(lastUpdate, 0);
    }

    function test_validationResponse_emitsEvent() public {
        uint256 agentId = _registerAgent(agentOwner);
        bytes32 requestHash = keccak256("request1");

        vm.prank(agentOwner);
        validation.validationRequest(validator, agentId, "ipfs://request", requestHash);

        vm.prank(validator);
        vm.expectEmit(true, true, true, true);
        emit IAgentValidationRegistry.ValidationResponse(
            validator,
            agentId,
            requestHash,
            100,
            "ipfs://response",
            bytes32(0),
            "passed"
        );
        validation.validationResponse(requestHash, 100, "ipfs://response", bytes32(0), "passed");
    }

    function test_validationResponse_allowsMultipleResponses() public {
        uint256 agentId = _registerAgent(agentOwner);
        bytes32 requestHash = keccak256("request1");

        vm.prank(agentOwner);
        validation.validationRequest(validator, agentId, "ipfs://request", requestHash);

        vm.prank(validator);
        validation.validationResponse(requestHash, 50, "ipfs://response1", bytes32(0), "partial");

        vm.prank(validator);
        validation.validationResponse(requestHash, 100, "ipfs://response2", bytes32(0), "final");

        (, , uint8 response, , string memory tag, ) = validation.getValidationStatus(requestHash);
        assertEq(response, 100);
        assertEq(tag, "final");
    }

    function test_validationResponse_revertsForNonValidator() public {
        uint256 agentId = _registerAgent(agentOwner);
        bytes32 requestHash = keccak256("request1");

        vm.prank(agentOwner);
        validation.validationRequest(validator, agentId, "ipfs://request", requestHash);

        vm.prank(other);
        vm.expectRevert(IAgentValidationRegistry.NotValidator.selector);
        validation.validationResponse(requestHash, 100, "ipfs://response", bytes32(0), "passed");
    }

    function test_validationResponse_revertsForInvalidResponse() public {
        uint256 agentId = _registerAgent(agentOwner);
        bytes32 requestHash = keccak256("request1");

        vm.prank(agentOwner);
        validation.validationRequest(validator, agentId, "ipfs://request", requestHash);

        vm.prank(validator);
        vm.expectRevert(IAgentValidationRegistry.InvalidResponse.selector);
        validation.validationResponse(requestHash, 101, "ipfs://response", bytes32(0), "passed");
    }

    function test_validationResponse_revertsForUnknownHash() public {
        vm.prank(validator);
        vm.expectRevert(IAgentValidationRegistry.RequestNotFound.selector);
        validation.validationResponse(keccak256("unknown"), 100, "ipfs://response", bytes32(0), "passed");
    }

    // --- views ---

    function test_getValidationStatus_revertsForUnknownHash() public {
        vm.expectRevert(IAgentValidationRegistry.RequestNotFound.selector);
        validation.getValidationStatus(keccak256("unknown"));
    }

    function test_getAgentValidations_returnsEmptyForNewAgent() public view {
        bytes32[] memory hashes = validation.getAgentValidations(99);
        assertEq(hashes.length, 0);
    }

    function test_getValidatorRequests_returnsEmptyForNewValidator() public view {
        bytes32[] memory hashes = validation.getValidatorRequests(validator);
        assertEq(hashes.length, 0);
    }

    function test_getIdentityRegistry_returnsCorrectAddress() public view {
        assertEq(validation.getIdentityRegistry(), address(identity));
    }
}
