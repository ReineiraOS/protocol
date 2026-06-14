// SPDX-License-Identifier: FSL-1.1-ALv2
pragma solidity ^0.8.25;

import {Test} from "forge-std/Test.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {CCTPV2EscrowReceiver} from "../../contracts/receivers/CCTPV2EscrowReceiver.sol";
import {ICCTPV2EscrowReceiver} from "../../contracts/interfaces/receivers/ICCTPV2EscrowReceiver.sol";
import {Escrow} from "../../contracts/core/Escrow.sol";
import {MockUSDC} from "@reineira-os/shared/contracts/mocks/MockUSDC.sol";
import {MockCCTPV2MessageTransmitter} from "../../contracts/mocks/MockCCTPV2MessageTransmitter.sol";

contract CCTPV2EscrowReceiverTest is Test {
    CCTPV2EscrowReceiver public receiver;
    Escrow public escrow;
    MockUSDC public usdc;
    MockCCTPV2MessageTransmitter public transmitter;

    address public owner;
    address public relayer;
    address public escrowOwner;

    uint256 constant ESCROW_AMOUNT = 1000e6;

    function setUp() public {
        owner = makeAddr("owner");
        relayer = makeAddr("relayer");
        escrowOwner = makeAddr("escrowOwner");

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

    function test_deployment_setsCorrectStorageVariables() public view {
        assertEq(address(receiver.cctpV2Transmitter()), address(transmitter));
        assertEq(address(receiver.usdc()), address(usdc));
        assertEq(address(receiver.escrow()), address(escrow));
    }

    function test_deployment_revertsOnZeroTransmitter() public {
        CCTPV2EscrowReceiver impl = new CCTPV2EscrowReceiver(address(0));
        vm.expectRevert();
        new ERC1967Proxy(
            address(impl),
            abi.encodeCall(CCTPV2EscrowReceiver.initialize, (owner, address(0), address(usdc), address(escrow)))
        );
    }

    function test_deployment_revertsOnZeroUsdc() public {
        CCTPV2EscrowReceiver impl = new CCTPV2EscrowReceiver(address(0));
        vm.expectRevert();
        new ERC1967Proxy(
            address(impl),
            abi.encodeCall(CCTPV2EscrowReceiver.initialize, (owner, address(transmitter), address(0), address(escrow)))
        );
    }

    function test_deployment_revertsOnZeroEscrow() public {
        CCTPV2EscrowReceiver impl = new CCTPV2EscrowReceiver(address(0));
        vm.expectRevert();
        new ERC1967Proxy(
            address(impl),
            abi.encodeCall(CCTPV2EscrowReceiver.initialize, (owner, address(transmitter), address(usdc), address(0)))
        );
    }

    function test_buildHookData_encodesEscrowId() public view {
        assertEq(receiver.buildHookData(42), abi.encode(uint256(42)));
    }

    function test_settle_fundsEscrowWithReceivedUsdc() public {
        vm.prank(owner);
        escrow.create(escrowOwner, ESCROW_AMOUNT, address(0), "");

        transmitter.setAmountToMint(ESCROW_AMOUNT);
        bytes memory message = buildMockCCTPV2Message(0);

        vm.prank(relayer);
        receiver.settle(message, "");

        assertEq(escrow.getPaidAmount(0), ESCROW_AMOUNT);
    }

    function test_settle_revertsWhenMessageReceiveFails() public {
        transmitter.setShouldSucceed(false);
        bytes memory message = buildMockCCTPV2Message(0);

        vm.prank(relayer);
        vm.expectRevert();
        receiver.settle(message, "");
    }

    function test_settle_revertsWhenNoUsdcReceived() public {
        transmitter.setAmountToMint(0);
        bytes memory message = buildMockCCTPV2Message(0);

        vm.prank(relayer);
        vm.expectRevert();
        receiver.settle(message, "");
    }

    function test_settle_revertsWhenEscrowDoesNotExist() public {
        transmitter.setAmountToMint(ESCROW_AMOUNT);
        bytes memory message = buildMockCCTPV2Message(999);

        vm.prank(relayer);
        vm.expectRevert();
        receiver.settle(message, "");
    }

    function test_settle_revertsOnMalformedMessage() public {
        transmitter.setAmountToMint(ESCROW_AMOUNT);
        bytes memory shortMessage = new bytes(100);

        vm.prank(relayer);
        vm.expectRevert();
        receiver.settle(shortMessage, "");
    }

    function test_settle_emitsEscrowSettledEvent() public {
        vm.prank(owner);
        escrow.create(escrowOwner, ESCROW_AMOUNT, address(0), "");

        transmitter.setAmountToMint(ESCROW_AMOUNT);
        bytes memory message = buildMockCCTPV2Message(0);

        vm.prank(relayer);
        vm.expectEmit(true, true, false, true);
        emit ICCTPV2EscrowReceiver.EscrowSettled(0, relayer, ESCROW_AMOUNT, ESCROW_AMOUNT);
        receiver.settle(message, "");
    }
}
