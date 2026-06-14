// SPDX-License-Identifier: FSL-1.1-ALv2
pragma solidity ^0.8.25;

import {Test} from "forge-std/Test.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {Escrow} from "../../contracts/core/Escrow.sol";
import {CCTPV2EscrowReceiver} from "../../contracts/receivers/CCTPV2EscrowReceiver.sol";
import {IEscrow} from "@reineira-os/shared/contracts/interfaces/core/IEscrow.sol";
import {IEscrowEvents} from "@reineira-os/shared/contracts/interfaces/core/IEscrowEvents.sol";
import {ICCTPV2EscrowReceiver} from "../../contracts/interfaces/receivers/ICCTPV2EscrowReceiver.sol";
import {MockUSDC} from "@reineira-os/shared/contracts/mocks/MockUSDC.sol";
import {MockCCTPV2MessageTransmitter} from "../../contracts/mocks/MockCCTPV2MessageTransmitter.sol";
import {MockCoverageManager} from "../../contracts/mocks/MockCoverageManager.sol";

contract EscrowSettlementTest is Test {
    CCTPV2EscrowReceiver public receiver;
    Escrow public escrow;
    MockUSDC public usdc;
    MockCCTPV2MessageTransmitter public transmitter;

    address public owner;
    address public escrowOwner;
    address public secondEscrowOwner;
    address public relayer;

    uint256 constant ESCROW_AMOUNT = 1_000_000;
    uint256 constant FEE_AMOUNT = 50_000;
    uint16 constant FEE_BPS = 500;

    function setUp() public {
        owner = makeAddr("owner");
        escrowOwner = makeAddr("escrowOwner");
        secondEscrowOwner = makeAddr("secondEscrowOwner");
        relayer = makeAddr("relayer");

        vm.startPrank(owner);

        usdc = new MockUSDC();
        transmitter = new MockCCTPV2MessageTransmitter(address(usdc));

        Escrow plainEscrow = new Escrow(address(0));
        escrow = Escrow(
            address(new ERC1967Proxy(address(plainEscrow), abi.encodeCall(Escrow.initialize, (owner, address(usdc)))))
        );

        CCTPV2EscrowReceiver plainReceiver = new CCTPV2EscrowReceiver(address(0));
        receiver = CCTPV2EscrowReceiver(
            address(
                new ERC1967Proxy(
                    address(plainReceiver),
                    abi.encodeCall(
                        CCTPV2EscrowReceiver.initialize,
                        (owner, address(transmitter), address(usdc), address(escrow))
                    )
                )
            )
        );

        vm.stopPrank();
    }

    function buildMockCCTPV2Message(uint256 escrowId) internal pure returns (bytes memory) {
        bytes memory padding = new bytes(376);
        return abi.encodePacked(padding, escrowId);
    }

    function _createEscrow(address escrowOwnerAddr, uint256 amount) internal returns (uint256) {
        vm.prank(owner);
        return escrow.create(escrowOwnerAddr, amount, address(0), "");
    }

    function _settle(uint256 escrowId, uint256 usdcAmount) internal {
        transmitter.setAmountToMint(usdcAmount);
        usdc.mint(address(transmitter), usdcAmount);
        bytes memory message = buildMockCCTPV2Message(escrowId);
        vm.prank(relayer);
        receiver.settle(message, "");
    }

    function test_fullLifecycle_createSettleRedeem() public {
        uint256 escrowId = _createEscrow(escrowOwner, ESCROW_AMOUNT);

        assertTrue(escrow.exists(escrowId));

        transmitter.setAmountToMint(ESCROW_AMOUNT);
        usdc.mint(address(transmitter), ESCROW_AMOUNT);
        bytes memory message = buildMockCCTPV2Message(escrowId);

        vm.prank(relayer);
        vm.expectEmit(true, true, false, true);
        emit ICCTPV2EscrowReceiver.EscrowSettled(0, relayer, ESCROW_AMOUNT, ESCROW_AMOUNT);
        receiver.settle(message, "");

        vm.prank(escrowOwner);
        vm.expectEmit(true, false, false, false);
        emit IEscrowEvents.EscrowRedeemed(0);
        escrow.redeem(0);

        assertEq(usdc.balanceOf(escrowOwner), ESCROW_AMOUNT);
    }

    function test_fullLifecycle_incrementalPaymentsUntilFullyPaid() public {
        _createEscrow(escrowOwner, ESCROW_AMOUNT);

        for (uint256 i = 0; i < 4; i++) {
            transmitter.setAmountToMint(ESCROW_AMOUNT / 4);
            usdc.mint(address(transmitter), ESCROW_AMOUNT / 4);
            bytes memory message = buildMockCCTPV2Message(0);
            vm.prank(relayer);
            receiver.settle(message, "");
        }

        vm.prank(escrowOwner);
        vm.expectEmit(true, false, false, false);
        emit IEscrowEvents.EscrowRedeemed(0);
        escrow.redeem(0);

        assertEq(usdc.balanceOf(escrowOwner), ESCROW_AMOUNT);
    }

    function test_multiEscrow_differentOwnersSettleAndRedeem() public {
        _createEscrow(escrowOwner, ESCROW_AMOUNT);
        _createEscrow(secondEscrowOwner, ESCROW_AMOUNT * 2);

        _settle(0, ESCROW_AMOUNT);
        _settle(1, ESCROW_AMOUNT * 2);

        vm.prank(escrowOwner);
        vm.expectEmit(true, false, false, false);
        emit IEscrowEvents.EscrowRedeemed(0);
        escrow.redeem(0);

        vm.prank(secondEscrowOwner);
        vm.expectEmit(true, false, false, false);
        emit IEscrowEvents.EscrowRedeemed(1);
        escrow.redeem(1);

        assertEq(usdc.balanceOf(escrowOwner), ESCROW_AMOUNT);
        assertEq(usdc.balanceOf(secondEscrowOwner), ESCROW_AMOUNT * 2);
    }

    function test_multiEscrow_batchRedemption() public {
        for (uint256 i = 0; i < 3; i++) {
            _createEscrow(escrowOwner, ESCROW_AMOUNT);
        }

        for (uint256 i = 0; i < 3; i++) {
            _settle(i, ESCROW_AMOUNT);
        }

        uint256[] memory ids = new uint256[](3);
        ids[0] = 0;
        ids[1] = 1;
        ids[2] = 2;

        vm.prank(escrowOwner);
        vm.expectEmit(false, false, false, true);
        emit IEscrowEvents.EscrowBatchRedeemed(ids);
        escrow.redeemMultiple(ids);

        assertEq(usdc.balanceOf(escrowOwner), ESCROW_AMOUNT * 3);
    }

    function test_multiEscrow_outOfOrderSettlement() public {
        for (uint256 i = 0; i < 3; i++) {
            _createEscrow(escrowOwner, ESCROW_AMOUNT);
        }

        _settle(2, ESCROW_AMOUNT);
        _settle(0, ESCROW_AMOUNT);
        _settle(1, ESCROW_AMOUNT);

        for (uint256 i = 0; i < 3; i++) {
            vm.prank(escrowOwner);
            vm.expectEmit(true, false, false, false);
            emit IEscrowEvents.EscrowRedeemed(i);
            escrow.redeem(i);
        }

        assertEq(usdc.balanceOf(escrowOwner), ESCROW_AMOUNT * 3);
    }

    function test_crossChain_multipleRelayersSettleSameEscrow() public {
        address relayer2 = makeAddr("relayer2");

        _createEscrow(escrowOwner, ESCROW_AMOUNT);

        transmitter.setAmountToMint(ESCROW_AMOUNT / 2);
        usdc.mint(address(transmitter), ESCROW_AMOUNT / 2);
        bytes memory message = buildMockCCTPV2Message(0);

        vm.prank(relayer);
        vm.expectEmit(true, true, false, true);
        emit ICCTPV2EscrowReceiver.EscrowSettled(0, relayer, ESCROW_AMOUNT / 2, ESCROW_AMOUNT / 2);
        receiver.settle(message, "");

        usdc.mint(address(transmitter), ESCROW_AMOUNT / 2);

        vm.prank(relayer2);
        vm.expectEmit(true, true, false, true);
        emit ICCTPV2EscrowReceiver.EscrowSettled(0, relayer2, ESCROW_AMOUNT / 2, ESCROW_AMOUNT / 2);
        receiver.settle(message, "");

        vm.prank(escrowOwner);
        vm.expectEmit(true, false, false, false);
        emit IEscrowEvents.EscrowRedeemed(0);
        escrow.redeem(0);

        assertEq(usdc.balanceOf(escrowOwner), ESCROW_AMOUNT);
    }

    function test_crossChain_overpaymentStillAllowsRedemption() public {
        _createEscrow(escrowOwner, ESCROW_AMOUNT);

        _settle(0, ESCROW_AMOUNT * 2);

        vm.prank(escrowOwner);
        vm.expectEmit(true, false, false, false);
        emit IEscrowEvents.EscrowRedeemed(0);
        escrow.redeem(0);

        assertEq(usdc.balanceOf(escrowOwner), ESCROW_AMOUNT * 2);
    }

    function test_errorRecovery_failedSettlementDoesNotAffectOtherEscrows() public {
        _createEscrow(escrowOwner, ESCROW_AMOUNT);

        transmitter.setAmountToMint(ESCROW_AMOUNT);
        usdc.mint(address(transmitter), ESCROW_AMOUNT);

        vm.prank(relayer);
        vm.expectRevert();
        receiver.settle(buildMockCCTPV2Message(999), "");

        vm.prank(relayer);
        vm.expectEmit(true, true, false, true);
        emit ICCTPV2EscrowReceiver.EscrowSettled(0, relayer, ESCROW_AMOUNT, ESCROW_AMOUNT);
        receiver.settle(buildMockCCTPV2Message(0), "");

        vm.prank(escrowOwner);
        vm.expectEmit(true, false, false, false);
        emit IEscrowEvents.EscrowRedeemed(0);
        escrow.redeem(0);

        assertEq(usdc.balanceOf(escrowOwner), ESCROW_AMOUNT);
    }

    function test_errorRecovery_cctpMessageFailureRecovery() public {
        _createEscrow(escrowOwner, ESCROW_AMOUNT);

        transmitter.setShouldSucceed(false);

        vm.prank(relayer);
        vm.expectRevert();
        receiver.settle(buildMockCCTPV2Message(0), "");

        transmitter.setShouldSucceed(true);
        transmitter.setAmountToMint(ESCROW_AMOUNT);
        usdc.mint(address(transmitter), ESCROW_AMOUNT);

        vm.prank(relayer);
        vm.expectEmit(true, true, false, true);
        emit ICCTPV2EscrowReceiver.EscrowSettled(0, relayer, ESCROW_AMOUNT, ESCROW_AMOUNT);
        receiver.settle(buildMockCCTPV2Message(0), "");
    }

    function test_accessControl_nonOwnerRedeemRevertsThenOwnerSucceeds() public {
        _createEscrow(escrowOwner, ESCROW_AMOUNT);

        _settle(0, ESCROW_AMOUNT);

        vm.prank(secondEscrowOwner);
        vm.expectRevert(IEscrow.NotOwner.selector);
        escrow.redeem(0);

        vm.prank(escrowOwner);
        vm.expectEmit(true, false, false, false);
        emit IEscrowEvents.EscrowRedeemed(0);
        escrow.redeem(0);

        assertEq(usdc.balanceOf(escrowOwner), ESCROW_AMOUNT);
        assertEq(usdc.balanceOf(secondEscrowOwner), 0);
    }

    function test_accessControl_anyAddressCanRelaySettlement() public {
        _createEscrow(escrowOwner, ESCROW_AMOUNT);

        for (uint256 i = 0; i < 5; i++) {
            address settlerAddr = makeAddr(string(abi.encodePacked("settler", i)));
            transmitter.setAmountToMint(ESCROW_AMOUNT / 5);
            usdc.mint(address(transmitter), ESCROW_AMOUNT / 5);
            bytes memory message = buildMockCCTPV2Message(0);

            vm.prank(settlerAddr);
            vm.expectEmit(true, true, false, true);
            emit ICCTPV2EscrowReceiver.EscrowSettled(0, settlerAddr, ESCROW_AMOUNT / 5, ESCROW_AMOUNT / 5);
            receiver.settle(message, "");
        }
    }

    function _setupCoverageManager() internal returns (MockCoverageManager) {
        vm.startPrank(owner);
        MockCoverageManager mgr = new MockCoverageManager(address(escrow));
        escrow.setCoverageManager(address(mgr));
        vm.stopPrank();
        return mgr;
    }

    function test_recourse_feeFromRecourseDeductedOnRedeem() public {
        address feeRecipient = makeAddr("feeRecipient");
        _createEscrow(escrowOwner, ESCROW_AMOUNT);

        MockCoverageManager mgr = _setupCoverageManager();
        mgr.setFee(0, escrowOwner, FEE_BPS, feeRecipient);

        _settle(0, ESCROW_AMOUNT);

        vm.prank(escrowOwner);
        vm.expectEmit(true, false, false, false);
        emit IEscrowEvents.EscrowRedeemed(0);
        escrow.redeem(0);

        assertEq(usdc.balanceOf(escrowOwner), ESCROW_AMOUNT - FEE_AMOUNT);
        assertEq(usdc.balanceOf(feeRecipient), FEE_AMOUNT);
    }

    function test_recourse_feeZeroedForUnauthorizedHolder() public {
        address feeRecipient = makeAddr("feeRecipient");
        address stranger = makeAddr("stranger");
        _createEscrow(escrowOwner, ESCROW_AMOUNT);

        MockCoverageManager mgr = _setupCoverageManager();
        mgr.setFee(0, stranger, FEE_BPS, feeRecipient);

        _settle(0, ESCROW_AMOUNT);

        vm.prank(escrowOwner);
        escrow.redeem(0);

        assertEq(usdc.balanceOf(escrowOwner), ESCROW_AMOUNT);
        assertEq(usdc.balanceOf(feeRecipient), 0);
    }
}
