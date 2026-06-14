// SPDX-License-Identifier: FSL-1.1-ALv2
pragma solidity ^0.8.25;

import {FHETestBase} from "@reineira-os/shared/test/FHETestBase.sol";
import {ICoverageManagerEvents} from "@reineira-os/shared/contracts/interfaces/core/ICoverageManagerEvents.sol";
import {IRecoursePoolEvents} from "@reineira-os/shared/contracts/interfaces/core/IRecoursePoolEvents.sol";
import {CoverageLib} from "@reineira-os/shared/contracts/libraries/CoverageLib.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {IFHERC20} from "fhenix-confidential-contracts/contracts/interfaces/IFHERC20.sol";
import {InEuint64, InEaddress} from "@fhenixprotocol/cofhe-contracts/FHE.sol";
import {ConfidentialPolicyRegistry} from "../../contracts/core/ConfidentialPolicyRegistry.sol";
import {ConfidentialPoolFactory} from "../../contracts/core/ConfidentialPoolFactory.sol";
import {ConfidentialRecoursePool} from "../../contracts/core/ConfidentialRecoursePool.sol";
import {ConfidentialCoverageManager} from "../../contracts/core/ConfidentialCoverageManager.sol";
import {MockConfidentialToken} from "../../contracts/mocks/MockConfidentialToken.sol";
import {MockConfidentialEscrow} from "../../contracts/mocks/MockConfidentialEscrow.sol";
import {MockConfidentialUnderwriterPolicy} from "../../contracts/mocks/MockConfidentialUnderwriterPolicy.sol";
import {CoverageInviteLib} from "@reineira-os/shared/contracts/libraries/CoverageInviteLib.sol";

contract ConfidentialRecourseFlowTest is FHETestBase {
    ConfidentialPoolFactory public poolFactory;
    ConfidentialPolicyRegistry public policyRegistry;
    ConfidentialCoverageManager public coverageManager;
    MockConfidentialToken public token;
    MockConfidentialEscrow public mockEscrow;
    MockConfidentialUnderwriterPolicy public simplePolicy;

    address public owner;
    address public creator;
    address public lp1;
    address public buyer;
    address public extraCreator;

    address public tokenAddress;
    address public simplePolicyAddress;
    address public coverageManagerAddress;

    uint64 constant STAKE_AMOUNT = 50000;
    uint64 constant COVERAGE_AMOUNT = 10000;
    uint64 constant ESCROW_AMOUNT = 20000;
    uint256 constant ESCROW_ID = 42;
    uint256 futureExpiry;

    function setUp() public {
        _initFHE();
        owner = makeAddr("owner");
        creator = makeAddr("creator");
        lp1 = _makeAccount("lp1");
        buyer = _makeAccount("buyer");
        extraCreator = makeAddr("extraCreator");
        futureExpiry = block.timestamp + 86400;

        vm.startPrank(owner);

        token = new MockConfidentialToken();
        tokenAddress = address(token);
        mockEscrow = new MockConfidentialEscrow();
        simplePolicy = new MockConfidentialUnderwriterPolicy();
        simplePolicyAddress = address(simplePolicy);

        ConfidentialPolicyRegistry policyRegistryImpl = new ConfidentialPolicyRegistry(address(0));
        policyRegistry = ConfidentialPolicyRegistry(
            address(
                new ERC1967Proxy(
                    address(policyRegistryImpl),
                    abi.encodeCall(ConfidentialPolicyRegistry.initialize, (owner))
                )
            )
        );
        policyRegistry.registerPolicy(simplePolicyAddress);

        ConfidentialRecoursePool poolImpl = new ConfidentialRecoursePool(address(0));

        ConfidentialCoverageManager coverageManagerImpl = new ConfidentialCoverageManager(address(0));
        coverageManager = ConfidentialCoverageManager(
            address(
                new ERC1967Proxy(
                    address(coverageManagerImpl),
                    abi.encodeCall(ConfidentialCoverageManager.initialize, (owner, owner))
                )
            )
        );
        coverageManagerAddress = address(coverageManager);
        coverageManager.setEscrow(address(mockEscrow));

        ConfidentialPoolFactory factoryImpl = new ConfidentialPoolFactory(address(0));
        poolFactory = ConfidentialPoolFactory(
            address(
                new ERC1967Proxy(
                    address(factoryImpl),
                    abi.encodeCall(
                        ConfidentialPoolFactory.initialize,
                        (owner, address(poolImpl), coverageManagerAddress, address(policyRegistry))
                    )
                )
            )
        );
        coverageManager.setPoolFactory(address(poolFactory));
        poolFactory.addAllowedToken(tokenAddress);

        vm.stopPrank();
    }

    function test_fullLifecycle_createPoolStakePurchaseCoverageDispute() public {
        vm.prank(creator);
        poolFactory.createPool(IFHERC20(tokenAddress), address(0), address(0), true);
        address poolAddress = poolFactory.pool(0);
        ConfidentialRecoursePool pool = ConfidentialRecoursePool(poolAddress);

        assertEq(pool.creator(), creator);
        assertEq(pool.manager(), creator);
        assertTrue(pool.isOpen());
        assertTrue(poolFactory.isPool(poolAddress));

        vm.prank(creator);
        pool.addPolicy(simplePolicyAddress);
        assertTrue(pool.isPolicy(simplePolicyAddress));

        vm.prank(owner);
        token.mintPlain(lp1, STAKE_AMOUNT);
        vm.prank(lp1);
        token.setOperator(poolAddress, uint48(block.timestamp + 86400));

        InEuint64 memory encStake = createInEuint64(STAKE_AMOUNT, lp1);
        vm.prank(lp1);
        vm.expectEmit(true, false, false, false);
        emit IRecoursePoolEvents.Staked(0);
        pool.stake(encStake);

        mockEscrow.setExists(ESCROW_ID, true);
        mockEscrow.setAmount(ESCROW_ID, ESCROW_AMOUNT, coverageManagerAddress);

        InEaddress memory encHolder = createInEaddress(buyer, buyer);
        InEuint64 memory encCoverage = createInEuint64(COVERAGE_AMOUNT, buyer);

        vm.prank(buyer);
        vm.expectEmit(true, false, false, false);
        emit ICoverageManagerEvents.CoveragePurchased(0);
        coverageManager.purchaseCoverage(
            encHolder,
            poolAddress,
            simplePolicyAddress,
            ESCROW_ID,
            encCoverage,
            futureExpiry,
            "",
            ""
        );

        assertEq(uint256(coverageManager.coverageStatus(0)), 1);

        assertTrue(mockEscrow.feeSet(ESCROW_ID));
        assertEq(mockEscrow.getFeeRecipient(ESCROW_ID), poolAddress);

        vm.prank(owner);
        token.mintPlain(coverageManagerAddress, COVERAGE_AMOUNT);

        vm.prank(buyer);
        vm.expectEmit(true, false, false, false);
        emit ICoverageManagerEvents.DisputeFiled(0);
        coverageManager.dispute(0, "");

        assertEq(uint256(coverageManager.coverageStatus(0)), 3);
    }

    function test_multiplePools_allowsMultiplePoolsWithDifferentCreators() public {
        vm.prank(creator);
        poolFactory.createPool(IFHERC20(tokenAddress), address(0), address(0), true);
        vm.prank(extraCreator);
        poolFactory.createPool(IFHERC20(tokenAddress), address(0), address(0), true);

        assertEq(poolFactory.poolCount(), 2);

        ConfidentialRecoursePool pool1 = ConfidentialRecoursePool(poolFactory.pool(0));
        ConfidentialRecoursePool pool2 = ConfidentialRecoursePool(poolFactory.pool(1));

        assertEq(pool1.creator(), creator);
        assertEq(pool2.creator(), extraCreator);
    }

    function test_maxCoverages_revertsWhenLimitReached() public {
        vm.prank(creator);
        poolFactory.createPool(IFHERC20(tokenAddress), address(0), address(0), true);
        address poolAddress = poolFactory.pool(0);
        ConfidentialRecoursePool pool = ConfidentialRecoursePool(poolAddress);
        vm.prank(creator);
        pool.addPolicy(simplePolicyAddress);

        vm.prank(owner);
        token.mintPlain(lp1, STAKE_AMOUNT);
        vm.prank(lp1);
        token.setOperator(poolAddress, uint48(block.timestamp + 86400));

        InEuint64 memory encStake = createInEuint64(STAKE_AMOUNT, lp1);
        vm.prank(lp1);
        pool.stake(encStake);

        mockEscrow.setExists(ESCROW_ID, true);
        mockEscrow.setAmount(ESCROW_ID, ESCROW_AMOUNT, coverageManagerAddress);

        for (uint256 i = 0; i < coverageManager.MAX_COVERAGES_PER_ESCROW(); i++) {
            InEaddress memory encHolder = createInEaddress(buyer, buyer);
            InEuint64 memory encCoverage = createInEuint64(COVERAGE_AMOUNT / 10, buyer);

            vm.prank(buyer);
            coverageManager.purchaseCoverage(
                encHolder,
                poolAddress,
                simplePolicyAddress,
                ESCROW_ID,
                encCoverage,
                futureExpiry,
                "",
                ""
            );
        }

        InEaddress memory encHolderExtra = createInEaddress(buyer, buyer);
        InEuint64 memory encCoverageExtra = createInEuint64(COVERAGE_AMOUNT / 10, buyer);

        vm.prank(buyer);
        vm.expectRevert(CoverageLib.MaxCoveragesReached.selector);
        coverageManager.purchaseCoverage(
            encHolderExtra,
            poolAddress,
            simplePolicyAddress,
            ESCROW_ID,
            encCoverageExtra,
            futureExpiry,
            "",
            ""
        );
    }

    function test_multiCoverage_allowsMultipleCoveragesPerEscrow() public {
        vm.prank(creator);
        poolFactory.createPool(IFHERC20(tokenAddress), address(0), address(0), true);
        address poolAddress = poolFactory.pool(0);
        ConfidentialRecoursePool pool = ConfidentialRecoursePool(poolAddress);
        vm.prank(creator);
        pool.addPolicy(simplePolicyAddress);

        vm.prank(owner);
        token.mintPlain(lp1, STAKE_AMOUNT);
        vm.prank(lp1);
        token.setOperator(poolAddress, uint48(block.timestamp + 86400));

        InEuint64 memory encStake = createInEuint64(STAKE_AMOUNT, lp1);
        vm.prank(lp1);
        pool.stake(encStake);

        mockEscrow.setExists(ESCROW_ID, true);
        mockEscrow.setAmount(ESCROW_ID, ESCROW_AMOUNT, coverageManagerAddress);

        InEaddress memory encHolder1 = createInEaddress(buyer, buyer);
        InEuint64 memory encCoverage1 = createInEuint64(COVERAGE_AMOUNT, buyer);

        vm.prank(buyer);
        coverageManager.purchaseCoverage(
            encHolder1,
            poolAddress,
            simplePolicyAddress,
            ESCROW_ID,
            encCoverage1,
            futureExpiry,
            "",
            ""
        );

        InEaddress memory encHolder2 = createInEaddress(buyer, buyer);
        InEuint64 memory encCoverage2 = createInEuint64(COVERAGE_AMOUNT, buyer);

        vm.prank(buyer);
        coverageManager.purchaseCoverage(
            encHolder2,
            poolAddress,
            simplePolicyAddress,
            ESCROW_ID,
            encCoverage2,
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
        (, address poolAddr) = poolFactory.createPool(IFHERC20(tokenAddress), managerA, guardianAddr, false);
        ConfidentialRecoursePool closedPool = ConfidentialRecoursePool(poolAddr);

        assertEq(closedPool.creator(), creator);
        assertEq(closedPool.manager(), managerA);
        assertEq(closedPool.guardian(), guardianAddr);
        assertFalse(closedPool.isOpen());

        vm.prank(creator);
        closedPool.addPolicy(simplePolicyAddress);

        vm.prank(owner);
        token.mintPlain(lp1, STAKE_AMOUNT);
        vm.prank(lp1);
        token.setOperator(poolAddr, uint48(block.timestamp + 86400));
        InEuint64 memory encStake = createInEuint64(STAKE_AMOUNT, lp1);
        vm.prank(lp1);
        closedPool.stake(encStake);

        mockEscrow.setExists(ESCROW_ID, true);
        mockEscrow.setAmount(ESCROW_ID, ESCROW_AMOUNT, coverageManagerAddress);

        CoverageInviteLib.CoverageInvite memory inviteA = CoverageInviteLib.CoverageInvite({
            pool: poolAddr,
            invitee: buyer,
            maxUses: 2,
            deadline: block.timestamp + 1 days,
            inviteId: 1
        });
        bytes memory sigA = _sign(managerAKey, closedPool, inviteA);
        bytes32 digestA = CoverageInviteLib.digest(closedPool.domainSeparator(), inviteA);

        InEaddress memory encHolderA = createInEaddress(buyer, buyer);
        InEuint64 memory encCovA = createInEuint64(COVERAGE_AMOUNT, buyer);

        vm.prank(buyer);
        coverageManager.purchaseCoverage(
            encHolderA,
            poolAddr,
            simplePolicyAddress,
            ESCROW_ID,
            encCovA,
            futureExpiry,
            "",
            "",
            inviteA,
            sigA
        );
        assertEq(coverageManager.usedCount(digestA), 1);
        assertEq(uint256(coverageManager.coverageStatus(0)), 1);

        vm.prank(managerA);
        closedPool.transferManager(managerB);
        assertEq(closedPool.manager(), managerB);

        mockEscrow.setExists(ESCROW_ID + 1, true);
        mockEscrow.setAmount(ESCROW_ID + 1, ESCROW_AMOUNT, coverageManagerAddress);

        InEaddress memory encHolderRetry = createInEaddress(buyer, buyer);
        InEuint64 memory encCovRetry = createInEuint64(COVERAGE_AMOUNT, buyer);

        vm.prank(buyer);
        vm.expectRevert(CoverageLib.InviteSignerMismatch.selector);
        coverageManager.purchaseCoverage(
            encHolderRetry,
            poolAddr,
            simplePolicyAddress,
            ESCROW_ID + 1,
            encCovRetry,
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

        InEaddress memory encHolderB = createInEaddress(buyer, buyer);
        InEuint64 memory encCovB = createInEuint64(COVERAGE_AMOUNT, buyer);

        vm.prank(buyer);
        coverageManager.purchaseCoverage(
            encHolderB,
            poolAddr,
            simplePolicyAddress,
            ESCROW_ID + 1,
            encCovB,
            futureExpiry,
            "",
            "",
            inviteB,
            sigB
        );
        assertEq(uint256(coverageManager.coverageStatus(1)), 1);
    }

    function _sign(
        uint256 key,
        ConfidentialRecoursePool pool_,
        CoverageInviteLib.CoverageInvite memory invite
    ) internal view returns (bytes memory) {
        bytes32 ds = pool_.domainSeparator();
        bytes32 d = CoverageInviteLib.digest(ds, invite);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(key, d);
        return abi.encodePacked(r, s, v);
    }
}
