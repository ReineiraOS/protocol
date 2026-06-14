// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {CCTPHandler} from "../../contracts/handlers/CCTPHandler.sol";
import {ICCTPHandler} from "../../contracts/interfaces/handlers/ICCTPHandler.sol";
import {MockEscrowReceiver} from "../../contracts/mocks/MockEscrowReceiver.sol";
import {CCTPMessageLib} from "../../contracts/libraries/CCTPMessageLib.sol";
import {TaskLib} from "../../contracts/libraries/TaskLib.sol";
import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import {PausableUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";

contract CCTPHandlerTest is Test {
    CCTPHandler handler;
    MockEscrowReceiver escrowReceiver;

    address owner;
    address executor;
    address user;

    function setUp() public {
        owner = makeAddr("owner");
        executor = makeAddr("executor");
        user = makeAddr("user");

        escrowReceiver = new MockEscrowReceiver();

        CCTPHandler impl = new CCTPHandler(address(0));
        bytes memory initData = abi.encodeCall(CCTPHandler.initialize, (owner, address(escrowReceiver), executor));
        ERC1967Proxy proxy = new ERC1967Proxy(address(impl), initData);
        handler = CCTPHandler(address(proxy));
    }

    function buildCCTPMessage(uint256 amount, uint256 escrowId) internal pure returns (bytes memory) {
        bytes memory header = new bytes(216);
        return abi.encodePacked(header, amount, bytes32(0), bytes32(0), bytes32(0), bytes32(0), escrowId);
    }

    function buildCCTPPayload(uint256 amount, uint256 escrowId) internal pure returns (bytes memory) {
        bytes memory message = buildCCTPMessage(amount, escrowId);
        bytes memory attestation = new bytes(65);
        return abi.encode(ICCTPHandler.CCTPPayload(message, attestation));
    }

    function test_deploy_correctParams() public view {
        assertEq(address(handler.escrowReceiver()), address(escrowReceiver));
        assertEq(handler.executor(), executor);
    }

    function test_deploy_revertZeroEscrowReceiver() public {
        CCTPHandler impl = new CCTPHandler(address(0));
        bytes memory initData = abi.encodeCall(CCTPHandler.initialize, (owner, address(0), executor));
        vm.expectRevert(CCTPMessageLib.MalformedMessage.selector);
        new ERC1967Proxy(address(impl), initData);
    }

    function test_deploy_revertZeroExecutor() public {
        CCTPHandler impl = new CCTPHandler(address(0));
        bytes memory initData = abi.encodeCall(CCTPHandler.initialize, (owner, address(escrowReceiver), address(0)));
        vm.expectRevert(CCTPMessageLib.MalformedMessage.selector);
        new ERC1967Proxy(address(impl), initData);
    }

    function test_executeTask_settlesEscrow() public {
        uint256 amount = 1_000_000;
        uint256 escrowId = 12345;
        bytes memory payload = buildCCTPPayload(amount, escrowId);
        bytes memory message = buildCCTPMessage(amount, escrowId);
        bytes32 messageHash = keccak256(message);

        vm.prank(executor);
        vm.expectEmit(true, true, false, true);
        emit ICCTPHandler.EscrowSettled(messageHash, escrowId, amount);
        handler.executeTask(payload);
    }

    function test_executeTask_returnEncodedResult() public {
        uint256 amount = 2_000_000;
        uint256 escrowId = 67890;
        bytes memory payload = buildCCTPPayload(amount, escrowId);

        vm.prank(executor);
        bytes memory result = handler.executeTask(payload);

        (uint256 returnedEscrowId, uint256 returnedAmount) = abi.decode(result, (uint256, uint256));
        assertEq(returnedEscrowId, escrowId);
        assertEq(returnedAmount, amount);
    }

    function test_executeTask_revertNotExecutor() public {
        bytes memory payload = buildCCTPPayload(1_000_000, 12345);

        vm.prank(user);
        vm.expectRevert(CCTPHandler.NotExecutor.selector);
        handler.executeTask(payload);
    }

    function test_executeTask_revertWhenPaused() public {
        bytes memory payload = buildCCTPPayload(1_000_000, 12345);

        vm.prank(owner);
        handler.pause();

        vm.prank(executor);
        vm.expectRevert(PausableUpgradeable.EnforcedPause.selector);
        handler.executeTask(payload);
    }

    function test_validateTask_trueForValid() public view {
        bytes memory payload = buildCCTPPayload(1_000_000, 12345);
        assertTrue(handler.validateTask(payload));
    }

    function test_validateTask_falseForShortMessage() public view {
        bytes memory shortMessage = hex"1234";
        bytes memory attestation = "";
        bytes memory payload = abi.encode(ICCTPHandler.CCTPPayload(shortMessage, attestation));
        assertFalse(handler.validateTask(payload));
    }

    function test_validateTask_falseForVeryShortPayload() public view {
        assertFalse(handler.validateTask(hex"1234"));
    }

    function test_getTaskHash_returnsKeccakOfMessage() public view {
        uint256 amount = 1_000_000;
        uint256 escrowId = 12345;
        bytes memory message = buildCCTPMessage(amount, escrowId);
        bytes memory payload = buildCCTPPayload(amount, escrowId);

        bytes32 taskHash = handler.getTaskHash(payload);
        assertEq(taskHash, keccak256(message));
    }

    function test_taskType_returnsCCTPRelay() public view {
        assertEq(handler.taskType(), TaskLib.TASK_CCTP_RELAY);
    }

    function test_setEscrowReceiver_updatesReceiver() public {
        MockEscrowReceiver newReceiver = new MockEscrowReceiver();

        vm.prank(owner);
        handler.setEscrowReceiver(address(newReceiver));

        assertEq(address(handler.escrowReceiver()), address(newReceiver));
    }

    function test_setEscrowReceiver_emitsEvent() public {
        MockEscrowReceiver newReceiver = new MockEscrowReceiver();

        vm.prank(owner);
        vm.expectEmit(true, true, false, false);
        emit ICCTPHandler.EscrowReceiverUpdated(address(escrowReceiver), address(newReceiver));
        handler.setEscrowReceiver(address(newReceiver));
    }

    function test_setEscrowReceiver_revertZeroAddress() public {
        vm.prank(owner);
        vm.expectRevert(CCTPMessageLib.MalformedMessage.selector);
        handler.setEscrowReceiver(address(0));
    }

    function test_setEscrowReceiver_revertNonOwner() public {
        MockEscrowReceiver newReceiver = new MockEscrowReceiver();

        vm.prank(user);
        vm.expectRevert(abi.encodeWithSelector(OwnableUpgradeable.OwnableUnauthorizedAccount.selector, user));
        handler.setEscrowReceiver(address(newReceiver));
    }

    function test_setExecutor_updatesExecutor() public {
        vm.prank(owner);
        handler.setExecutor(user);
        assertEq(handler.executor(), user);
    }

    function test_setExecutor_revertZeroAddress() public {
        vm.prank(owner);
        vm.expectRevert(CCTPMessageLib.MalformedMessage.selector);
        handler.setExecutor(address(0));
    }

    function test_setExecutor_revertNonOwner() public {
        vm.prank(user);
        vm.expectRevert(abi.encodeWithSelector(OwnableUpgradeable.OwnableUnauthorizedAccount.selector, user));
        handler.setExecutor(user);
    }

    function test_pausable_pauseAndUnpause() public {
        bytes memory payload = buildCCTPPayload(1_000_000, 12345);

        vm.prank(owner);
        handler.pause();

        vm.prank(executor);
        vm.expectRevert(PausableUpgradeable.EnforcedPause.selector);
        handler.executeTask(payload);

        vm.prank(owner);
        handler.unpause();

        vm.prank(executor);
        handler.executeTask(payload);
    }
}
