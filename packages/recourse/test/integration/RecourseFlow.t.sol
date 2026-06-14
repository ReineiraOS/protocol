// SPDX-License-Identifier: FSL-1.1-ALv2
pragma solidity ^0.8.25;

import {Test} from "forge-std/Test.sol";
import {ICoverageManagerEvents} from "@reineira-os/shared/contracts/interfaces/core/ICoverageManagerEvents.sol";
import {IRecoursePoolEvents} from "@reineira-os/shared/contracts/interfaces/core/IRecoursePoolEvents.sol";
import {CoverageLib} from "@reineira-os/shared/contracts/libraries/CoverageLib.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {PolicyRegistry} from "../../contracts/core/PolicyRegistry.sol";
import {PoolFactory} from "../../contracts/core/PoolFactory.sol";
import {RecoursePool} from "../../contracts/core/RecoursePool.sol";
import {CoverageManager} from "../../contracts/core/CoverageManager.sol";
import {ICoverageManager} from "../../contracts/interfaces/core/ICoverageManager.sol";
import {MockUSDC} from "@reineira-os/shared/contracts/mocks/MockUSDC.sol";
import {MockEscrow} from "../../contracts/mocks/MockEscrow.sol";
import {MockUnderwriterPolicy} from "../../contracts/mocks/MockUnderwriterPolicy.sol";
import {CoverageInviteLib} from "@reineira-os/shared/contracts/libraries/CoverageInviteLib.sol";

contract RecourseFlowTest is Test {
    PoolFactory public poolFactory;
    PolicyRegistry public policyRegistry;
    CoverageManager public coverageManager;
    MockUSDC public usdc;
    MockEscrow public mockEscrow;
    MockUnderwriterPolicy public simplePolicy;

    address public owner;
    address public creator;
    address public lp1;
    address public buyer;
    address public extraCreator;

    address public simplePolicyAddress;
    address public coverageManagerAddress;

    uint256 constant STAKE_AMOUNT = 50_000e6;
    uint256 constant COVERAGE_AMOUNT = 10_000e6;
    uint256 constant ESCROW_AMOUNT = 20_000e6;
    uint256 constant ESCROW_ID = 42;
    uint256 futureExpiry;

    function setUp() public {
        owner = makeAddr("owner");
        creator = makeAddr("creator");
        lp1 = makeAddr("lp1");
        buyer = makeAddr("buyer");
        extraCreator = makeAddr("extraCreator");
        futureExpiry = block.timestamp + 86400;

        vm.startPrank(owner);

        usdc = new MockUSDC();
        mockEscrow = new MockEscrow();
        simplePolicy = new MockUnderwriterPolicy();
        simplePolicyAddress = address(simplePolicy);

        PolicyRegistry policyRegistryImpl = new PolicyRegistry(address(0));
        policyRegistry = PolicyRegistry(
            address(new ERC1967Proxy(address(policyRegistryImpl), abi.encodeCall(PolicyRegistry.initialize, (owner))))
        );
        policyRegistry.registerPolicy(simplePolicyAddress);

        RecoursePool poolImpl = new RecoursePool(address(0));

        CoverageManager coverageManagerImpl = new CoverageManager(address(0));
        coverageManager = CoverageManager(
            address(
                new ERC1967Proxy(
                    address(coverageManagerImpl),
                    abi.encodeCall(CoverageManager.initialize, (owner, owner))
                )
            )
        );
        coverageManagerAddress = address(coverageManager);
        coverageManager.setEscrow(address(mockEscrow));

        PoolFactory factoryImpl = new PoolFactory(address(0));
        poolFactory = PoolFactory(
            address(
                new ERC1967Proxy(
                    address(factoryImpl),
                    abi.encodeCall(
                        PoolFactory.initialize,
                        (owner, address(poolImpl), coverageManagerAddress, address(policyRegistry))
                    )
                )
            )
        );
        coverageManager.setPoolFactory(address(poolFactory));
        poolFactory.addAllowedToken(address(usdc));

        vm.stopPrank();
    }

    function test_fullLifecycle_createPoolStakePurchaseCoverageDispute() public {
        vm.prank(creator);
        poolFactory.createPool(address(usdc), address(0), address(0), true);
        address poolAddress = poolFactory.pool(0);
        RecoursePool pool = RecoursePool(poolAddress);

        assertEq(pool.creator(), creator);
        assertEq(pool.manager(), creator);
        assertTrue(pool.isOpen());
        assertTrue(poolFactory.isPool(poolAddress));

        vm.prank(creator);
        pool.addPolicy(simplePolicyAddress);
        assertTrue(pool.isPolicy(simplePolicyAddress));

        usdc.mint(lp1, STAKE_AMOUNT);
        vm.prank(lp1);
        usdc.approve(poolAddress, STAKE_AMOUNT);

        vm.prank(lp1);
        vm.expectEmit(true, false, false, false);
        emit IRecoursePoolEvents.Staked(0);
        pool.stake(STAKE_AMOUNT);

        assertEq(pool.totalLiquidity(), STAKE_AMOUNT);

        mockEscrow.setExists(ESCROW_ID, true);
        mockEscrow.setAmount(ESCROW_ID, ESCROW_AMOUNT);

        vm.prank(buyer);
        vm.expectEmit(true, false, false, false);
        emit ICoverageManagerEvents.CoveragePurchased(0);
        coverageManager.purchaseCoverage(
            buyer,
            poolAddress,
            simplePolicyAddress,
            ESCROW_ID,
            COVERAGE_AMOUNT,
            futureExpiry,
            "",
            ""
        );

        assertEq(uint256(coverageManager.coverageStatus(0)), uint256(ICoverageManager.CoverageStatus.Active));

        assertTrue(mockEscrow.feeSet(ESCROW_ID));
        assertEq(mockEscrow.getFeeRecipient(ESCROW_ID), poolAddress);

        vm.prank(buyer);
        vm.expectEmit(true, false, false, false);
        emit ICoverageManagerEvents.DisputeFiled(0);
        coverageManager.dispute(0, "");

        assertEq(uint256(coverageManager.coverageStatus(0)), uint256(ICoverageManager.CoverageStatus.Claimed));

        assertEq(usdc.balanceOf(buyer), COVERAGE_AMOUNT);
    }

    function test_multiplePools_allowsMultiplePoolsWithDifferentCreators() public {
        vm.prank(creator);
        poolFactory.createPool(address(usdc), address(0), address(0), true);
        vm.prank(extraCreator);
        poolFactory.createPool(address(usdc), address(0), address(0), true);

        assertEq(poolFactory.poolCount(), 2);

        RecoursePool pool1 = RecoursePool(poolFactory.pool(0));
        RecoursePool pool2 = RecoursePool(poolFactory.pool(1));

        assertEq(pool1.creator(), creator);
        assertEq(pool2.creator(), extraCreator);
    }

    function test_maxCoverages_revertsWhenLimitReached() public {
        vm.prank(creator);
        poolFactory.createPool(address(usdc), address(0), address(0), true);
        address poolAddress = poolFactory.pool(0);
        RecoursePool pool = RecoursePool(poolAddress);
        vm.prank(creator);
        pool.addPolicy(simplePolicyAddress);

        usdc.mint(lp1, STAKE_AMOUNT);
        vm.prank(lp1);
        usdc.approve(poolAddress, STAKE_AMOUNT);
        vm.prank(lp1);
        pool.stake(STAKE_AMOUNT);

        mockEscrow.setExists(ESCROW_ID, true);
        mockEscrow.setAmount(ESCROW_ID, ESCROW_AMOUNT);

        for (uint256 i = 0; i < coverageManager.MAX_COVERAGES_PER_ESCROW(); i++) {
            vm.prank(buyer);
            coverageManager.purchaseCoverage(
                buyer,
                poolAddress,
                simplePolicyAddress,
                ESCROW_ID,
                COVERAGE_AMOUNT / 10,
                futureExpiry,
                "",
                ""
            );
        }

        vm.prank(buyer);
        vm.expectRevert(CoverageLib.MaxCoveragesReached.selector);
        coverageManager.purchaseCoverage(
            buyer,
            poolAddress,
            simplePolicyAddress,
            ESCROW_ID,
            COVERAGE_AMOUNT / 10,
            futureExpiry,
            "",
            ""
        );
    }

    function test_multiCoverage_allowsMultipleCoveragesPerEscrow() public {
        vm.prank(creator);
        poolFactory.createPool(address(usdc), address(0), address(0), true);
        address poolAddress = poolFactory.pool(0);
        RecoursePool pool = RecoursePool(poolAddress);
        vm.prank(creator);
        pool.addPolicy(simplePolicyAddress);

        usdc.mint(lp1, STAKE_AMOUNT);
        vm.prank(lp1);
        usdc.approve(poolAddress, STAKE_AMOUNT);
        vm.prank(lp1);
        pool.stake(STAKE_AMOUNT);

        mockEscrow.setExists(ESCROW_ID, true);
        mockEscrow.setAmount(ESCROW_ID, ESCROW_AMOUNT);

        vm.prank(buyer);
        coverageManager.purchaseCoverage(
            buyer,
            poolAddress,
            simplePolicyAddress,
            ESCROW_ID,
            COVERAGE_AMOUNT,
            futureExpiry,
            "",
            ""
        );

        vm.prank(buyer);
        coverageManager.purchaseCoverage(
            buyer,
            poolAddress,
            simplePolicyAddress,
            ESCROW_ID,
            COVERAGE_AMOUNT,
            futureExpiry,
            "",
            ""
        );

        uint256[] memory coverages = coverageManager.getCoveragesForEscrow(ESCROW_ID);
        assertEq(coverages.length, 2);
        assertEq(coverages[0], 0);
        assertEq(coverages[1], 1);
        assertEq(uint256(coverageManager.coverageStatus(0)), 1);
        assertEq(uint256(coverageManager.coverageStatus(1)), 1);
    }

    function test_closedPoolEndToEnd_managerRotationInvalidatesOldInvite() public {
        (address managerA, uint256 managerAKey) = makeAddrAndKey("managerA");
        (address managerB, uint256 managerBKey) = makeAddrAndKey("managerB");
        address guardianAddr = makeAddr("guardian");

        vm.prank(creator);
        (, address poolAddr) = poolFactory.createPool(address(usdc), managerA, guardianAddr, false);
        RecoursePool closedPool = RecoursePool(poolAddr);

        assertEq(closedPool.creator(), creator);
        assertEq(closedPool.manager(), managerA);
        assertEq(closedPool.guardian(), guardianAddr);
        assertFalse(closedPool.isOpen());

        vm.prank(creator);
        closedPool.addPolicy(simplePolicyAddress);

        usdc.mint(lp1, STAKE_AMOUNT);
        vm.prank(lp1);
        usdc.approve(poolAddr, STAKE_AMOUNT);
        vm.prank(lp1);
        closedPool.stake(STAKE_AMOUNT);
        assertEq(closedPool.totalLiquidity(), STAKE_AMOUNT);

        CoverageInviteLib.CoverageInvite memory inviteA = CoverageInviteLib.CoverageInvite({
            pool: poolAddr,
            invitee: buyer,
            maxUses: 2,
            deadline: block.timestamp + 1 days,
            inviteId: 1
        });
        bytes memory sigA = _sign(managerAKey, closedPool, inviteA);
        bytes32 digestA = CoverageInviteLib.digest(closedPool.domainSeparator(), inviteA);

        mockEscrow.setExists(ESCROW_ID, true);
        mockEscrow.setAmount(ESCROW_ID, ESCROW_AMOUNT);

        vm.prank(buyer);
        coverageManager.purchaseCoverage(
            buyer,
            poolAddr,
            simplePolicyAddress,
            ESCROW_ID,
            COVERAGE_AMOUNT,
            futureExpiry,
            "",
            "",
            inviteA,
            sigA
        );
        assertEq(coverageManager.usedCount(digestA), 1);
        assertEq(uint256(coverageManager.coverageStatus(0)), uint256(ICoverageManager.CoverageStatus.Active));

        vm.prank(managerA);
        closedPool.transferManager(managerB);
        assertEq(closedPool.manager(), managerB);

        mockEscrow.setExists(ESCROW_ID + 1, true);
        mockEscrow.setAmount(ESCROW_ID + 1, ESCROW_AMOUNT);
        vm.prank(buyer);
        vm.expectRevert(CoverageLib.InviteSignerMismatch.selector);
        coverageManager.purchaseCoverage(
            buyer,
            poolAddr,
            simplePolicyAddress,
            ESCROW_ID + 1,
            COVERAGE_AMOUNT,
            futureExpiry,
            "",
            "",
            inviteA,
            sigA
        );

        CoverageInviteLib.CoverageInvite memory inviteB = CoverageInviteLib.CoverageInvite({
            pool: poolAddr,
            invitee: buyer,
            maxUses: 1,
            deadline: block.timestamp + 1 days,
            inviteId: 2
        });
        bytes memory sigB = _sign(managerBKey, closedPool, inviteB);

        vm.prank(buyer);
        coverageManager.purchaseCoverage(
            buyer,
            poolAddr,
            simplePolicyAddress,
            ESCROW_ID + 1,
            COVERAGE_AMOUNT,
            futureExpiry,
            "",
            "",
            inviteB,
            sigB
        );
        assertEq(uint256(coverageManager.coverageStatus(1)), uint256(ICoverageManager.CoverageStatus.Active));

        vm.prank(buyer);
        coverageManager.dispute(1, "");
        assertEq(uint256(coverageManager.coverageStatus(1)), uint256(ICoverageManager.CoverageStatus.Claimed));
        assertEq(usdc.balanceOf(buyer), COVERAGE_AMOUNT);
    }

    function _sign(
        uint256 key,
        RecoursePool pool_,
        CoverageInviteLib.CoverageInvite memory invite
    ) internal view returns (bytes memory) {
        bytes32 ds = pool_.domainSeparator();
        bytes32 d = CoverageInviteLib.digest(ds, invite);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(key, d);
        return abi.encodePacked(r, s, v);
    }
}
