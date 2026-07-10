// SPDX-License-Identifier: FSL-1.1-ALv2
pragma solidity ^0.8.25;

import {Test, console2} from "forge-std/Test.sol";
import {PolicyRegistry} from "../../contracts/core/PolicyRegistry.sol";
import {PoolFactory} from "../../contracts/core/PoolFactory.sol";
import {RecoursePool} from "../../contracts/core/RecoursePool.sol";
import {CoverageManager} from "../../contracts/core/CoverageManager.sol";
import {ICoverageManager} from "../../contracts/interfaces/core/ICoverageManager.sol";
import {MockUSDC} from "@reineira-os/shared/contracts/mocks/MockUSDC.sol";
import {MockEscrow} from "../../contracts/mocks/MockEscrow.sol";
import {MockUnderwriterPolicy} from "../../contracts/mocks/MockUnderwriterPolicy.sol";

contract DemoPayoutForkTest is Test {
    address constant PLAIN_COVERAGE_MANAGER = 0xE93191EE7C275E2C8a93FE9A6a2a67f2124daB8E;
    address constant PLAIN_POOL_FACTORY = 0x2AA20E195290426ad626F65C540FCE2A58DFF9AF;
    address constant PLAIN_POLICY_REGISTRY = 0x44A8314006E036047586bA90cD3FC153B8990361;

    uint256 constant STAKE = 50_000e6;
    uint256 constant ESCROW_AMOUNT = 20_000e6;
    uint256 constant COVERAGE = 10_000e6;
    uint256 constant ESCROW_ID = 987654321;

    function test_deployedStack_paysOutClientOnDispute() public {
        string memory rpc =
            vm.envOr("ARBITRUM_SEPOLIA_RPC_URL", string("https://sepolia-rollup.arbitrum.io/rpc"));
        vm.createSelectFork(rpc);

        CoverageManager cm = CoverageManager(PLAIN_COVERAGE_MANAGER);
        PoolFactory factory = PoolFactory(PLAIN_POOL_FACTORY);
        PolicyRegistry registry = PolicyRegistry(PLAIN_POLICY_REGISTRY);

        MockUSDC usdc = new MockUSDC();
        MockEscrow escrow = new MockEscrow();
        MockUnderwriterPolicy policy = new MockUnderwriterPolicy();

        address operator = makeAddr("operator");
        address client = makeAddr("client");

        vm.prank(registry.owner());
        registry.registerPolicy(address(policy));

        vm.prank(cm.owner());
        cm.setEscrow(address(escrow));

        vm.prank(factory.owner());
        factory.addAllowedToken(address(usdc));

        uint256 idx = factory.poolCount();
        vm.prank(operator);
        factory.createPool(address(usdc), address(0), address(0), true);
        address poolAddr = factory.pool(idx);
        RecoursePool pool = RecoursePool(poolAddr);

        vm.prank(operator);
        pool.addPolicy(address(policy));

        usdc.mint(operator, STAKE);
        vm.startPrank(operator);
        usdc.approve(poolAddr, STAKE);
        pool.stake(STAKE);
        vm.stopPrank();

        escrow.setExists(ESCROW_ID, true);
        escrow.setAmount(ESCROW_ID, ESCROW_AMOUNT);

        vm.prank(operator);
        uint256 covId = cm.purchaseCoverage(
            client, poolAddr, address(policy), ESCROW_ID, COVERAGE, block.timestamp + 1 days, "", ""
        );
        assertEq(
            uint256(cm.coverageStatus(covId)),
            uint256(ICoverageManager.CoverageStatus.Active),
            "coverage should be active after purchase"
        );

        uint256 balBefore = usdc.balanceOf(client);

        vm.prank(client);
        cm.dispute(covId, "");

        uint256 balAfter = usdc.balanceOf(client);

        console2.log("=== DEMO PAYOUT ON FORKED ARB SEPOLIA (deployed contracts) ===");
        console2.log("coverageManager owner:", cm.owner());
        console2.log("poolFactory owner    :", factory.owner());
        console2.log("policyRegistry owner :", registry.owner());
        console2.log("pool created at      :", poolAddr);
        console2.log("client USDC before   :", balBefore);
        console2.log("client USDC after    :", balAfter);
        console2.log("payout to client     :", balAfter - balBefore);

        assertEq(balAfter - balBefore, COVERAGE, "client must receive the full recourse payout");
        assertEq(
            uint256(cm.coverageStatus(covId)),
            uint256(ICoverageManager.CoverageStatus.Claimed),
            "coverage should be claimed after payout"
        );
    }
}
