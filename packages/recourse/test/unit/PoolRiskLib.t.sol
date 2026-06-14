// SPDX-License-Identifier: FSL-1.1-ALv2
// Copyright (c) 2026 Reineira Labs Limited All rights reserved.
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {PoolRiskLib} from "@reineira-os/shared/contracts/libraries/PoolRiskLib.sol";

/// @dev External wrapper so `vm.expectRevert` observes the library's reverts as call boundaries.
contract PoolRiskLibHarness {
    function requiredLiquidity(
        uint256 totalAssets,
        uint256 outstandingCoverage,
        uint16 maxDeploymentBps,
        uint16 claimsBufferBps
    ) external pure returns (uint256) {
        return PoolRiskLib.requiredLiquidity(totalAssets, outstandingCoverage, maxDeploymentBps, claimsBufferBps);
    }

    function maxDeployable(
        uint256 totalAssets,
        uint256 currentlyDeployed,
        uint256 outstandingCoverage,
        uint16 maxDeploymentBps,
        uint16 claimsBufferBps
    ) external pure returns (uint256) {
        return
            PoolRiskLib.maxDeployable(
                totalAssets,
                currentlyDeployed,
                outstandingCoverage,
                maxDeploymentBps,
                claimsBufferBps
            );
    }

    function validateDeployment(
        uint256 amount,
        uint256 totalAssets,
        uint256 currentlyDeployed,
        uint256 outstandingCoverage,
        uint16 maxDeploymentBps,
        uint16 claimsBufferBps
    ) external pure {
        PoolRiskLib.validateDeployment(
            amount,
            totalAssets,
            currentlyDeployed,
            outstandingCoverage,
            maxDeploymentBps,
            claimsBufferBps
        );
    }

    function validateMaxDeploymentBps(uint16 bps) external pure {
        PoolRiskLib.validateMaxDeploymentBps(bps);
    }
}

contract PoolRiskLibTest is Test {
    PoolRiskLibHarness internal lib;

    function setUp() public {
        lib = new PoolRiskLibHarness();
    }

    // --- requiredLiquidity ---

    function test_requiredLiquidity_structuralFloorOnly() public view {
        // 30% structural floor at the default ceiling, no coverage.
        assertEq(lib.requiredLiquidity(1000, 0, 7000, 5000), 300);
    }

    function test_requiredLiquidity_addsClaimsBuffer() public view {
        // 30% of 1000 = 300, plus 50% of 400 coverage = 200 => 500.
        assertEq(lib.requiredLiquidity(1000, 400, 7000, 5000), 500);
    }

    function test_requiredLiquidity_roundsUp() public view {
        // 3000/10000 of 1 wei = 0.3, must round UP to 1 (conservative reserve).
        assertEq(lib.requiredLiquidity(1, 0, 7000, 0), 1);
    }

    function test_requiredLiquidity_fullyConservativeBuffer() public view {
        // claimsBufferBps = 100% keeps all outstanding coverage liquid on top of the floor.
        assertEq(lib.requiredLiquidity(1000, 200, 7000, 10000), 300 + 200);
    }

    // --- maxDeployable ---

    function test_maxDeployable_freshPool() public view {
        // 1000 assets, 30% floor, nothing deployed, no coverage => 700 deployable.
        assertEq(lib.maxDeployable(1000, 0, 0, 7000, 0), 700);
    }

    function test_maxDeployable_atLimitReturnsZero() public view {
        assertEq(lib.maxDeployable(1000, 700, 0, 7000, 0), 0);
    }

    function test_maxDeployable_overDeployedClampsToZero() public view {
        assertEq(lib.maxDeployable(1000, 800, 0, 7000, 0), 0);
    }

    function test_maxDeployable_withCoverageBuffer() public view {
        // required = 300 structural + 200 buffer = 500 => 500 deployable.
        assertEq(lib.maxDeployable(1000, 0, 400, 7000, 5000), 500);
    }

    function test_maxDeployable_zeroAssets() public view {
        assertEq(lib.maxDeployable(0, 0, 0, 7000, 5000), 0);
    }

    // --- validateDeployment ---

    function test_validateDeployment_withinLimitPasses() public view {
        lib.validateDeployment(700, 1000, 0, 0, 7000, 0);
    }

    function test_validateDeployment_revertsWhenExceeds() public {
        vm.expectRevert(abi.encodeWithSelector(PoolRiskLib.DeploymentExceedsLimit.selector, 701, 700));
        lib.validateDeployment(701, 1000, 0, 0, 7000, 0);
    }

    // --- validateMaxDeploymentBps ---

    function test_validateMaxDeploymentBps_acceptsAtAndBelowCeiling() public view {
        lib.validateMaxDeploymentBps(0);
        lib.validateMaxDeploymentBps(7000);
    }

    function test_validateMaxDeploymentBps_revertsAboveCeiling() public {
        vm.expectRevert(abi.encodeWithSelector(PoolRiskLib.MaxDeploymentTooHigh.selector, uint16(7001)));
        lib.validateMaxDeploymentBps(7001);
    }

    // --- core safety invariant ---

    /// @dev After deploying the maximum permitted amount, remaining idle must always
    ///      still satisfy the required reserve. This is the property the whole feature rests on.
    function testFuzz_deployingMaxKeepsRequiredLiquidity(
        uint256 totalAssets,
        uint256 outstandingCoverage,
        uint16 maxDeploymentBps,
        uint16 claimsBufferBps
    ) public view {
        totalAssets = bound(totalAssets, 0, 1e30);
        outstandingCoverage = bound(outstandingCoverage, 0, 1e30);
        maxDeploymentBps = uint16(bound(maxDeploymentBps, 0, 7000));
        claimsBufferBps = uint16(bound(claimsBufferBps, 0, 10000));

        uint256 deployable = lib.maxDeployable(totalAssets, 0, outstandingCoverage, maxDeploymentBps, claimsBufferBps);
        uint256 required = lib.requiredLiquidity(totalAssets, outstandingCoverage, maxDeploymentBps, claimsBufferBps);

        assertLe(deployable, totalAssets);
        uint256 idleAfter = totalAssets - deployable;
        if (required <= totalAssets) {
            assertGe(idleAfter, required);
        } else {
            assertEq(deployable, 0);
        }
    }
}
