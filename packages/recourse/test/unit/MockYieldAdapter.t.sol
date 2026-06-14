// SPDX-License-Identifier: FSL-1.1-ALv2
// Copyright (c) 2026 Reineira Labs Limited All rights reserved.
pragma solidity ^0.8.25;

import {Test} from "forge-std/Test.sol";
import {IERC20} from "@openzeppelin/contracts/interfaces/IERC20.sol";
import {MockUSDC} from "@reineira-os/shared/contracts/mocks/MockUSDC.sol";
import {MockYieldAdapter} from "../../contracts/mocks/MockYieldAdapter.sol";

contract MockYieldAdapterTest is Test {
    MockUSDC internal usdc;
    MockYieldAdapter internal adapter;
    address internal router;
    address internal receiver;

    uint256 constant AMOUNT = 1_000e6;

    function setUp() public {
        usdc = new MockUSDC();
        adapter = new MockYieldAdapter(IERC20(address(usdc)));
        router = makeAddr("router");
        receiver = makeAddr("receiver");

        usdc.mint(router, AMOUNT);
        vm.prank(router);
        usdc.approve(address(adapter), type(uint256).max);
    }

    function test_asset_returnsUnderlying() public view {
        assertEq(adapter.asset(), address(usdc));
    }

    function test_deposit_pullsAssetsAndTracksTotalAssets() public {
        vm.prank(router);
        adapter.deposit(AMOUNT);

        assertEq(adapter.totalAssets(), AMOUNT);
        assertEq(usdc.balanceOf(address(adapter)), AMOUNT);
        assertEq(usdc.balanceOf(router), 0);
    }

    function test_totalAssets_reflectsSimulatedYield() public {
        vm.prank(router);
        adapter.deposit(AMOUNT);

        // Simulate venue yield accrual by minting extra underlying into the adapter.
        usdc.mint(address(adapter), 50e6);

        assertEq(adapter.totalAssets(), AMOUNT + 50e6);
    }

    function test_maxWithdraw_fullyLiquidByDefault() public {
        vm.prank(router);
        adapter.deposit(AMOUNT);

        assertEq(adapter.maxWithdraw(), AMOUNT);
    }

    function test_withdraw_returnsRequestedWhenLiquid() public {
        vm.prank(router);
        adapter.deposit(AMOUNT);

        vm.prank(router);
        uint256 withdrawn = adapter.withdraw(400e6, receiver);

        assertEq(withdrawn, 400e6);
        assertEq(usdc.balanceOf(receiver), 400e6);
        assertEq(adapter.totalAssets(), 600e6);
    }

    function test_withdraw_cappedByVenueLiquidity() public {
        vm.prank(router);
        adapter.deposit(AMOUNT);

        // Venue can only honor 300 right now (e.g. high utilization).
        adapter.setLiquidity(300e6);

        vm.prank(router);
        uint256 withdrawn = adapter.withdraw(500e6, receiver);

        assertEq(withdrawn, 300e6);
        assertEq(usdc.balanceOf(receiver), 300e6);
        assertEq(adapter.maxWithdraw(), 0);
    }
}
