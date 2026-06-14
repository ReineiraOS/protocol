// SPDX-License-Identifier: FSL-1.1-ALv2
pragma solidity ^0.8.25;

import {FHETestBase} from "@reineira-os/shared/test/FHETestBase.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {ConfidentialEscrow} from "../../contracts/core/ConfidentialEscrow.sol";
import {CCTPV2ConfidentialEscrowReceiver} from "../../contracts/receivers/CCTPV2ConfidentialEscrowReceiver.sol";
import {MockUSDC} from "@reineira-os/shared/contracts/mocks/MockUSDC.sol";
import {MockConfidentialToken} from "../../contracts/mocks/MockConfidentialToken.sol";
import {MockCCTPV2MessageTransmitter} from "../../contracts/mocks/MockCCTPV2MessageTransmitter.sol";
import {IEscrowEvents} from "@reineira-os/shared/contracts/interfaces/core/IEscrowEvents.sol";
import {ICCTPV2ConfidentialEscrowReceiver} from "../../contracts/interfaces/receivers/ICCTPV2ConfidentialEscrowReceiver.sol";
import {InEuint64, InEaddress} from "@fhenixprotocol/cofhe-contracts/FHE.sol";

contract CCTPV2EscrowReceiverFHETest is FHETestBase {
    CCTPV2ConfidentialEscrowReceiver public receiver;
    ConfidentialEscrow public escrow;
    MockUSDC public usdc;
    MockConfidentialToken public token;
    MockCCTPV2MessageTransmitter public transmitter;

    address public owner;
    address public escrowOwner;
    address public relayer;

    uint64 constant ESCROW_AMOUNT = 1000000;
    uint256 constant USDC_AMOUNT = 1000000;

    function setUp() public {
        _initFHE();
        owner = _makeAccount("owner");
        escrowOwner = makeAddr("escrowOwner");
        relayer = makeAddr("relayer");

        vm.startPrank(owner);

        usdc = new MockUSDC();
        transmitter = new MockCCTPV2MessageTransmitter(address(usdc));
        token = new MockConfidentialToken();

        ConfidentialEscrow escrowImpl = new ConfidentialEscrow(address(0));
        escrow = ConfidentialEscrow(
            address(
                new ERC1967Proxy(
                    address(escrowImpl),
                    abi.encodeCall(ConfidentialEscrow.initialize, (owner, address(token)))
                )
            )
        );

        CCTPV2ConfidentialEscrowReceiver receiverImpl = new CCTPV2ConfidentialEscrowReceiver(address(0));
        receiver = CCTPV2ConfidentialEscrowReceiver(
            address(
                new ERC1967Proxy(
                    address(receiverImpl),
                    abi.encodeCall(
                        CCTPV2ConfidentialEscrowReceiver.initialize,
                        (owner, address(transmitter), address(usdc), address(token), address(escrow))
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

    function _createEscrow(address escrowOwner_, uint64 amount) internal {
        InEaddress memory encOwner = createInEaddress(escrowOwner_, owner);
        InEuint64 memory encAmount = createInEuint64(amount, owner);
        vm.prank(owner);
        escrow.create(encOwner, encAmount, address(0), "");
    }

    function test_settleEscrowViaCCTPBridge() public {
        _createEscrow(escrowOwner, ESCROW_AMOUNT);
        transmitter.setAmountToMint(USDC_AMOUNT);
        bytes memory message = buildMockCCTPV2Message(0);

        vm.prank(relayer);
        receiver.settle(message, "");

        assertTrue(escrow.exists(0));
    }

    function test_settleEmitsEscrowSettledWithCorrectParameters() public {
        _createEscrow(escrowOwner, ESCROW_AMOUNT);
        transmitter.setAmountToMint(USDC_AMOUNT);
        bytes memory message = buildMockCCTPV2Message(0);

        vm.prank(relayer);
        vm.expectEmit(true, true, false, true);
        emit ICCTPV2ConfidentialEscrowReceiver.EscrowSettled(0, relayer, USDC_AMOUNT, ESCROW_AMOUNT);
        receiver.settle(message, "");
    }

    function test_settleEmitsEscrowFundedOnEscrow() public {
        _createEscrow(escrowOwner, ESCROW_AMOUNT);
        transmitter.setAmountToMint(USDC_AMOUNT);
        bytes memory message = buildMockCCTPV2Message(0);

        vm.prank(relayer);
        vm.expectEmit(true, true, false, false);
        emit IEscrowEvents.EscrowFunded(0, address(receiver));
        receiver.settle(message, "");
    }

    function test_escrowOwnerCanRedeemAfterSettlement() public {
        _createEscrow(escrowOwner, ESCROW_AMOUNT);
        transmitter.setAmountToMint(USDC_AMOUNT);
        bytes memory message = buildMockCCTPV2Message(0);

        vm.prank(relayer);
        receiver.settle(message, "");

        vm.prank(escrowOwner);
        vm.expectEmit(true, false, false, false);
        emit IEscrowEvents.EscrowRedeemed(0);
        escrow.redeem(0);
    }

    function test_settleHandlesPartialPayments() public {
        _createEscrow(escrowOwner, ESCROW_AMOUNT);
        uint256 partialAmount = USDC_AMOUNT / 2;
        transmitter.setAmountToMint(partialAmount);
        bytes memory message = buildMockCCTPV2Message(0);

        vm.prank(relayer);
        vm.expectEmit(true, true, false, true);
        emit ICCTPV2ConfidentialEscrowReceiver.EscrowSettled(0, relayer, partialAmount, uint64(ESCROW_AMOUNT / 2));
        receiver.settle(message, "");
    }

    function test_settleHandlesMultiplePartialPayments() public {
        _createEscrow(escrowOwner, ESCROW_AMOUNT);
        uint256 partialAmount = USDC_AMOUNT / 4;
        transmitter.setAmountToMint(partialAmount);
        bytes memory message = buildMockCCTPV2Message(0);

        vm.prank(relayer);
        receiver.settle(message, "");
        vm.prank(relayer);
        receiver.settle(message, "");
        vm.prank(relayer);
        receiver.settle(message, "");
        vm.prank(relayer);
        receiver.settle(message, "");

        vm.prank(escrowOwner);
        vm.expectEmit(true, false, false, false);
        emit IEscrowEvents.EscrowRedeemed(0);
        escrow.redeem(0);
    }

    function test_settleMultipleDifferentEscrows() public {
        _createEscrow(escrowOwner, ESCROW_AMOUNT);
        _createEscrow(escrowOwner, 2000000);

        transmitter.setAmountToMint(USDC_AMOUNT);
        bytes memory message0 = buildMockCCTPV2Message(0);
        vm.prank(relayer);
        receiver.settle(message0, "");

        transmitter.setAmountToMint(2000000);
        bytes memory message1 = buildMockCCTPV2Message(1);
        vm.prank(relayer);
        receiver.settle(message1, "");

        uint256[] memory ids = new uint256[](2);
        ids[0] = 0;
        ids[1] = 1;

        vm.prank(escrowOwner);
        vm.expectEmit(false, false, false, true);
        emit IEscrowEvents.EscrowBatchRedeemed(ids);
        escrow.redeemMultiple(ids);
    }

    function test_settleHandlesOverpaymentGracefully() public {
        _createEscrow(escrowOwner, ESCROW_AMOUNT);
        uint256 overpayment = USDC_AMOUNT * 2;
        transmitter.setAmountToMint(overpayment);
        bytes memory message = buildMockCCTPV2Message(0);

        vm.prank(relayer);
        vm.expectEmit(true, true, false, true);
        emit ICCTPV2ConfidentialEscrowReceiver.EscrowSettled(0, relayer, overpayment, uint64(ESCROW_AMOUNT * 2));
        receiver.settle(message, "");

        vm.prank(escrowOwner);
        vm.expectEmit(true, false, false, false);
        emit IEscrowEvents.EscrowRedeemed(0);
        escrow.redeem(0);
    }

    function test_settleAllowsAnyRelayer() public {
        _createEscrow(escrowOwner, ESCROW_AMOUNT);
        address randomRelayer = makeAddr("randomRelayer");
        transmitter.setAmountToMint(USDC_AMOUNT);
        bytes memory message = buildMockCCTPV2Message(0);

        vm.prank(randomRelayer);
        vm.expectEmit(true, true, false, true);
        emit ICCTPV2ConfidentialEscrowReceiver.EscrowSettled(0, randomRelayer, USDC_AMOUNT, ESCROW_AMOUNT);
        receiver.settle(message, "");
    }

    function test_settleRevertsForNonExistentEscrow() public {
        transmitter.setAmountToMint(USDC_AMOUNT);
        bytes memory message = buildMockCCTPV2Message(999);

        vm.prank(relayer);
        vm.expectRevert();
        receiver.settle(message, "");
    }

    function test_settleRevertsWhenCCTPReceiveFails() public {
        _createEscrow(escrowOwner, ESCROW_AMOUNT);
        transmitter.setShouldSucceed(false);
        bytes memory message = buildMockCCTPV2Message(0);

        vm.prank(relayer);
        vm.expectRevert();
        receiver.settle(message, "");
    }

    function test_settleRevertsWhenNoUSDCReceived() public {
        _createEscrow(escrowOwner, ESCROW_AMOUNT);
        transmitter.setAmountToMint(0);
        bytes memory message = buildMockCCTPV2Message(0);

        vm.prank(relayer);
        vm.expectRevert();
        receiver.settle(message, "");
    }

    function test_settleConvertsUSDCToConfidentialAmountCorrectly() public {
        _createEscrow(escrowOwner, ESCROW_AMOUNT);
        transmitter.setAmountToMint(1000000);
        bytes memory message = buildMockCCTPV2Message(0);

        vm.prank(relayer);
        vm.expectEmit(true, true, false, true);
        emit ICCTPV2ConfidentialEscrowReceiver.EscrowSettled(0, relayer, 1000000, 1000000);
        receiver.settle(message, "");
    }

    function test_settleHandlesExactOneToOneConversionWithRateOne() public {
        _createEscrow(escrowOwner, 500000);
        transmitter.setAmountToMint(500000);
        bytes memory message = buildMockCCTPV2Message(0);

        vm.prank(relayer);
        vm.expectEmit(true, true, false, true);
        emit ICCTPV2ConfidentialEscrowReceiver.EscrowSettled(0, relayer, 500000, 500000);
        receiver.settle(message, "");
    }
}
