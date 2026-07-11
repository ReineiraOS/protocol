// SPDX-License-Identifier: FSL-1.1-ALv2
pragma solidity ^0.8.25;

import {Test} from "forge-std/Test.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {Escrow} from "../../contracts/core/Escrow.sol";
import {IEscrow} from "@reineira-os/shared/contracts/interfaces/core/IEscrow.sol";
import {IEscrowEvents} from "@reineira-os/shared/contracts/interfaces/core/IEscrowEvents.sol";
import {EscrowLib} from "@reineira-os/shared/contracts/libraries/EscrowLib.sol";
import {FeeLib} from "@reineira-os/shared/contracts/libraries/FeeLib.sol";
import {MockUSDC} from "@reineira-os/shared/contracts/mocks/MockUSDC.sol";
import {MockConditionResolver} from "../../contracts/mocks/MockConditionResolver.sol";
import {MockCoverageManager} from "../../contracts/mocks/MockCoverageManager.sol";

contract EscrowTest is Test {
    Escrow public escrow;
    MockUSDC public usdc;

    address public owner;
    address public user1;
    address public user2;
    address public conditionAuthor;
    address public pool;
    address public pool1;
    address public pool2;

    uint256 constant ESCROW_AMOUNT = 1000e6;
    uint16 constant CONDITION_BPS = 500;
    uint16 constant UNDERWRITER_BPS = 800;

    function setUp() public {
        owner = makeAddr("owner");
        user1 = makeAddr("user1");
        user2 = makeAddr("user2");
        conditionAuthor = makeAddr("conditionAuthor");
        pool = makeAddr("pool");
        pool1 = makeAddr("pool1");
        pool2 = makeAddr("pool2");

        vm.startPrank(owner);
        usdc = new MockUSDC();
        Escrow impl = new Escrow(address(0));
        escrow = Escrow(
            address(new ERC1967Proxy(address(impl), abi.encodeCall(Escrow.initialize, (owner, address(usdc)))))
        );
        vm.stopPrank();
    }

    function test_deployment_setsCorrectPaymentToken() public view {
        assertEq(address(escrow.paymentToken()), address(usdc));
    }

    function test_deployment_startsWithZeroEscrows() public view {
        assertEq(escrow.total(), 0);
    }

    function test_create_createsEscrowWithCorrectData() public {
        vm.prank(user1);
        uint256 id = escrow.create(user2, ESCROW_AMOUNT, address(0), "");

        assertEq(id, 0);
        assertTrue(escrow.exists(0));
        assertEq(escrow.getOwner(0), user2);
        assertEq(escrow.getAmount(0), ESCROW_AMOUNT);
        assertEq(escrow.getPaidAmount(0), 0);
        assertFalse(escrow.getRedeemedStatus(0));
        assertEq(escrow.getCaller(0), user1);
        assertEq(escrow.total(), 1);
    }

    function test_create_emitsEscrowCreatedEvent() public {
        vm.prank(user1);
        vm.expectEmit(true, false, false, false);
        emit IEscrowEvents.EscrowCreated(0);
        escrow.create(user2, ESCROW_AMOUNT, address(0), "");
    }

    function test_setCondition_stampsConditionFee() public {
        MockConditionResolver resolver = new MockConditionResolver();
        resolver.setConditionFee(CONDITION_BPS, conditionAuthor);

        vm.prank(user1);
        escrow.create(user2, ESCROW_AMOUNT, address(resolver), "");

        (uint16 bps, address recipient, bool set) = escrow.getFee(0, uint8(FeeLib.FeeKind.Condition));
        assertEq(bps, CONDITION_BPS);
        assertEq(recipient, conditionAuthor);
        assertTrue(set);
    }

    function test_setCondition_skipsFeeWhenResolverReturnsZero() public {
        MockConditionResolver resolver = new MockConditionResolver();

        vm.prank(user1);
        escrow.create(user2, ESCROW_AMOUNT, address(resolver), "");

        (, , bool set) = escrow.getFee(0, uint8(FeeLib.FeeKind.Condition));
        assertFalse(set);
    }

    function test_setUnderwriterFee_stampsFeeWhenAuthorized() public {
        MockCoverageManager mgr = new MockCoverageManager(address(escrow));
        vm.prank(owner);
        escrow.setCoverageManager(address(mgr));

        vm.prank(user1);
        escrow.create(user1, ESCROW_AMOUNT, address(0), "");

        mgr.setFee(0, user1, UNDERWRITER_BPS, pool);

        (uint16 bps, address recipient, bool set) = escrow.getFee(0, uint8(FeeLib.FeeKind.Underwriter));
        assertEq(bps, UNDERWRITER_BPS);
        assertEq(recipient, pool);
        assertTrue(set);
    }

    function test_setUnderwriterFee_zeroesBpsIfHolderNotAuthorized() public {
        MockCoverageManager mgr = new MockCoverageManager(address(escrow));
        vm.prank(owner);
        escrow.setCoverageManager(address(mgr));

        vm.prank(user1);
        escrow.create(user1, ESCROW_AMOUNT, address(0), "");

        mgr.setFee(0, user2, UNDERWRITER_BPS, pool);

        usdc.mint(user1, ESCROW_AMOUNT);
        vm.startPrank(user1);
        usdc.approve(address(escrow), ESCROW_AMOUNT);
        escrow.fund(0, ESCROW_AMOUNT);
        escrow.redeem(0);
        vm.stopPrank();

        assertEq(usdc.balanceOf(user1), ESCROW_AMOUNT);
        assertEq(usdc.balanceOf(pool), 0);
    }

    function test_setUnderwriterFee_revertsIfNotCoverageManager() public {
        vm.prank(user1);
        escrow.create(user1, ESCROW_AMOUNT, address(0), "");

        vm.prank(user1);
        vm.expectRevert(EscrowLib.NotCoverageManager.selector);
        escrow.setUnderwriterFee(0, user1, UNDERWRITER_BPS, pool);
    }

    function test_setUnderwriterFee_revertsIfSumExceedsMaxBps() public {
        MockCoverageManager mgr = new MockCoverageManager(address(escrow));
        vm.prank(owner);
        escrow.setCoverageManager(address(mgr));

        vm.prank(user1);
        escrow.create(user1, ESCROW_AMOUNT, address(0), "");

        vm.expectRevert();
        mgr.setFee(0, user1, uint16(FeeLib.MAX_TOTAL_BPS + 1), pool);
    }

    function test_redeem_transfersFundsToOwner_noFees() public {
        vm.prank(user1);
        escrow.create(user2, ESCROW_AMOUNT, address(0), "");

        usdc.mint(user1, ESCROW_AMOUNT);
        vm.startPrank(user1);
        usdc.approve(address(escrow), ESCROW_AMOUNT);
        escrow.fund(0, ESCROW_AMOUNT);
        vm.stopPrank();

        vm.prank(user2);
        escrow.redeem(0);

        assertEq(usdc.balanceOf(user2), ESCROW_AMOUNT);
        assertTrue(escrow.getRedeemedStatus(0));
    }

    function test_redeem_distributesConditionAndUnderwriterFees() public {
        MockConditionResolver resolver = new MockConditionResolver();
        resolver.setCondition(0, true);
        resolver.setConditionFee(CONDITION_BPS, conditionAuthor);

        MockCoverageManager mgr = new MockCoverageManager(address(escrow));
        vm.prank(owner);
        escrow.setCoverageManager(address(mgr));

        vm.prank(user1);
        escrow.create(user1, ESCROW_AMOUNT, address(resolver), "");

        mgr.setFee(0, user1, UNDERWRITER_BPS, pool);

        usdc.mint(user1, ESCROW_AMOUNT);
        vm.startPrank(user1);
        usdc.approve(address(escrow), ESCROW_AMOUNT);
        escrow.fund(0, ESCROW_AMOUNT);
        escrow.redeem(0);
        vm.stopPrank();

        uint256 expectedConditionFee = (ESCROW_AMOUNT * CONDITION_BPS) / 10000;
        uint256 expectedUnderwriterFee = (ESCROW_AMOUNT * UNDERWRITER_BPS) / 10000;
        uint256 expectedNet = ESCROW_AMOUNT - expectedConditionFee - expectedUnderwriterFee;

        assertEq(usdc.balanceOf(conditionAuthor), expectedConditionFee);
        assertEq(usdc.balanceOf(pool), expectedUnderwriterFee);
        assertEq(usdc.balanceOf(user1), expectedNet);
    }

    function test_redeem_twoUnderwriterFees_fromDifferentPools() public {
        MockCoverageManager mgr = new MockCoverageManager(address(escrow));
        vm.prank(owner);
        escrow.setCoverageManager(address(mgr));

        vm.prank(user1);
        escrow.create(user1, ESCROW_AMOUNT, address(0), "");

        uint16 underwriterBps1 = 400;
        uint16 underwriterBps2 = 400;

        mgr.setFee(0, user1, underwriterBps1, pool1);
        mgr.setFee(0, user1, underwriterBps2, pool2);

        usdc.mint(user1, ESCROW_AMOUNT);
        vm.startPrank(user1);
        usdc.approve(address(escrow), ESCROW_AMOUNT);
        escrow.fund(0, ESCROW_AMOUNT);
        escrow.redeem(0);
        vm.stopPrank();

        uint256 expectedUnderwriterFee1 = (ESCROW_AMOUNT * underwriterBps1) / 10000;
        uint256 expectedUnderwriterFee2 = (ESCROW_AMOUNT * underwriterBps2) / 10000;
        uint256 expectedNet = ESCROW_AMOUNT - expectedUnderwriterFee1 - expectedUnderwriterFee2;

        assertEq(usdc.balanceOf(pool1), expectedUnderwriterFee1);
        assertEq(usdc.balanceOf(pool2), expectedUnderwriterFee2);
        assertEq(usdc.balanceOf(user1), expectedNet);
    }

    function test_redeem_totalStampedBps_tracksSum() public {
        MockConditionResolver resolver = new MockConditionResolver();
        resolver.setConditionFee(CONDITION_BPS, conditionAuthor);
        MockCoverageManager mgr = new MockCoverageManager(address(escrow));
        vm.prank(owner);
        escrow.setCoverageManager(address(mgr));

        vm.prank(user1);
        escrow.create(user1, ESCROW_AMOUNT, address(resolver), "");
        mgr.setFee(0, user1, UNDERWRITER_BPS, pool);

        uint16 totalBps = escrow.getTotalStampedBps(0);
        assertEq(totalBps, CONDITION_BPS + UNDERWRITER_BPS);
    }

    function test_redeem_revertsIfNotOwner() public {
        vm.prank(user1);
        escrow.create(user2, ESCROW_AMOUNT, address(0), "");

        usdc.mint(user1, ESCROW_AMOUNT);
        vm.startPrank(user1);
        usdc.approve(address(escrow), ESCROW_AMOUNT);
        escrow.fund(0, ESCROW_AMOUNT);
        vm.stopPrank();

        vm.prank(user1);
        vm.expectRevert(IEscrow.NotOwner.selector);
        escrow.redeem(0);
    }

    function test_redeem_revertsIfNotFullyPaid() public {
        vm.prank(user1);
        escrow.create(user2, ESCROW_AMOUNT, address(0), "");

        vm.prank(user2);
        vm.expectRevert(IEscrow.NotFullyPaid.selector);
        escrow.redeem(0);
    }

    function test_redeem_revertsIfAlreadyRedeemed() public {
        vm.prank(user1);
        escrow.create(user2, ESCROW_AMOUNT, address(0), "");

        usdc.mint(user1, ESCROW_AMOUNT);
        vm.startPrank(user1);
        usdc.approve(address(escrow), ESCROW_AMOUNT);
        escrow.fund(0, ESCROW_AMOUNT);
        vm.stopPrank();

        vm.prank(user2);
        escrow.redeem(0);

        vm.prank(user2);
        vm.expectRevert(IEscrow.AlreadyRedeemed.selector);
        escrow.redeem(0);
    }

    function test_redeem_revertsIfConditionNotMet() public {
        MockConditionResolver resolver = new MockConditionResolver();
        vm.prank(user1);
        escrow.create(user2, ESCROW_AMOUNT, address(resolver), "");

        usdc.mint(user1, ESCROW_AMOUNT);
        vm.startPrank(user1);
        usdc.approve(address(escrow), ESCROW_AMOUNT);
        escrow.fund(0, ESCROW_AMOUNT);
        vm.stopPrank();

        vm.prank(user2);
        vm.expectRevert();
        escrow.redeem(0);
    }

    function test_redeemMultiple_redeemsMultipleEscrows() public {
        vm.startPrank(user1);
        escrow.create(user1, ESCROW_AMOUNT, address(0), "");
        escrow.create(user1, ESCROW_AMOUNT, address(0), "");
        vm.stopPrank();

        usdc.mint(user1, ESCROW_AMOUNT * 2);
        vm.startPrank(user1);
        usdc.approve(address(escrow), ESCROW_AMOUNT * 2);
        escrow.fund(0, ESCROW_AMOUNT);
        escrow.fund(1, ESCROW_AMOUNT);
        vm.stopPrank();

        uint256[] memory ids = new uint256[](2);
        ids[0] = 0;
        ids[1] = 1;

        vm.prank(user1);
        escrow.redeemMultiple(ids);

        assertEq(usdc.balanceOf(user1), ESCROW_AMOUNT * 2);
        assertTrue(escrow.getRedeemedStatus(0));
        assertTrue(escrow.getRedeemedStatus(1));
    }

    function test_view_returnsFalseForNonExistent() public view {
        assertFalse(escrow.exists(0));
        assertFalse(escrow.exists(999));
    }

    function test_initialize_allowsDefaultToken() public view {
        assertTrue(escrow.isAllowedToken(address(usdc)));
    }

    function test_addAllowedToken_onlyOwner() public {
        MockUSDC token = new MockUSDC();
        vm.prank(user1);
        vm.expectRevert();
        escrow.addAllowedToken(address(token));
    }

    function test_addAllowedToken_setsAllowedAndEmits() public {
        MockUSDC token = new MockUSDC();
        vm.prank(owner);
        vm.expectEmit(true, false, false, false);
        emit IEscrowEvents.TokenAllowed(address(token));
        escrow.addAllowedToken(address(token));
        assertTrue(escrow.isAllowedToken(address(token)));
    }

    function test_addAllowedToken_revertsOnZeroAddress() public {
        vm.prank(owner);
        vm.expectRevert();
        escrow.addAllowedToken(address(0));
    }

    function test_removeAllowedToken_onlyOwner() public {
        vm.prank(user1);
        vm.expectRevert();
        escrow.removeAllowedToken(address(usdc));
    }

    function test_removeAllowedToken_clearsAllowedAndEmits() public {
        vm.prank(owner);
        vm.expectEmit(true, false, false, false);
        emit IEscrowEvents.TokenRemoved(address(usdc));
        escrow.removeAllowedToken(address(usdc));
        assertFalse(escrow.isAllowedToken(address(usdc)));
    }

    function test_removeAllowedToken_existingEscrowStillRedeems() public {
        MockUSDC token = new MockUSDC();
        vm.prank(owner);
        escrow.addAllowedToken(address(token));

        vm.prank(user1);
        escrow.create(abi.encode(user2, ESCROW_AMOUNT, address(token)), address(0), "");

        vm.prank(owner);
        escrow.removeAllowedToken(address(token));

        vm.prank(user1);
        vm.expectRevert(abi.encodeWithSelector(EscrowLib.TokenNotAllowed.selector, address(token)));
        escrow.create(abi.encode(user2, ESCROW_AMOUNT, address(token)), address(0), "");

        token.mint(user1, ESCROW_AMOUNT);
        vm.startPrank(user1);
        token.approve(address(escrow), ESCROW_AMOUNT);
        escrow.fund(0, ESCROW_AMOUNT);
        vm.stopPrank();

        vm.prank(user2);
        escrow.redeem(0);
        assertEq(token.balanceOf(user2), ESCROW_AMOUNT);
    }

    function test_create_typed_usesDefaultToken() public {
        vm.prank(user1);
        escrow.create(user2, ESCROW_AMOUNT, address(0), "");
        assertEq(escrow.paymentTokenOf(0), address(usdc));
    }

    function test_create_bytes2Field_usesDefaultToken() public {
        vm.prank(user1);
        escrow.create(abi.encode(user2, ESCROW_AMOUNT), address(0), "");
        assertEq(escrow.paymentTokenOf(0), address(usdc));
    }

    function test_create_bytes3Field_zeroToken_usesDefaultToken() public {
        vm.prank(user1);
        escrow.create(abi.encode(user2, ESCROW_AMOUNT, address(0)), address(0), "");
        assertEq(escrow.paymentTokenOf(0), address(usdc));
    }

    function test_create_bytes3Field_allowedToken_setsPaymentTokenOf() public {
        MockUSDC token = new MockUSDC();
        vm.prank(owner);
        escrow.addAllowedToken(address(token));

        vm.prank(user1);
        escrow.create(abi.encode(user2, ESCROW_AMOUNT, address(token)), address(0), "");
        assertEq(escrow.paymentTokenOf(0), address(token));
    }

    function test_create_bytes3Field_notAllowedToken_reverts() public {
        MockUSDC token = new MockUSDC();
        vm.prank(user1);
        vm.expectRevert(abi.encodeWithSelector(EscrowLib.TokenNotAllowed.selector, address(token)));
        escrow.create(abi.encode(user2, ESCROW_AMOUNT, address(token)), address(0), "");
    }

    function test_paymentTokenOf_revertsForNonExistent() public {
        vm.expectRevert(abi.encodeWithSelector(EscrowLib.EscrowDoesNotExist.selector, uint256(0)));
        escrow.paymentTokenOf(0);
    }

    function test_fundAndRedeem_useSelectedToken() public {
        MockUSDC token = new MockUSDC();
        vm.prank(owner);
        escrow.addAllowedToken(address(token));

        vm.prank(user1);
        escrow.create(abi.encode(user2, ESCROW_AMOUNT, address(token)), address(0), "");

        token.mint(user1, ESCROW_AMOUNT);
        vm.startPrank(user1);
        token.approve(address(escrow), ESCROW_AMOUNT);
        escrow.fund(0, ESCROW_AMOUNT);
        vm.stopPrank();

        assertEq(token.balanceOf(address(escrow)), ESCROW_AMOUNT);
        assertEq(usdc.balanceOf(address(escrow)), 0);

        vm.prank(user2);
        escrow.redeem(0);

        assertEq(token.balanceOf(user2), ESCROW_AMOUNT);
        assertEq(usdc.balanceOf(user2), 0);
    }

    function test_redeemMultiple_paysEachTokenSeparately() public {
        MockUSDC token = new MockUSDC();
        vm.prank(owner);
        escrow.addAllowedToken(address(token));

        vm.startPrank(user1);
        escrow.create(user1, ESCROW_AMOUNT, address(0), "");
        escrow.create(abi.encode(user1, ESCROW_AMOUNT, address(token)), address(0), "");
        vm.stopPrank();

        usdc.mint(user1, ESCROW_AMOUNT);
        token.mint(user1, ESCROW_AMOUNT);
        vm.startPrank(user1);
        usdc.approve(address(escrow), ESCROW_AMOUNT);
        token.approve(address(escrow), ESCROW_AMOUNT);
        escrow.fund(0, ESCROW_AMOUNT);
        escrow.fund(1, ESCROW_AMOUNT);
        vm.stopPrank();

        uint256[] memory ids = new uint256[](2);
        ids[0] = 0;
        ids[1] = 1;

        vm.prank(user1);
        escrow.redeemMultiple(ids);

        assertEq(usdc.balanceOf(user1), ESCROW_AMOUNT);
        assertEq(token.balanceOf(user1), ESCROW_AMOUNT);
        assertTrue(escrow.getRedeemedStatus(0));
        assertTrue(escrow.getRedeemedStatus(1));
    }
}
