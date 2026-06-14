// SPDX-License-Identifier: FSL-1.1-ALv2
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {OperatorRegistry} from "../../contracts/core/OperatorRegistry.sol";
import {MockGovernanceToken} from "../../contracts/mocks/MockGovernanceToken.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {IOperatorRegistry} from "../../contracts/interfaces/core/IOperatorRegistry.sol";

contract OperatorRegistryTest is Test {
    uint256 constant MIN_STAKE = 5000e18;
    uint256 constant EXCLUSIVE_WINDOW = 60;
    uint256 constant PERMISSIONLESS_DELAY = 600;
    uint256 constant UNBOND_PERIOD = 7 days;
    uint256 constant MINT_AMOUNT = 100_000e18;

    OperatorRegistry registry;
    MockGovernanceToken stakingToken;

    address owner = makeAddr("owner");
    address operator1 = makeAddr("operator1");
    address operator2 = makeAddr("operator2");
    address monitor = makeAddr("monitor");

    function setUp() public {
        vm.startPrank(owner);

        stakingToken = new MockGovernanceToken();

        OperatorRegistry impl = new OperatorRegistry(address(0));
        bytes memory initData = abi.encodeCall(
            OperatorRegistry.initialize,
            (owner, address(stakingToken), MIN_STAKE, EXCLUSIVE_WINDOW, PERMISSIONLESS_DELAY)
        );
        ERC1967Proxy proxy = new ERC1967Proxy(address(impl), initData);
        registry = OperatorRegistry(address(proxy));

        stakingToken.mint(operator1, MINT_AMOUNT);
        stakingToken.mint(operator2, MINT_AMOUNT);

        vm.stopPrank();

        vm.prank(operator1);
        stakingToken.approve(address(registry), MINT_AMOUNT);

        vm.prank(operator2);
        stakingToken.approve(address(registry), MINT_AMOUNT);
    }

    function _registerOperator(address operator) internal {
        vm.prank(operator);
        registry.registerOperator(MIN_STAKE);
    }

    function test_deployment_initializesWithCorrectParams() public view {
        assertEq(registry.minStake(), MIN_STAKE);
        assertEq(registry.exclusiveWindow(), EXCLUSIVE_WINDOW);
        assertEq(registry.permissionlessDelay(), PERMISSIONLESS_DELAY);
        assertEq(address(registry.stakingToken()), address(stakingToken));
    }

    function test_registration_registersWithValidStake() public {
        _registerOperator(operator1);

        IOperatorRegistry.OperatorInfo memory info = registry.getOperatorInfo(operator1);
        assertEq(info.stake, MIN_STAKE);
        assertTrue(info.isActive);
        assertFalse(info.slashed);
    }

    function test_registration_emitsOperatorRegisteredEvent() public {
        vm.expectEmit(true, false, false, true, address(registry));
        emit IOperatorRegistry.OperatorRegistered(operator1, MIN_STAKE);

        vm.prank(operator1);
        registry.registerOperator(MIN_STAKE);
    }

    function test_registration_revertsWithInsufficientStake() public {
        vm.prank(operator1);
        vm.expectRevert(IOperatorRegistry.InsufficientStake.selector);
        registry.registerOperator(MIN_STAKE - 1);
    }

    function test_registration_revertsWhenAlreadyRegistered() public {
        _registerOperator(operator1);

        vm.prank(operator1);
        vm.expectRevert(IOperatorRegistry.AlreadyRegistered.selector);
        registry.registerOperator(MIN_STAKE);
    }

    function test_stake_addStakeIncreasesOperatorStake() public {
        _registerOperator(operator1);

        uint256 additionalStake = 1000e18;
        vm.prank(operator1);
        registry.addStake(additionalStake);

        IOperatorRegistry.OperatorInfo memory info = registry.getOperatorInfo(operator1);
        assertEq(info.stake, MIN_STAKE + additionalStake);
    }

    function test_unbonding_requestUnbondDeactivatesOperator() public {
        _registerOperator(operator1);

        vm.prank(operator1);
        registry.requestUnbond();

        IOperatorRegistry.OperatorInfo memory info = registry.getOperatorInfo(operator1);
        assertFalse(info.isActive);
        assertGt(info.unbondRequestTime, 0);
    }

    function test_unbonding_withdrawStakeAfterUnbondPeriod() public {
        _registerOperator(operator1);

        vm.prank(operator1);
        registry.requestUnbond();

        vm.warp(block.timestamp + UNBOND_PERIOD + 1);

        uint256 balanceBefore = stakingToken.balanceOf(operator1);

        vm.prank(operator1);
        registry.withdrawStake();

        uint256 balanceAfter = stakingToken.balanceOf(operator1);
        assertEq(balanceAfter - balanceBefore, MIN_STAKE);
    }

    function test_taskClaiming_claimTaskSetsOperator() public {
        _registerOperator(operator1);

        bytes32 taskHash = keccak256("test task");

        vm.prank(operator1);
        registry.claimTask(taskHash);

        IOperatorRegistry.TaskClaim memory claim = registry.getTaskClaim(taskHash);
        assertEq(claim.operator, operator1);
    }

    function test_taskExecution_activeOperatorCanExecuteUnclaimedTask() public {
        _registerOperator(operator1);

        bytes32 taskHash = keccak256("test task");
        assertTrue(registry.canExecuteTask(operator1, taskHash));
    }

    function test_taskExecution_exclusiveWindowEnforcedForClaimer() public {
        _registerOperator(operator1);
        _registerOperator(operator2);

        bytes32 taskHash = keccak256("test task");

        vm.prank(operator1);
        registry.claimTask(taskHash);

        assertTrue(registry.canExecuteTask(operator1, taskHash));
        assertFalse(registry.canExecuteTask(operator2, taskHash));
    }

    function test_slashing_slashReducesStakeAndDeactivates() public {
        _registerOperator(operator1);

        uint256 slashAmount = 1000e18;
        bytes32 evidence = keccak256("slash evidence");

        uint256 ownerBalanceBefore = stakingToken.balanceOf(owner);

        vm.prank(owner);
        registry.slash(operator1, slashAmount, evidence);

        IOperatorRegistry.OperatorInfo memory info = registry.getOperatorInfo(operator1);
        assertEq(info.stake, MIN_STAKE - slashAmount);
        assertTrue(info.slashed);
        assertFalse(info.isActive);

        uint256 ownerBalanceAfter = stakingToken.balanceOf(owner);
        assertEq(ownerBalanceAfter - ownerBalanceBefore, slashAmount);
    }

    function test_slashing_slashedOperatorCannotReRegister() public {
        _registerOperator(operator1);

        bytes32 evidence = keccak256("slash evidence");

        vm.prank(owner);
        registry.slash(operator1, MIN_STAKE, evidence);

        vm.prank(operator1);
        vm.expectRevert(IOperatorRegistry.PermanentlySlashed.selector);
        registry.registerOperator(MIN_STAKE);
    }

    function test_pausable_pauseBlocksRegistrationUnpauseAllows() public {
        vm.prank(owner);
        registry.pause();

        vm.prank(operator1);
        vm.expectRevert();
        registry.registerOperator(MIN_STAKE);

        vm.prank(owner);
        registry.unpause();

        _registerOperator(operator1);

        IOperatorRegistry.OperatorInfo memory info = registry.getOperatorInfo(operator1);
        assertTrue(info.isActive);
    }

    function test_admin_setMonitorUpdatesMonitor() public {
        vm.prank(owner);
        registry.setMonitor(monitor);

        assertEq(registry.monitor(), monitor);
    }

    function test_admin_setConfigUpdatesAllParams() public {
        uint256 newMinStake = 10_000e18;
        uint256 newExclusiveWindow = 120;
        uint256 newPermissionlessDelay = 1200;

        vm.prank(owner);
        registry.setConfig(newMinStake, newExclusiveWindow, newPermissionlessDelay);

        assertEq(registry.minStake(), newMinStake);
        assertEq(registry.exclusiveWindow(), newExclusiveWindow);
        assertEq(registry.permissionlessDelay(), newPermissionlessDelay);
    }
}
