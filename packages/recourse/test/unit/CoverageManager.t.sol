// SPDX-License-Identifier: FSL-1.1-ALv2
pragma solidity ^0.8.25;

import {Test} from "forge-std/Test.sol";
import {ICoverageManagerEvents} from "@reineira-os/shared/contracts/interfaces/core/ICoverageManagerEvents.sol";
import {CoverageLib} from "@reineira-os/shared/contracts/libraries/CoverageLib.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {PolicyRegistry} from "../../contracts/core/PolicyRegistry.sol";
import {PoolFactory} from "../../contracts/core/PoolFactory.sol";
import {RecoursePool} from "../../contracts/core/RecoursePool.sol";
import {CoverageManager} from "../../contracts/core/CoverageManager.sol";
import {MockEscrow} from "../../contracts/mocks/MockEscrow.sol";
import {MockUnderwriterPolicy} from "../../contracts/mocks/MockUnderwriterPolicy.sol";
import {MockUSDC} from "@reineira-os/shared/contracts/mocks/MockUSDC.sol";
import {CoverageInviteLib} from "@reineira-os/shared/contracts/libraries/CoverageInviteLib.sol";

contract CoverageManagerTest is Test {
    PoolFactory public poolFactory;
    PolicyRegistry public policyRegistry;
    CoverageManager public coverageManager;
    MockUSDC public usdc;
    MockEscrow public mockEscrow;
    MockUnderwriterPolicy public mockPolicy;
    RecoursePool public pool;

    address public owner;
    address public creator;
    address public lp1;
    address public buyer;
    address public attacker;
    address public poolAddress;
    address public mockPolicyAddress;
    address public coverageManagerAddress;
    address public mockEscrowAddress;
    address public poolFactoryAddress;

    uint256 constant STAKE_AMOUNT = 10_000e6;
    uint256 constant COVERAGE_AMOUNT = 5_000e6;
    uint256 constant ESCROW_AMOUNT = 10_000e6;
    uint256 constant ESCROW_ID = 0;
    uint256 futureExpiry;

    function setUp() public {
        owner = makeAddr("owner");
        creator = makeAddr("creator");
        lp1 = makeAddr("lp1");
        buyer = makeAddr("buyer");
        attacker = makeAddr("attacker");
        futureExpiry = block.timestamp + 86400;

        vm.startPrank(owner);

        usdc = new MockUSDC();
        mockEscrow = new MockEscrow();
        mockEscrowAddress = address(mockEscrow);
        mockPolicy = new MockUnderwriterPolicy();
        mockPolicyAddress = address(mockPolicy);

        PolicyRegistry policyRegistryImpl = new PolicyRegistry(address(0));
        policyRegistry = PolicyRegistry(
            address(new ERC1967Proxy(address(policyRegistryImpl), abi.encodeCall(PolicyRegistry.initialize, (owner))))
        );
        policyRegistry.registerPolicy(mockPolicyAddress);

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
        coverageManager.setEscrow(mockEscrowAddress);

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
        poolFactoryAddress = address(poolFactory);
        coverageManager.setPoolFactory(poolFactoryAddress);
        poolFactory.addAllowedToken(address(usdc));

        vm.stopPrank();

        vm.prank(creator);
        poolFactory.createPool(address(usdc), address(0), address(0), true);
        poolAddress = poolFactory.pool(0);
        pool = RecoursePool(poolAddress);

        vm.prank(creator);
        pool.addPolicy(mockPolicyAddress);

        usdc.mint(lp1, STAKE_AMOUNT);
        vm.prank(lp1);
        usdc.approve(poolAddress, STAKE_AMOUNT);
        vm.prank(lp1);
        pool.stake(STAKE_AMOUNT);
    }

    function _purchaseCoverage() internal {
        mockEscrow.setExists(ESCROW_ID, true);
        mockEscrow.setAmount(ESCROW_ID, ESCROW_AMOUNT);

        vm.prank(buyer);
        coverageManager.purchaseCoverage(
            buyer,
            poolAddress,
            mockPolicyAddress,
            ESCROW_ID,
            COVERAGE_AMOUNT,
            futureExpiry,
            "",
            ""
        );
    }

    function _setupEscrow(uint256 escrowId) internal {
        mockEscrow.setExists(escrowId, true);
        mockEscrow.setAmount(escrowId, ESCROW_AMOUNT);
    }

    function _deployClosedPool(address managerSigner) internal returns (RecoursePool closedPool) {
        vm.prank(creator);
        (, address poolAddr) = poolFactory.createPool(address(usdc), managerSigner, address(0), false);
        closedPool = RecoursePool(poolAddr);

        vm.prank(creator);
        closedPool.addPolicy(mockPolicyAddress);

        usdc.mint(lp1, STAKE_AMOUNT);
        vm.prank(lp1);
        usdc.approve(address(closedPool), STAKE_AMOUNT);
        vm.prank(lp1);
        closedPool.stake(STAKE_AMOUNT);
    }

    function _signInvite(
        uint256 key,
        RecoursePool pool_,
        CoverageInviteLib.CoverageInvite memory invite
    ) internal view returns (bytes memory) {
        bytes32 ds = pool_.domainSeparator();
        bytes32 d = CoverageInviteLib.digest(ds, invite);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(key, d);
        return abi.encodePacked(r, s, v);
    }

    function test_viewFunctions_returnsEscrowAddress() public view {
        assertEq(coverageManager.escrow(), mockEscrowAddress);
    }

    function test_viewFunctions_returnsPoolFactoryAddress() public view {
        assertEq(coverageManager.poolFactory(), poolFactoryAddress);
    }

    function test_viewFunctions_returnsNoneStatusForNonexistentCoverage() public view {
        assertEq(uint256(coverageManager.coverageStatus(999)), 0);
    }

    function test_purchaseCoverage_purchasesCoverageSuccessfully() public {
        mockEscrow.setExists(ESCROW_ID, true);
        mockEscrow.setAmount(ESCROW_ID, ESCROW_AMOUNT);

        vm.prank(buyer);
        vm.expectEmit(true, false, false, false);
        emit ICoverageManagerEvents.CoveragePurchased(0);
        coverageManager.purchaseCoverage(
            buyer,
            poolAddress,
            mockPolicyAddress,
            ESCROW_ID,
            COVERAGE_AMOUNT,
            futureExpiry,
            "",
            ""
        );
    }

    function test_purchaseCoverage_setsCoverageStatusToActive() public {
        _purchaseCoverage();
        assertEq(uint256(coverageManager.coverageStatus(0)), 1);
    }

    function test_purchaseCoverage_callsSetFeeOnEscrow() public {
        _purchaseCoverage();
        assertTrue(mockEscrow.feeSet(ESCROW_ID));
        assertEq(mockEscrow.getFeeRecipient(ESCROW_ID), poolAddress);
    }

    function test_purchaseCoverage_revertsForInvalidPool() public {
        vm.prank(buyer);
        vm.expectRevert(CoverageLib.InvalidPool.selector);
        coverageManager.purchaseCoverage(
            buyer,
            attacker,
            mockPolicyAddress,
            ESCROW_ID,
            COVERAGE_AMOUNT,
            futureExpiry,
            "",
            ""
        );
    }

    function test_purchaseCoverage_revertsForPolicyNotAllowedOnPool() public {
        MockUnderwriterPolicy otherPolicy = new MockUnderwriterPolicy();

        vm.prank(buyer);
        vm.expectRevert(CoverageLib.InvalidPolicy.selector);
        coverageManager.purchaseCoverage(
            buyer,
            poolAddress,
            address(otherPolicy),
            ESCROW_ID,
            COVERAGE_AMOUNT,
            futureExpiry,
            "",
            ""
        );
    }

    function test_purchaseCoverage_revertsForPastExpiry() public {
        mockEscrow.setExists(ESCROW_ID, true);
        mockEscrow.setAmount(ESCROW_ID, ESCROW_AMOUNT);

        vm.prank(buyer);
        vm.expectRevert(CoverageLib.InvalidExpiry.selector);
        coverageManager.purchaseCoverage(buyer, poolAddress, mockPolicyAddress, ESCROW_ID, COVERAGE_AMOUNT, 1, "", "");
    }

    function test_purchaseCoverage_allowsMultipleCoveragesPerEscrow() public {
        _purchaseCoverage();

        vm.prank(buyer);
        uint256 coverageId2 = coverageManager.purchaseCoverage(
            buyer,
            poolAddress,
            mockPolicyAddress,
            ESCROW_ID,
            COVERAGE_AMOUNT,
            futureExpiry,
            "",
            ""
        );

        uint256[] memory coverages = coverageManager.getCoveragesForEscrow(ESCROW_ID);
        assertEq(coverages.length, 2);
        assertEq(coverages[0], 0);
        assertEq(coverages[1], coverageId2);
    }

    function test_purchaseCoverage_revertsWhenMaxCoveragesReached() public {
        mockEscrow.setExists(ESCROW_ID, true);
        mockEscrow.setAmount(ESCROW_ID, ESCROW_AMOUNT);

        for (uint256 i = 0; i < coverageManager.MAX_COVERAGES_PER_ESCROW(); i++) {
            vm.prank(buyer);
            coverageManager.purchaseCoverage(
                buyer,
                poolAddress,
                mockPolicyAddress,
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
            mockPolicyAddress,
            ESCROW_ID,
            COVERAGE_AMOUNT / 10,
            futureExpiry,
            "",
            ""
        );
    }

    function test_purchaseCoverage_revertsForNonExistentEscrow() public {
        vm.prank(buyer);
        vm.expectRevert(CoverageLib.EscrowDoesNotExist.selector);
        coverageManager.purchaseCoverage(
            buyer,
            poolAddress,
            mockPolicyAddress,
            999,
            COVERAGE_AMOUNT,
            futureExpiry,
            "",
            ""
        );
    }

    function test_purchaseCoverage_revertsForZeroHolder() public {
        mockEscrow.setExists(ESCROW_ID, true);
        mockEscrow.setAmount(ESCROW_ID, ESCROW_AMOUNT);

        vm.prank(buyer);
        vm.expectRevert();
        coverageManager.purchaseCoverage(
            address(0),
            poolAddress,
            mockPolicyAddress,
            ESCROW_ID,
            COVERAGE_AMOUNT,
            futureExpiry,
            "",
            ""
        );
    }

    function test_dispute_emitsDisputeFiledAndCoverageClaimedEvents() public {
        _purchaseCoverage();

        vm.prank(buyer);
        vm.expectEmit(true, false, false, false);
        emit ICoverageManagerEvents.DisputeFiled(0);
        vm.expectEmit(true, false, false, false);
        emit ICoverageManagerEvents.CoverageClaimed(0);
        coverageManager.dispute(0, "");
    }

    function test_dispute_setsStatusToClaimedAfterDispute() public {
        _purchaseCoverage();

        vm.prank(buyer);
        coverageManager.dispute(0, "");

        assertEq(uint256(coverageManager.coverageStatus(0)), 3);
    }

    function test_dispute_paysOutToHolderAddress() public {
        _purchaseCoverage();

        uint256 buyerBalanceBefore = usdc.balanceOf(buyer);

        vm.prank(buyer);
        coverageManager.dispute(0, "");

        assertEq(usdc.balanceOf(buyer), buyerBalanceBefore + COVERAGE_AMOUNT);
        assertEq(uint256(coverageManager.coverageStatus(0)), 3);
    }

    function test_dispute_revertsForNonexistentCoverage() public {
        _purchaseCoverage();

        vm.prank(buyer);
        vm.expectRevert(CoverageLib.CoverageDoesNotExist.selector);
        coverageManager.dispute(999, "");
    }

    function test_dispute_revertsIfAlreadyClaimed() public {
        _purchaseCoverage();

        vm.prank(buyer);
        coverageManager.dispute(0, "");

        vm.prank(buyer);
        vm.expectRevert(CoverageLib.NotActiveStatus.selector);
        coverageManager.dispute(0, "");
    }

    function test_dispute_revertsWhenNonHolderCallsDispute() public {
        _purchaseCoverage();

        vm.prank(attacker);
        vm.expectRevert(CoverageLib.NotCoverageHolder.selector);
        coverageManager.dispute(0, "");
    }

    function test_dispute_revertsOnRejectedJudge() public {
        _purchaseCoverage();

        mockPolicy.setJudgeResult(false);

        vm.prank(buyer);
        vm.expectRevert(CoverageLib.DisputeRejected.selector);
        coverageManager.dispute(0, "");
    }

    function test_voucher_openPoolIgnoresInvite() public {
        _setupEscrow(ESCROW_ID);

        CoverageInviteLib.CoverageInvite memory invite;

        vm.prank(buyer);
        coverageManager.purchaseCoverage(
            buyer,
            poolAddress,
            mockPolicyAddress,
            ESCROW_ID,
            COVERAGE_AMOUNT,
            futureExpiry,
            "",
            "",
            invite,
            ""
        );

        assertEq(uint256(coverageManager.coverageStatus(0)), 1);
    }

    function test_voucher_closedPoolWithoutVoucherReverts() public {
        (address managerSigner, ) = makeAddrAndKey("voucherManager");
        RecoursePool closedPool = _deployClosedPool(managerSigner);
        _setupEscrow(ESCROW_ID);

        vm.prank(buyer);
        vm.expectRevert(CoverageLib.InvitePoolMismatch.selector);
        coverageManager.purchaseCoverage(
            buyer,
            address(closedPool),
            mockPolicyAddress,
            ESCROW_ID,
            COVERAGE_AMOUNT,
            futureExpiry,
            "",
            ""
        );
    }

    function test_voucher_closedPoolValidVoucherSucceeds() public {
        (address managerSigner, uint256 managerKey) = makeAddrAndKey("voucherManager");
        RecoursePool closedPool = _deployClosedPool(managerSigner);
        _setupEscrow(ESCROW_ID);

        CoverageInviteLib.CoverageInvite memory invite = CoverageInviteLib.CoverageInvite({
            pool: address(closedPool),
            invitee: buyer,
            maxUses: 1,
            deadline: block.timestamp + 1 days,
            inviteId: 1
        });
        bytes memory sig = _signInvite(managerKey, closedPool, invite);

        bytes32 ds = closedPool.domainSeparator();
        bytes32 digest = CoverageInviteLib.digest(ds, invite);

        vm.prank(buyer);
        vm.expectEmit(true, true, true, false);
        emit ICoverageManagerEvents.InviteConsumed(address(closedPool), digest, buyer);
        coverageManager.purchaseCoverage(
            buyer,
            address(closedPool),
            mockPolicyAddress,
            ESCROW_ID,
            COVERAGE_AMOUNT,
            futureExpiry,
            "",
            "",
            invite,
            sig
        );

        assertEq(coverageManager.usedCount(digest), 1);
        assertEq(uint256(coverageManager.coverageStatus(0)), 1);
    }

    function test_voucher_revertsOnWrongInvitee() public {
        (address managerSigner, uint256 managerKey) = makeAddrAndKey("voucherManager");
        RecoursePool closedPool = _deployClosedPool(managerSigner);
        _setupEscrow(ESCROW_ID);

        CoverageInviteLib.CoverageInvite memory invite = CoverageInviteLib.CoverageInvite({
            pool: address(closedPool),
            invitee: attacker,
            maxUses: 1,
            deadline: block.timestamp + 1 days,
            inviteId: 1
        });
        bytes memory sig = _signInvite(managerKey, closedPool, invite);

        vm.prank(buyer);
        vm.expectRevert(CoverageLib.InviteeMismatch.selector);
        coverageManager.purchaseCoverage(
            buyer,
            address(closedPool),
            mockPolicyAddress,
            ESCROW_ID,
            COVERAGE_AMOUNT,
            futureExpiry,
            "",
            "",
            invite,
            sig
        );
    }

    function test_voucher_revertsOnWrongPool() public {
        (address managerSigner, uint256 managerKey) = makeAddrAndKey("voucherManager");
        RecoursePool closedPool = _deployClosedPool(managerSigner);
        _setupEscrow(ESCROW_ID);

        CoverageInviteLib.CoverageInvite memory invite = CoverageInviteLib.CoverageInvite({
            pool: poolAddress,
            invitee: buyer,
            maxUses: 1,
            deadline: block.timestamp + 1 days,
            inviteId: 1
        });
        bytes memory sig = _signInvite(managerKey, closedPool, invite);

        vm.prank(buyer);
        vm.expectRevert(CoverageLib.InvitePoolMismatch.selector);
        coverageManager.purchaseCoverage(
            buyer,
            address(closedPool),
            mockPolicyAddress,
            ESCROW_ID,
            COVERAGE_AMOUNT,
            futureExpiry,
            "",
            "",
            invite,
            sig
        );
    }

    function test_voucher_revertsOnExpiredVoucher() public {
        (address managerSigner, uint256 managerKey) = makeAddrAndKey("voucherManager");
        RecoursePool closedPool = _deployClosedPool(managerSigner);
        _setupEscrow(ESCROW_ID);

        uint256 pastDeadline = block.timestamp + 100;
        CoverageInviteLib.CoverageInvite memory invite = CoverageInviteLib.CoverageInvite({
            pool: address(closedPool),
            invitee: buyer,
            maxUses: 1,
            deadline: pastDeadline,
            inviteId: 1
        });
        bytes memory sig = _signInvite(managerKey, closedPool, invite);

        vm.warp(pastDeadline + 1);

        vm.prank(buyer);
        vm.expectRevert(CoverageLib.InviteExpired.selector);
        coverageManager.purchaseCoverage(
            buyer,
            address(closedPool),
            mockPolicyAddress,
            ESCROW_ID,
            COVERAGE_AMOUNT,
            pastDeadline + 1 days,
            "",
            "",
            invite,
            sig
        );
    }

    function test_voucher_revertsOnZeroMaxUses() public {
        (address managerSigner, uint256 managerKey) = makeAddrAndKey("voucherManager");
        RecoursePool closedPool = _deployClosedPool(managerSigner);
        _setupEscrow(ESCROW_ID);

        CoverageInviteLib.CoverageInvite memory invite = CoverageInviteLib.CoverageInvite({
            pool: address(closedPool),
            invitee: buyer,
            maxUses: 0,
            deadline: block.timestamp + 1 days,
            inviteId: 1
        });
        bytes memory sig = _signInvite(managerKey, closedPool, invite);

        vm.prank(buyer);
        vm.expectRevert(CoverageLib.InviteExhausted.selector);
        coverageManager.purchaseCoverage(
            buyer,
            address(closedPool),
            mockPolicyAddress,
            ESCROW_ID,
            COVERAGE_AMOUNT,
            futureExpiry,
            "",
            "",
            invite,
            sig
        );
    }

    function test_voucher_revertsOnSignerNotManager() public {
        (address managerSigner, ) = makeAddrAndKey("voucherManager");
        RecoursePool closedPool = _deployClosedPool(managerSigner);
        _setupEscrow(ESCROW_ID);

        (, uint256 wrongKey) = makeAddrAndKey("notTheManager");

        CoverageInviteLib.CoverageInvite memory invite = CoverageInviteLib.CoverageInvite({
            pool: address(closedPool),
            invitee: buyer,
            maxUses: 1,
            deadline: block.timestamp + 1 days,
            inviteId: 1
        });
        bytes memory sig = _signInvite(wrongKey, closedPool, invite);

        vm.prank(buyer);
        vm.expectRevert(CoverageLib.InviteSignerMismatch.selector);
        coverageManager.purchaseCoverage(
            buyer,
            address(closedPool),
            mockPolicyAddress,
            ESCROW_ID,
            COVERAGE_AMOUNT,
            futureExpiry,
            "",
            "",
            invite,
            sig
        );
    }

    function test_voucher_multiUseVoucherConsumesUpToMaxUses() public {
        (address managerSigner, uint256 managerKey) = makeAddrAndKey("voucherManager");
        RecoursePool closedPool = _deployClosedPool(managerSigner);

        CoverageInviteLib.CoverageInvite memory invite = CoverageInviteLib.CoverageInvite({
            pool: address(closedPool),
            invitee: buyer,
            maxUses: 3,
            deadline: block.timestamp + 1 days,
            inviteId: 1
        });
        bytes memory sig = _signInvite(managerKey, closedPool, invite);

        bytes32 digest = CoverageInviteLib.digest(closedPool.domainSeparator(), invite);

        for (uint256 i = 0; i < 3; i++) {
            _setupEscrow(i + 10);
            vm.prank(buyer);
            coverageManager.purchaseCoverage(
                buyer,
                address(closedPool),
                mockPolicyAddress,
                i + 10,
                COVERAGE_AMOUNT,
                futureExpiry,
                "",
                "",
                invite,
                sig
            );
        }
        assertEq(coverageManager.usedCount(digest), 3);

        _setupEscrow(13);
        vm.prank(buyer);
        vm.expectRevert(CoverageLib.InviteExhausted.selector);
        coverageManager.purchaseCoverage(
            buyer,
            address(closedPool),
            mockPolicyAddress,
            13,
            COVERAGE_AMOUNT,
            futureExpiry,
            "",
            "",
            invite,
            sig
        );
    }

    function test_revokeInvite_marksDigestRevokedAndBlocksConsumption() public {
        (address managerSigner, uint256 managerKey) = makeAddrAndKey("voucherManager");
        RecoursePool closedPool = _deployClosedPool(managerSigner);
        _setupEscrow(ESCROW_ID);

        CoverageInviteLib.CoverageInvite memory invite = CoverageInviteLib.CoverageInvite({
            pool: address(closedPool),
            invitee: buyer,
            maxUses: 1,
            deadline: block.timestamp + 1 days,
            inviteId: 1
        });
        bytes memory sig = _signInvite(managerKey, closedPool, invite);
        bytes32 digest = CoverageInviteLib.digest(closedPool.domainSeparator(), invite);

        vm.prank(managerSigner);
        vm.expectEmit(true, true, false, true);
        emit ICoverageManagerEvents.InviteRevoked(address(closedPool), digest, managerSigner);
        coverageManager.revokeInvite(address(closedPool), digest);

        assertTrue(coverageManager.isInviteRevoked(digest));

        vm.prank(buyer);
        vm.expectRevert(CoverageLib.InviteAlreadyRevoked.selector);
        coverageManager.purchaseCoverage(
            buyer,
            address(closedPool),
            mockPolicyAddress,
            ESCROW_ID,
            COVERAGE_AMOUNT,
            futureExpiry,
            "",
            "",
            invite,
            sig
        );
    }

    function test_revokeInvite_revertsForNonManager() public {
        (address managerSigner, ) = makeAddrAndKey("voucherManager");
        RecoursePool closedPool = _deployClosedPool(managerSigner);

        bytes32 digest = keccak256("arbitrary");

        vm.prank(attacker);
        vm.expectRevert(CoverageLib.NotManager.selector);
        coverageManager.revokeInvite(address(closedPool), digest);
    }

    function test_revokeInvite_idempotencyRevertsOnDoubleRevoke() public {
        (address managerSigner, ) = makeAddrAndKey("voucherManager");
        RecoursePool closedPool = _deployClosedPool(managerSigner);

        bytes32 digest = keccak256("arbitrary");

        vm.prank(managerSigner);
        coverageManager.revokeInvite(address(closedPool), digest);

        vm.prank(managerSigner);
        vm.expectRevert(CoverageLib.InviteAlreadyRevoked.selector);
        coverageManager.revokeInvite(address(closedPool), digest);
    }

    function test_voucher_managerRotationInvalidatesOutstandingVouchers() public {
        (address managerSigner, uint256 managerKey) = makeAddrAndKey("voucherManager");
        RecoursePool closedPool = _deployClosedPool(managerSigner);
        _setupEscrow(ESCROW_ID);

        CoverageInviteLib.CoverageInvite memory invite = CoverageInviteLib.CoverageInvite({
            pool: address(closedPool),
            invitee: buyer,
            maxUses: 1,
            deadline: block.timestamp + 1 days,
            inviteId: 1
        });
        bytes memory sig = _signInvite(managerKey, closedPool, invite);

        address newManager = makeAddr("newManager");
        vm.prank(managerSigner);
        closedPool.transferManager(newManager);

        vm.prank(buyer);
        vm.expectRevert(CoverageLib.InviteSignerMismatch.selector);
        coverageManager.purchaseCoverage(
            buyer,
            address(closedPool),
            mockPolicyAddress,
            ESCROW_ID,
            COVERAGE_AMOUNT,
            futureExpiry,
            "",
            "",
            invite,
            sig
        );
    }
}
