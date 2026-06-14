// SPDX-License-Identifier: FSL-1.1-ALv2
// Copyright (c) 2026 Reineira Labs Limited All rights reserved.
pragma solidity ^0.8.25;

import {Test} from "forge-std/Test.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {IERC20} from "@openzeppelin/contracts/interfaces/IERC20.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

import {MockUSDC} from "@reineira-os/shared/contracts/mocks/MockUSDC.sol";
import {PoolRiskLib} from "@reineira-os/shared/contracts/libraries/PoolRiskLib.sol";

import {StrategyRouter} from "../../contracts/core/StrategyRouter.sol";
import {IStrategyRouter} from "../../contracts/interfaces/core/IStrategyRouter.sol";
import {MockYieldAdapter} from "../../contracts/mocks/MockYieldAdapter.sol";

contract StrategyRouterTest is Test {
    StrategyRouter internal router;
    MockUSDC internal usdc;
    MockUSDC internal otherToken;
    MockYieldAdapter internal adapter;
    MockYieldAdapter internal adapter2;
    MockYieldAdapter internal mismatchedAdapter;

    address internal manager;
    address internal alice;
    address internal receiver;

    uint256 constant TIMELOCK = 1 days;

    function setUp() public {
        manager = makeAddr("manager");
        alice = makeAddr("alice");
        receiver = makeAddr("receiver");

        usdc = new MockUSDC();
        otherToken = new MockUSDC();

        adapter = new MockYieldAdapter(IERC20(address(usdc)));
        adapter2 = new MockYieldAdapter(IERC20(address(usdc)));
        mismatchedAdapter = new MockYieldAdapter(IERC20(address(otherToken)));

        StrategyRouter impl = new StrategyRouter(address(0));
        router = StrategyRouter(
            address(
                new ERC1967Proxy(address(impl), abi.encodeCall(StrategyRouter.initialize, (manager, address(usdc))))
            )
        );

        vm.prank(manager);
        usdc.mint(manager, 1_000_000e6);

        vm.prank(manager);
        usdc.approve(address(router), type(uint256).max);
    }

    // --- helpers ---

    function _attach(MockYieldAdapter a) internal {
        vm.prank(manager);
        router.submitAttachAdapter(address(a));
        vm.warp(block.timestamp + TIMELOCK);
        router.executeAttachAdapter(address(a));
    }

    function _raiseMaxDebt(MockYieldAdapter a, uint256 cap) internal {
        vm.prank(manager);
        router.submitMaxDebtRaise(address(a), cap);
        vm.warp(block.timestamp + TIMELOCK);
        router.executeMaxDebtRaise(address(a));
    }

    // --- initialization ---

    function test_initialize_setsOwnerAndAsset() public view {
        assertEq(router.owner(), manager);
        assertEq(router.asset(), address(usdc));
        assertEq(router.maxDeploymentBps(), 0); // starts conservative — manager must raise to use
        assertEq(router.TIMELOCK_DELAY(), TIMELOCK);
    }

    function test_initialize_revertsZeroOwner() public {
        StrategyRouter impl = new StrategyRouter(address(0));
        vm.expectRevert();
        new ERC1967Proxy(address(impl), abi.encodeCall(StrategyRouter.initialize, (address(0), address(usdc))));
    }

    function test_initialize_revertsZeroAsset() public {
        StrategyRouter impl = new StrategyRouter(address(0));
        vm.expectRevert();
        new ERC1967Proxy(address(impl), abi.encodeCall(StrategyRouter.initialize, (manager, address(0))));
    }

    // --- attach ---

    function test_attach_submitsWithUnlockAt() public {
        vm.prank(manager);
        router.submitAttachAdapter(address(adapter));
        assertEq(router.pendingAttach(address(adapter)), block.timestamp + TIMELOCK);
        assertEq(router.isAdapterAttached(address(adapter)), false);
    }

    function test_attach_executeRevertsBeforeTimelock() public {
        vm.prank(manager);
        router.submitAttachAdapter(address(adapter));
        vm.expectRevert(
            abi.encodeWithSelector(IStrategyRouter.TimelockNotElapsed.selector, block.timestamp + TIMELOCK)
        );
        router.executeAttachAdapter(address(adapter));
    }

    function test_attach_executeSucceedsAfterTimelock() public {
        _attach(adapter);
        assertEq(router.isAdapterAttached(address(adapter)), true);
        assertEq(router.pendingAttach(address(adapter)), 0);
        address[] memory list = router.adapters();
        assertEq(list.length, 1);
        assertEq(list[0], address(adapter));
    }

    function test_attach_executePermissionless() public {
        vm.prank(manager);
        router.submitAttachAdapter(address(adapter));
        vm.warp(block.timestamp + TIMELOCK);
        // anyone may execute after timelock
        vm.prank(alice);
        router.executeAttachAdapter(address(adapter));
        assertEq(router.isAdapterAttached(address(adapter)), true);
    }

    function test_attach_revertsIfAlreadyAttached() public {
        _attach(adapter);
        vm.prank(manager);
        vm.expectRevert(IStrategyRouter.AdapterAlreadyAttached.selector);
        router.submitAttachAdapter(address(adapter));
    }

    function test_attach_revertsIfAssetMismatch() public {
        vm.prank(manager);
        vm.expectRevert(IStrategyRouter.AdapterAssetMismatch.selector);
        router.submitAttachAdapter(address(mismatchedAdapter));
    }

    function test_attach_revertsIfExecuteWithoutPending() public {
        vm.expectRevert(IStrategyRouter.AttachNotPending.selector);
        router.executeAttachAdapter(address(adapter));
    }

    // --- detach ---

    function test_detach_instant() public {
        _attach(adapter);
        vm.prank(manager);
        router.detachAdapter(address(adapter));
        assertEq(router.isAdapterAttached(address(adapter)), false);
        assertEq(router.adapters().length, 0);
    }

    function test_detach_revertsIfNotAttached() public {
        vm.prank(manager);
        vm.expectRevert(IStrategyRouter.AdapterNotAttached.selector);
        router.detachAdapter(address(adapter));
    }

    function test_detach_revertsIfStillHasDebt() public {
        _attach(adapter);
        _raiseMaxDebt(adapter, 100e6);
        // raise deployment bps so deposit can proceed
        vm.prank(manager);
        router.submitMaxDeploymentBpsRaise(7000);
        vm.warp(block.timestamp + TIMELOCK);
        router.executeMaxDeploymentBpsRaise();

        vm.prank(manager);
        router.deposit(address(adapter), 50e6, 1000e6, 0);

        vm.prank(manager);
        vm.expectRevert(abi.encodeWithSelector(IStrategyRouter.AdapterStillHasDebt.selector, 50e6));
        router.detachAdapter(address(adapter));
    }

    function test_detach_clearsPendingMaxDebtAndBlocksExecute() public {
        _attach(adapter);

        vm.prank(manager);
        router.submitMaxDebtRaise(address(adapter), 100e6);

        (uint256 capBefore, uint256 unlockAtBefore) = router.pendingMaxDebt(address(adapter));
        assertEq(capBefore, 100e6);
        assertGt(unlockAtBefore, 0);

        vm.prank(manager);
        router.detachAdapter(address(adapter));

        (uint256 capAfter, uint256 unlockAtAfter) = router.pendingMaxDebt(address(adapter));
        assertEq(capAfter, 0);
        assertEq(unlockAtAfter, 0);

        vm.warp(block.timestamp + TIMELOCK);
        vm.expectRevert(IStrategyRouter.AdapterNotAttached.selector);
        router.executeMaxDebtRaise(address(adapter));
    }

    // --- maxDebt ---

    function test_maxDebt_raiseSubmitAndExecute() public {
        _attach(adapter);
        vm.prank(manager);
        router.submitMaxDebtRaise(address(adapter), 500e6);
        (uint256 cap, uint256 unlockAt) = router.pendingMaxDebt(address(adapter));
        assertEq(cap, 500e6);
        assertEq(unlockAt, block.timestamp + TIMELOCK);

        vm.warp(block.timestamp + TIMELOCK);
        router.executeMaxDebtRaise(address(adapter));
        assertEq(router.maxDebt(address(adapter)), 500e6);
    }

    function test_maxDebt_raiseRevertsIfNotARaise() public {
        _attach(adapter);
        _raiseMaxDebt(adapter, 500e6);
        vm.prank(manager);
        vm.expectRevert(IStrategyRouter.NotARaise.selector);
        router.submitMaxDebtRaise(address(adapter), 400e6);
    }

    function test_maxDebt_lowerInstant() public {
        _attach(adapter);
        _raiseMaxDebt(adapter, 500e6);
        vm.prank(manager);
        router.lowerMaxDebt(address(adapter), 200e6);
        assertEq(router.maxDebt(address(adapter)), 200e6);
    }

    function test_maxDebt_lowerRevertsIfNotALower() public {
        _attach(adapter);
        _raiseMaxDebt(adapter, 100e6);
        vm.prank(manager);
        vm.expectRevert(IStrategyRouter.NotALower.selector);
        router.lowerMaxDebt(address(adapter), 200e6);
    }

    // --- maxDeploymentBps ---

    function test_maxDeploymentBps_raiseSubmitAndExecute() public {
        vm.prank(manager);
        router.submitMaxDeploymentBpsRaise(5000);
        vm.warp(block.timestamp + TIMELOCK);
        router.executeMaxDeploymentBpsRaise();
        assertEq(router.maxDeploymentBps(), 5000);
    }

    function test_maxDeploymentBps_raiseRevertsAboveCeiling() public {
        vm.prank(manager);
        vm.expectRevert(abi.encodeWithSelector(PoolRiskLib.MaxDeploymentTooHigh.selector, uint16(7001)));
        router.submitMaxDeploymentBpsRaise(7001);
    }

    function test_maxDeploymentBps_lowerInstant() public {
        vm.prank(manager);
        router.submitMaxDeploymentBpsRaise(5000);
        vm.warp(block.timestamp + TIMELOCK);
        router.executeMaxDeploymentBpsRaise();

        vm.prank(manager);
        router.lowerMaxDeploymentBps(3000);
        assertEq(router.maxDeploymentBps(), 3000);
    }

    // --- claimsBuffer + minIdle ---

    function test_setClaimsBufferBps_stores() public {
        vm.prank(manager);
        router.setClaimsBufferBps(5000);
        assertEq(router.claimsBufferBps(), 5000);
    }

    function test_setClaimsBufferBps_revertsAbove10000() public {
        vm.prank(manager);
        vm.expectRevert(abi.encodeWithSelector(IStrategyRouter.InvalidBps.selector, uint16(10001)));
        router.setClaimsBufferBps(10001);
    }

    function test_setMinIdleReserve_stores() public {
        vm.prank(manager);
        router.setMinIdleReserve(123e6);
        assertEq(router.minIdleReserve(), 123e6);
    }

    // --- deposit ---

    function _setUpForDeposit(uint16 bps) internal {
        _attach(adapter);
        _raiseMaxDebt(adapter, 1_000e6);
        vm.prank(manager);
        router.submitMaxDeploymentBpsRaise(bps);
        vm.warp(block.timestamp + TIMELOCK);
        router.executeMaxDeploymentBpsRaise();
    }

    function test_deposit_pullsAndTracksDeployed() public {
        _setUpForDeposit(7000);

        uint256 managerBefore = usdc.balanceOf(manager);
        vm.prank(manager);
        router.deposit(address(adapter), 500e6, 1000e6, 0);

        assertEq(usdc.balanceOf(manager), managerBefore - 500e6);
        assertEq(usdc.balanceOf(address(adapter)), 500e6);
        assertEq(usdc.balanceOf(address(router)), 0);
        assertEq(router.deployed(address(adapter)), 500e6);
        assertEq(router.totalDeployed(), 500e6);
    }

    function test_deposit_revertsIfAdapterNotAttached() public {
        vm.prank(manager);
        vm.expectRevert(IStrategyRouter.AdapterNotAttached.selector);
        router.deposit(address(adapter), 1e6, 1000e6, 0);
    }

    function test_deposit_revertsIfExceedsAdapterMaxDebt() public {
        _setUpForDeposit(7000);
        // adapter maxDebt = 1_000e6 (from helper); deploy 600 first, then attempt 500 more.
        vm.prank(manager);
        router.deposit(address(adapter), 600e6, 10_000e6, 0);
        vm.prank(manager);
        vm.expectRevert(abi.encodeWithSelector(IStrategyRouter.AdapterMaxDebtExceeded.selector, 500e6, 400e6));
        router.deposit(address(adapter), 500e6, 10_000e6, 0);
    }

    function test_deposit_revertsIfBreachesRiskInvariant() public {
        _setUpForDeposit(7000);
        // totalAssets=1000, 70% deployable -> 700 max. Asking 750 must revert.
        vm.prank(manager);
        vm.expectRevert(abi.encodeWithSelector(PoolRiskLib.DeploymentExceedsLimit.selector, 750e6, 700e6));
        router.deposit(address(adapter), 750e6, 1000e6, 0);
    }

    function test_deposit_riskCheckUsesLiveAdapterTotalAssets() public {
        _setUpForDeposit(7000);
        _attach(adapter2);
        _raiseMaxDebt(adapter2, 1_000e6);

        // Deploy 400 to adapter then simulate yield to push its totalAssets above the principal.
        vm.prank(manager);
        router.deposit(address(adapter), 400e6, 1000e6, 0);
        usdc.mint(address(adapter), 100e6); // adapter.totalAssets() now 500 — live read

        // currentlyDeployed (live) = 500. totalAssets=1000, required=300, max additional = 1000-300-500 = 200.
        // 250 must revert.
        vm.prank(manager);
        vm.expectRevert(abi.encodeWithSelector(PoolRiskLib.DeploymentExceedsLimit.selector, 250e6, 200e6));
        router.deposit(address(adapter2), 250e6, 1000e6, 0);
    }

    // --- withdraw ---

    function test_withdraw_callsAdapterAndDecrementsDeployed() public {
        _setUpForDeposit(7000);
        vm.prank(manager);
        router.deposit(address(adapter), 500e6, 1000e6, 0);

        vm.prank(manager);
        uint256 withdrawn = router.withdraw(address(adapter), 200e6, receiver);

        assertEq(withdrawn, 200e6);
        assertEq(usdc.balanceOf(receiver), 200e6);
        assertEq(router.deployed(address(adapter)), 300e6);
    }

    function test_withdraw_handlesVenueIlliquidityPartial() public {
        _setUpForDeposit(7000);
        vm.prank(manager);
        router.deposit(address(adapter), 500e6, 1000e6, 0);

        adapter.setLiquidity(120e6); // venue can honor only 120

        vm.prank(manager);
        uint256 withdrawn = router.withdraw(address(adapter), 500e6, receiver);

        assertEq(withdrawn, 120e6);
        assertEq(usdc.balanceOf(receiver), 120e6);
        assertEq(router.deployed(address(adapter)), 380e6);
    }

    function test_withdraw_revertsIfAdapterNotAttached() public {
        vm.prank(manager);
        vm.expectRevert(IStrategyRouter.AdapterNotAttached.selector);
        router.withdraw(address(adapter), 1, receiver);
    }

    // --- access control (representative) ---

    function test_submitAttach_revertsForNonOwner() public {
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, alice));
        router.submitAttachAdapter(address(adapter));
    }

    function test_deposit_revertsForNonOwner() public {
        _setUpForDeposit(7000);
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, alice));
        router.deposit(address(adapter), 1, 1000e6, 0);
    }
}
