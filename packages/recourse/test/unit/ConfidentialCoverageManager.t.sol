// SPDX-License-Identifier: FSL-1.1-ALv2
pragma solidity ^0.8.25;

import {FHETestBase} from "@reineira-os/shared/test/FHETestBase.sol";
import {ICoverageManagerEvents} from "@reineira-os/shared/contracts/interfaces/core/ICoverageManagerEvents.sol";
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

contract ConfidentialCoverageManagerTest is FHETestBase {
    ConfidentialPoolFactory public poolFactory;
    ConfidentialPolicyRegistry public policyRegistry;
    ConfidentialCoverageManager public coverageManager;
    MockConfidentialToken public token;
    MockConfidentialEscrow public mockEscrow;
    MockConfidentialUnderwriterPolicy public mockPolicy;
    ConfidentialRecoursePool public pool;

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

    uint64 constant STAKE_AMOUNT = 10000;
    uint64 constant COVERAGE_AMOUNT = 5000;
    uint64 constant ESCROW_AMOUNT = 10000;
    uint256 constant ESCROW_ID = 0;
    uint256 futureExpiry;

    function setUp() public {
        _initFHE();
        owner = makeAddr("owner");
        creator = makeAddr("creator");
        lp1 = _makeAccount("lp1");
        buyer = _makeAccount("buyer");
        attacker = makeAddr("attacker");
        futureExpiry = block.timestamp + 86400;

        vm.startPrank(owner);

        token = new MockConfidentialToken();
        mockEscrow = new MockConfidentialEscrow();
        mockEscrowAddress = address(mockEscrow);
        mockPolicy = new MockConfidentialUnderwriterPolicy();
        mockPolicyAddress = address(mockPolicy);

        ConfidentialPolicyRegistry policyRegistryImpl = new ConfidentialPolicyRegistry(address(0));
        policyRegistry = ConfidentialPolicyRegistry(
            address(
                new ERC1967Proxy(
                    address(policyRegistryImpl),
                    abi.encodeCall(ConfidentialPolicyRegistry.initialize, (owner))
                )
            )
        );
        policyRegistry.registerPolicy(mockPolicyAddress);

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
        coverageManager.setEscrow(mockEscrowAddress);

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
        poolFactoryAddress = address(poolFactory);
        coverageManager.setPoolFactory(poolFactoryAddress);
        poolFactory.addAllowedToken(address(token));

        vm.stopPrank();

        vm.prank(creator);
        poolFactory.createPool(IFHERC20(address(token)), address(0), address(0), true);
        poolAddress = poolFactory.pool(0);
        pool = ConfidentialRecoursePool(poolAddress);

        vm.prank(creator);
        pool.addPolicy(mockPolicyAddress);

        vm.prank(owner);
        token.mintPlain(lp1, STAKE_AMOUNT);
        vm.prank(lp1);
        token.setOperator(poolAddress, uint48(block.timestamp + 86400));
        InEuint64 memory encStake = createInEuint64(STAKE_AMOUNT, lp1);
        vm.prank(lp1);
        pool.stake(encStake);
    }

    function _setupEscrow(uint256 escrowId) internal {
        mockEscrow.setExists(escrowId, true);
        mockEscrow.setAmount(escrowId, uint64(ESCROW_AMOUNT), coverageManagerAddress);
    }

    function _purchaseCoverage() internal {
        _setupEscrow(ESCROW_ID);

        InEaddress memory encHolder = createInEaddress(buyer, buyer);
        InEuint64 memory encAmount = createInEuint64(COVERAGE_AMOUNT, buyer);

        vm.prank(buyer);
        coverageManager.purchaseCoverage(
            encHolder,
            poolAddress,
            mockPolicyAddress,
            ESCROW_ID,
            encAmount,
            futureExpiry,
            "",
            ""
        );
    }

    function _deployClosedPool(address managerSigner) internal returns (ConfidentialRecoursePool closedPool) {
        vm.prank(creator);
        (, address poolAddr) = poolFactory.createPool(IFHERC20(address(token)), managerSigner, address(0), false);
        closedPool = ConfidentialRecoursePool(poolAddr);

        vm.prank(creator);
        closedPool.addPolicy(mockPolicyAddress);

        vm.prank(owner);
        token.mintPlain(lp1, STAKE_AMOUNT);
        vm.prank(lp1);
        token.setOperator(poolAddr, uint48(block.timestamp + 86400));
        InEuint64 memory encStake = createInEuint64(STAKE_AMOUNT, lp1);
        vm.prank(lp1);
        closedPool.stake(encStake);
    }

    function _signInvite(
        uint256 key,
        ConfidentialRecoursePool pool_,
        CoverageInviteLib.CoverageInvite memory invite
    ) internal view returns (bytes memory) {
        bytes32 ds = pool_.domainSeparator();
        bytes32 d = CoverageInviteLib.digest(ds, invite);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(key, d);
        return abi.encodePacked(r, s, v);
    }

    function test_purchaseCoverage_purchasesCoverageSuccessfully() public {
        _setupEscrow(ESCROW_ID);

        InEaddress memory encHolder = createInEaddress(buyer, buyer);
        InEuint64 memory encAmount = createInEuint64(COVERAGE_AMOUNT, buyer);

        vm.prank(buyer);
        vm.expectEmit(true, false, false, false);
        emit ICoverageManagerEvents.CoveragePurchased(0);
        coverageManager.purchaseCoverage(
            encHolder,
            poolAddress,
            mockPolicyAddress,
            ESCROW_ID,
            encAmount,
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
        InEaddress memory encHolder = createInEaddress(buyer, buyer);
        InEuint64 memory encAmount = createInEuint64(COVERAGE_AMOUNT, buyer);

        vm.prank(buyer);
        vm.expectRevert(CoverageLib.InvalidPool.selector);
        coverageManager.purchaseCoverage(
            encHolder,
            attacker,
            mockPolicyAddress,
            ESCROW_ID,
            encAmount,
            futureExpiry,
            "",
            ""
        );
    }

    function test_purchaseCoverage_revertsForPolicyNotAllowedOnPool() public {
        MockConfidentialUnderwriterPolicy otherPolicy = new MockConfidentialUnderwriterPolicy();

        InEaddress memory encHolder = createInEaddress(buyer, buyer);
        InEuint64 memory encAmount = createInEuint64(COVERAGE_AMOUNT, buyer);

        vm.prank(buyer);
        vm.expectRevert(CoverageLib.InvalidPolicy.selector);
        coverageManager.purchaseCoverage(
            encHolder,
            poolAddress,
            address(otherPolicy),
            ESCROW_ID,
            encAmount,
            futureExpiry,
            "",
            ""
        );
    }

    function test_purchaseCoverage_revertsForPastExpiry() public {
        _setupEscrow(ESCROW_ID);

        InEaddress memory encHolder = createInEaddress(buyer, buyer);
        InEuint64 memory encAmount = createInEuint64(COVERAGE_AMOUNT, buyer);

        vm.prank(buyer);
        vm.expectRevert(CoverageLib.InvalidExpiry.selector);
        coverageManager.purchaseCoverage(encHolder, poolAddress, mockPolicyAddress, ESCROW_ID, encAmount, 1, "", "");
    }

    function test_purchaseCoverage_revertsForNonExistentEscrow() public {
        InEaddress memory encHolder = createInEaddress(buyer, buyer);
        InEuint64 memory encAmount = createInEuint64(COVERAGE_AMOUNT, buyer);

        vm.prank(buyer);
        vm.expectRevert(CoverageLib.EscrowDoesNotExist.selector);
        coverageManager.purchaseCoverage(
            encHolder,
            poolAddress,
            mockPolicyAddress,
            999,
            encAmount,
            futureExpiry,
            "",
            ""
        );
    }

    function test_purchaseCoverage_allowsMultipleCoveragesPerEscrow() public {
        _purchaseCoverage();

        InEaddress memory encHolder2 = createInEaddress(buyer, buyer);
        InEuint64 memory encAmount2 = createInEuint64(COVERAGE_AMOUNT, buyer);

        vm.prank(buyer);
        uint256 coverageId2 = coverageManager.purchaseCoverage(
            encHolder2,
            poolAddress,
            mockPolicyAddress,
            ESCROW_ID,
            encAmount2,
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
        _setupEscrow(ESCROW_ID);

        for (uint256 i = 0; i < coverageManager.MAX_COVERAGES_PER_ESCROW(); i++) {
            InEaddress memory encHolder = createInEaddress(buyer, buyer);
            InEuint64 memory encAmount = createInEuint64(COVERAGE_AMOUNT / 10, buyer);

            vm.prank(buyer);
            coverageManager.purchaseCoverage(
                encHolder,
                poolAddress,
                mockPolicyAddress,
                ESCROW_ID,
                encAmount,
                futureExpiry,
                "",
                ""
            );
        }

        InEaddress memory encHolderExtra = createInEaddress(buyer, buyer);
        InEuint64 memory encAmountExtra = createInEuint64(COVERAGE_AMOUNT / 10, buyer);

        vm.prank(buyer);
        vm.expectRevert(CoverageLib.MaxCoveragesReached.selector);
        coverageManager.purchaseCoverage(
            encHolderExtra,
            poolAddress,
            mockPolicyAddress,
            ESCROW_ID,
            encAmountExtra,
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

    function test_dispute_revertsForNonexistentCoverage() public {
        _purchaseCoverage();

        vm.prank(buyer);
        vm.expectRevert(CoverageLib.CoverageDoesNotExist.selector);
        coverageManager.dispute(999, "");
    }

    function test_dispute_revertsWhenNonHolderCallsDispute() public {
        _purchaseCoverage();

        vm.prank(attacker);
        vm.expectRevert(CoverageLib.NotCoverageHolder.selector);
        coverageManager.dispute(0, "");
    }

    function test_dispute_paysOutToHolderAddressNotMsgSender() public {
        _purchaseCoverage();

        vm.prank(buyer);
        vm.expectEmit(true, false, false, false);
        emit ICoverageManagerEvents.CoverageClaimed(0);
        coverageManager.dispute(0, "");

        assertEq(uint256(coverageManager.coverageStatus(0)), 3);
    }

    function test_dispute_revertsIfAlreadyClaimed() public {
        _purchaseCoverage();

        vm.prank(buyer);
        coverageManager.dispute(0, "");

        vm.prank(buyer);
        vm.expectRevert(CoverageLib.NotActiveStatus.selector);
        coverageManager.dispute(0, "");
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

    function test_voucher_openPoolIgnoresInvite() public {
        _setupEscrow(ESCROW_ID);

        InEaddress memory encHolder = createInEaddress(buyer, buyer);
        InEuint64 memory encAmount = createInEuint64(COVERAGE_AMOUNT, buyer);

        CoverageInviteLib.CoverageInvite memory invite;

        vm.prank(buyer);
        coverageManager.purchaseCoverage(
            encHolder,
            poolAddress,
            mockPolicyAddress,
            ESCROW_ID,
            encAmount,
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
        ConfidentialRecoursePool closedPool = _deployClosedPool(managerSigner);
        _setupEscrow(ESCROW_ID);

        InEaddress memory encHolder = createInEaddress(buyer, buyer);
        InEuint64 memory encAmount = createInEuint64(COVERAGE_AMOUNT, buyer);

        vm.prank(buyer);
        vm.expectRevert(CoverageLib.InvitePoolMismatch.selector);
        coverageManager.purchaseCoverage(
            encHolder,
            address(closedPool),
            mockPolicyAddress,
            ESCROW_ID,
            encAmount,
            futureExpiry,
            "",
            ""
        );
    }

    function test_voucher_closedPoolValidVoucherSucceeds() public {
        (address managerSigner, uint256 managerKey) = makeAddrAndKey("voucherManager");
        ConfidentialRecoursePool closedPool = _deployClosedPool(managerSigner);
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

        InEaddress memory encHolder = createInEaddress(buyer, buyer);
        InEuint64 memory encAmount = createInEuint64(COVERAGE_AMOUNT, buyer);

        vm.prank(buyer);
        vm.expectEmit(true, true, true, false);
        emit ICoverageManagerEvents.InviteConsumed(address(closedPool), digest, buyer);
        coverageManager.purchaseCoverage(
            encHolder,
            address(closedPool),
            mockPolicyAddress,
            ESCROW_ID,
            encAmount,
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
        ConfidentialRecoursePool closedPool = _deployClosedPool(managerSigner);
        _setupEscrow(ESCROW_ID);

        CoverageInviteLib.CoverageInvite memory invite = CoverageInviteLib.CoverageInvite({
            pool: address(closedPool),
            invitee: attacker,
            maxUses: 1,
            deadline: block.timestamp + 1 days,
            inviteId: 1
        });
        bytes memory sig = _signInvite(managerKey, closedPool, invite);

        InEaddress memory encHolder = createInEaddress(buyer, buyer);
        InEuint64 memory encAmount = createInEuint64(COVERAGE_AMOUNT, buyer);

        vm.prank(buyer);
        vm.expectRevert(CoverageLib.InviteeMismatch.selector);
        coverageManager.purchaseCoverage(
            encHolder,
            address(closedPool),
            mockPolicyAddress,
            ESCROW_ID,
            encAmount,
            futureExpiry,
            "",
            "",
            invite,
            sig
        );
    }

    function test_voucher_revertsOnExpiredVoucher() public {
        (address managerSigner, uint256 managerKey) = makeAddrAndKey("voucherManager");
        ConfidentialRecoursePool closedPool = _deployClosedPool(managerSigner);
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

        InEaddress memory encHolder = createInEaddress(buyer, buyer);
        InEuint64 memory encAmount = createInEuint64(COVERAGE_AMOUNT, buyer);

        vm.prank(buyer);
        vm.expectRevert(CoverageLib.InviteExpired.selector);
        coverageManager.purchaseCoverage(
            encHolder,
            address(closedPool),
            mockPolicyAddress,
            ESCROW_ID,
            encAmount,
            pastDeadline + 1 days,
            "",
            "",
            invite,
            sig
        );
    }

    function test_voucher_revertsOnSignerNotManager() public {
        (address managerSigner, ) = makeAddrAndKey("voucherManager");
        ConfidentialRecoursePool closedPool = _deployClosedPool(managerSigner);
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

        InEaddress memory encHolder = createInEaddress(buyer, buyer);
        InEuint64 memory encAmount = createInEuint64(COVERAGE_AMOUNT, buyer);

        vm.prank(buyer);
        vm.expectRevert(CoverageLib.InviteSignerMismatch.selector);
        coverageManager.purchaseCoverage(
            encHolder,
            address(closedPool),
            mockPolicyAddress,
            ESCROW_ID,
            encAmount,
            futureExpiry,
            "",
            "",
            invite,
            sig
        );
    }

    function test_revokeInvite_marksDigestRevokedAndBlocksConsumption() public {
        (address managerSigner, uint256 managerKey) = makeAddrAndKey("voucherManager");
        ConfidentialRecoursePool closedPool = _deployClosedPool(managerSigner);
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

        InEaddress memory encHolder = createInEaddress(buyer, buyer);
        InEuint64 memory encAmount = createInEuint64(COVERAGE_AMOUNT, buyer);

        vm.prank(buyer);
        vm.expectRevert(CoverageLib.InviteAlreadyRevoked.selector);
        coverageManager.purchaseCoverage(
            encHolder,
            address(closedPool),
            mockPolicyAddress,
            ESCROW_ID,
            encAmount,
            futureExpiry,
            "",
            "",
            invite,
            sig
        );
    }

    function test_revokeInvite_revertsForNonManager() public {
        (address managerSigner, ) = makeAddrAndKey("voucherManager");
        ConfidentialRecoursePool closedPool = _deployClosedPool(managerSigner);

        bytes32 digest = keccak256("arbitrary");

        vm.prank(attacker);
        vm.expectRevert(CoverageLib.NotManager.selector);
        coverageManager.revokeInvite(address(closedPool), digest);
    }

    function test_voucher_managerRotationInvalidatesOutstandingVouchers() public {
        (address managerSigner, uint256 managerKey) = makeAddrAndKey("voucherManager");
        ConfidentialRecoursePool closedPool = _deployClosedPool(managerSigner);
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

        InEaddress memory encHolder = createInEaddress(buyer, buyer);
        InEuint64 memory encAmount = createInEuint64(COVERAGE_AMOUNT, buyer);

        vm.prank(buyer);
        vm.expectRevert(CoverageLib.InviteSignerMismatch.selector);
        coverageManager.purchaseCoverage(
            encHolder,
            address(closedPool),
            mockPolicyAddress,
            ESCROW_ID,
            encAmount,
            futureExpiry,
            "",
            "",
            invite,
            sig
        );
    }
}
