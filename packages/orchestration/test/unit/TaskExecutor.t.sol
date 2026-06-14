// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {TaskExecutor} from "../../contracts/core/TaskExecutor.sol";
import {ITaskExecutor} from "../../contracts/interfaces/core/ITaskExecutor.sol";
import {OperatorRegistry} from "../../contracts/core/OperatorRegistry.sol";
import {CCTPHandler} from "../../contracts/handlers/CCTPHandler.sol";
import {ICCTPHandler} from "../../contracts/interfaces/handlers/ICCTPHandler.sol";
import {MockGovernanceToken} from "../../contracts/mocks/MockGovernanceToken.sol";
import {MockEscrowReceiver} from "../../contracts/mocks/MockEscrowReceiver.sol";
import {MockTaskHandler} from "../../contracts/mocks/MockTaskHandler.sol";
import {TaskLib} from "../../contracts/libraries/TaskLib.sol";
import {FeeManager} from "../../contracts/core/FeeManager.sol";
import {PausableUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";

contract TaskExecutorTest is Test {
    TaskExecutor executor;
    OperatorRegistry registry;
    CCTPHandler cctpHandler;
    MockGovernanceToken stakingToken;
    MockEscrowReceiver escrowReceiver;

    address owner;
    address operator1;
    address operator2;
    address user;

    uint256 constant MIN_STAKE = 5000e18;
    uint256 constant EXCLUSIVE_WINDOW = 60;
    uint256 constant PERMISSIONLESS_DELAY = 600;
    bytes32 TASK_CCTP_RELAY = TaskLib.TASK_CCTP_RELAY;

    function setUp() public {
        owner = makeAddr("owner");
        operator1 = makeAddr("operator1");
        operator2 = makeAddr("operator2");
        user = makeAddr("user");

        stakingToken = new MockGovernanceToken();
        escrowReceiver = new MockEscrowReceiver();

        OperatorRegistry registryImpl = new OperatorRegistry(address(0));
        bytes memory registryInitData = abi.encodeCall(
            OperatorRegistry.initialize,
            (owner, address(stakingToken), MIN_STAKE, EXCLUSIVE_WINDOW, PERMISSIONLESS_DELAY)
        );
        ERC1967Proxy registryProxy = new ERC1967Proxy(address(registryImpl), registryInitData);
        registry = OperatorRegistry(address(registryProxy));

        TaskExecutor executorImpl = new TaskExecutor(address(0));
        bytes memory executorInitData = abi.encodeCall(TaskExecutor.initialize, (owner, address(registry), address(0)));
        ERC1967Proxy executorProxy = new ERC1967Proxy(address(executorImpl), executorInitData);
        executor = TaskExecutor(address(executorProxy));

        CCTPHandler handlerImpl = new CCTPHandler(address(0));
        bytes memory handlerInitData = abi.encodeCall(
            CCTPHandler.initialize,
            (owner, address(escrowReceiver), address(executor))
        );
        ERC1967Proxy handlerProxy = new ERC1967Proxy(address(handlerImpl), handlerInitData);
        cctpHandler = CCTPHandler(address(handlerProxy));

        vm.prank(owner);
        registry.setMonitor(address(executor));

        vm.prank(owner);
        executor.registerHandler(TASK_CCTP_RELAY, address(cctpHandler));

        uint256 mintAmount = 100_000e18;
        stakingToken.mint(operator1, mintAmount);

        vm.prank(operator1);
        stakingToken.approve(address(registry), mintAmount);

        vm.prank(operator1);
        registry.registerOperator(MIN_STAKE);
    }

    function createMockCCTPMessage(uint256 escrowId, uint256 amount) internal pure returns (bytes memory) {
        bytes memory prefix = new bytes(216);
        bytes memory padding = new bytes(128);
        return abi.encodePacked(prefix, amount, padding, escrowId);
    }

    function encodeCCTPPayload(bytes memory message, bytes memory attestation) internal pure returns (bytes memory) {
        return abi.encode(ICCTPHandler.CCTPPayload(message, attestation));
    }

    function test_registerHandler_handlerIsRegistered() public view {
        assertEq(executor.getHandler(TASK_CCTP_RELAY), address(cctpHandler));
    }

    function test_registerHandler_failMismatchedTaskType() public {
        bytes32 differentType = keccak256("DIFFERENT_TYPE");
        MockTaskHandler mockHandler = new MockTaskHandler(differentType);

        bytes32 wrongType = keccak256("WRONG_TYPE");

        vm.prank(owner);
        vm.expectRevert(ITaskExecutor.InvalidHandler.selector);
        executor.registerHandler(wrongType, address(mockHandler));
    }

    function test_removeHandler() public {
        vm.prank(owner);
        executor.removeHandler(TASK_CCTP_RELAY);
        assertEq(executor.getHandler(TASK_CCTP_RELAY), address(0));
    }

    function test_executeTask_success() public {
        uint256 escrowId = 123;
        uint256 amount = 10_000e18;
        bytes memory message = createMockCCTPMessage(escrowId, amount);
        bytes memory attestation = hex"1234";
        bytes memory payload = encodeCCTPPayload(message, attestation);
        bytes32 messageHash = keccak256(message);

        vm.prank(operator1);
        registry.claimTask(messageHash);

        vm.prank(operator1);
        executor.executeTask(TASK_CCTP_RELAY, payload);

        assertTrue(registry.getTaskClaim(messageHash).executed);
    }

    function test_executeTask_emitEvent() public {
        uint256 escrowId = 456;
        uint256 amount = 5000e18;
        bytes memory message = createMockCCTPMessage(escrowId, amount);
        bytes memory attestation = hex"5678";
        bytes memory payload = encodeCCTPPayload(message, attestation);
        bytes32 messageHash = keccak256(message);

        vm.prank(operator1);
        registry.claimTask(messageHash);

        vm.prank(operator1);
        vm.expectEmit(true, true, true, true);
        emit ITaskExecutor.TaskExecuted(TASK_CCTP_RELAY, messageHash, operator1, 0);
        executor.executeTask(TASK_CCTP_RELAY, payload);
    }

    function test_executeTask_revertNotAuthorizedOperator() public {
        uint256 escrowId = 789;
        uint256 amount = 1000e18;
        bytes memory message = createMockCCTPMessage(escrowId, amount);
        bytes memory attestation = hex"abcd";
        bytes memory payload = encodeCCTPPayload(message, attestation);

        vm.prank(user);
        vm.expectRevert(ITaskExecutor.NotAuthorizedOperator.selector);
        executor.executeTask(TASK_CCTP_RELAY, payload);
    }

    function test_executeTask_revertUnknownTaskType() public {
        bytes32 unknownType = keccak256("UNKNOWN");
        bytes memory payload = hex"1234";

        vm.prank(operator1);
        vm.expectRevert(ITaskExecutor.UnknownTaskType.selector);
        executor.executeTask(unknownType, payload);
    }

    function test_pausable_pauseAndUnpause() public {
        uint256 escrowId = 999;
        uint256 amount = 100e18;
        bytes memory message = createMockCCTPMessage(escrowId, amount);
        bytes memory attestation = hex"ffff";
        bytes memory payload = encodeCCTPPayload(message, attestation);
        bytes32 messageHash = keccak256(message);

        vm.prank(owner);
        executor.pause();

        vm.prank(operator1);
        vm.expectRevert(PausableUpgradeable.EnforcedPause.selector);
        executor.executeTask(TASK_CCTP_RELAY, payload);

        vm.prank(owner);
        executor.unpause();

        vm.prank(operator1);
        registry.claimTask(messageHash);

        vm.prank(operator1);
        executor.executeTask(TASK_CCTP_RELAY, payload);

        assertTrue(registry.getTaskClaim(messageHash).executed);
    }

    function test_executeTask_nonCCTPHandler_skipsFeeLogic() public {
        FeeManager feeManagerImpl = new FeeManager(address(0));
        bytes memory feeManagerInitData = abi.encodeCall(
            FeeManager.initialize,
            (owner, address(stakingToken), owner, uint256(50))
        );
        ERC1967Proxy feeManagerProxy = new ERC1967Proxy(address(feeManagerImpl), feeManagerInitData);
        FeeManager feeManager = FeeManager(address(feeManagerProxy));

        vm.prank(owner);
        executor.setFeeManager(address(feeManager));

        bytes32 automationType = TaskLib.TASK_AUTOMATION;
        MockTaskHandler mockHandler = new MockTaskHandler(automationType);

        vm.prank(owner);
        executor.registerHandler(automationType, address(mockHandler));

        bytes memory payload = hex"deadbeef";
        bytes32 taskHash = mockHandler.getTaskHash(payload);

        vm.prank(operator1);
        registry.claimTask(taskHash);

        uint256 feeManagerBalanceBefore = stakingToken.balanceOf(address(feeManager));
        uint256 operatorBalanceBefore = stakingToken.balanceOf(operator1);

        vm.prank(operator1);
        vm.expectEmit(true, true, true, true);
        emit ITaskExecutor.TaskExecuted(automationType, taskHash, operator1, 0);
        executor.executeTask(automationType, payload);

        assertEq(stakingToken.balanceOf(address(feeManager)), feeManagerBalanceBefore);
        assertEq(stakingToken.balanceOf(operator1), operatorBalanceBefore);
        assertTrue(registry.getTaskClaim(taskHash).executed);
    }

    function test_admin_setRegistry() public {
        OperatorRegistry newRegistryImpl = new OperatorRegistry(address(0));
        bytes memory newRegistryInitData = abi.encodeCall(
            OperatorRegistry.initialize,
            (owner, address(stakingToken), MIN_STAKE, EXCLUSIVE_WINDOW, PERMISSIONLESS_DELAY)
        );
        ERC1967Proxy newRegistryProxy = new ERC1967Proxy(address(newRegistryImpl), newRegistryInitData);

        vm.prank(owner);
        executor.setRegistry(address(newRegistryProxy));

        assertEq(address(executor.registry()), address(newRegistryProxy));
    }
}
