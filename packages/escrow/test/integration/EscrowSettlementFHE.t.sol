// SPDX-License-Identifier: FSL-1.1-ALv2
pragma solidity ^0.8.25;

import {FHETestBase} from "@reineira-os/shared/test/FHETestBase.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {ConfidentialEscrow} from "../../contracts/core/ConfidentialEscrow.sol";
import {CCTPV2ConfidentialEscrowReceiver} from "../../contracts/receivers/CCTPV2ConfidentialEscrowReceiver.sol";
import {IEscrowEvents} from "@reineira-os/shared/contracts/interfaces/core/IEscrowEvents.sol";
import {ICCTPV2ConfidentialEscrowReceiver} from "../../contracts/interfaces/receivers/ICCTPV2ConfidentialEscrowReceiver.sol";
import {MockUSDC} from "@reineira-os/shared/contracts/mocks/MockUSDC.sol";
import {MockConfidentialToken} from "../../contracts/mocks/MockConfidentialToken.sol";
import {MockCCTPV2MessageTransmitter} from "../../contracts/mocks/MockCCTPV2MessageTransmitter.sol";
import {InEuint64, InEaddress} from "@fhenixprotocol/cofhe-contracts/FHE.sol";

contract EscrowSettlementFHETest is FHETestBase {
    CCTPV2ConfidentialEscrowReceiver public receiver;
    ConfidentialEscrow public escrow;
    MockUSDC public usdc;
    MockConfidentialToken public token;
    MockCCTPV2MessageTransmitter public transmitter;

    address public owner;
    address public escrowOwner;
    address public secondEscrowOwner;
    address public relayer;

    function setUp() public {
        _initFHE();
        owner = _makeAccount("owner");
        escrowOwner = makeAddr("escrowOwner");
        secondEscrowOwner = makeAddr("secondEscrowOwner");
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

    function _createEscrow(address escrowOwnerAddr, uint64 amount) internal returns (uint256) {
        InEaddress memory encOwner = createInEaddress(escrowOwnerAddr, owner);
        InEuint64 memory encAmount = createInEuint64(amount, owner);
        vm.prank(owner);
        return escrow.create(encOwner, encAmount, address(0), "");
    }

    function _settle(uint256 escrowId, uint256 usdcAmount) internal {
        transmitter.setAmountToMint(usdcAmount);
        usdc.mint(address(transmitter), usdcAmount);
        bytes memory message = buildMockCCTPV2Message(escrowId);
        vm.prank(relayer);
        receiver.settle(message, "");
    }

    function _settleAs(uint256 escrowId, uint256 usdcAmount, address settler) internal {
        transmitter.setAmountToMint(usdcAmount);
        usdc.mint(address(transmitter), usdcAmount);
        bytes memory message = buildMockCCTPV2Message(escrowId);
        vm.prank(settler);
        receiver.settle(message, "");
    }

    function test_fullLifecycle_createSettleRedeem() public {
        uint256 escrowId = _createEscrow(escrowOwner, 1000000);

        assertTrue(escrow.exists(escrowId));

        transmitter.setAmountToMint(1000000);
        usdc.mint(address(transmitter), 1000000);
        bytes memory message = buildMockCCTPV2Message(escrowId);

        vm.prank(relayer);
        vm.expectEmit(true, true, false, true);
        emit ICCTPV2ConfidentialEscrowReceiver.EscrowSettled(0, relayer, 1000000, 1000000);
        receiver.settle(message, "");

        vm.prank(escrowOwner);
        vm.expectEmit(true, false, false, false);
        emit IEscrowEvents.EscrowRedeemed(0);
        escrow.redeem(0);
    }

    function test_fullLifecycle_incrementalPaymentsUntilFullyPaid() public {
        _createEscrow(escrowOwner, 1000000);

        for (uint256 i = 0; i < 4; i++) {
            transmitter.setAmountToMint(250000);
            usdc.mint(address(transmitter), 250000);
            bytes memory message = buildMockCCTPV2Message(0);
            vm.prank(relayer);
            receiver.settle(message, "");
        }

        vm.prank(escrowOwner);
        vm.expectEmit(true, false, false, false);
        emit IEscrowEvents.EscrowRedeemed(0);
        escrow.redeem(0);
    }

    function test_multiEscrow_differentOwnersSettleAndRedeem() public {
        _createEscrow(escrowOwner, 1000000);
        _createEscrow(secondEscrowOwner, 2000000);

        _settle(0, 1000000);
        _settle(1, 2000000);

        vm.prank(escrowOwner);
        vm.expectEmit(true, false, false, false);
        emit IEscrowEvents.EscrowRedeemed(0);
        escrow.redeem(0);

        vm.prank(secondEscrowOwner);
        vm.expectEmit(true, false, false, false);
        emit IEscrowEvents.EscrowRedeemed(1);
        escrow.redeem(1);
    }

    function test_multiEscrow_batchRedemption() public {
        for (uint256 i = 0; i < 3; i++) {
            _createEscrow(escrowOwner, 1000000);
        }

        for (uint256 i = 0; i < 3; i++) {
            _settle(i, 1000000);
        }

        uint256[] memory ids = new uint256[](3);
        ids[0] = 0;
        ids[1] = 1;
        ids[2] = 2;

        vm.prank(escrowOwner);
        vm.expectEmit(false, false, false, true);
        emit IEscrowEvents.EscrowBatchRedeemed(ids);
        escrow.redeemMultiple(ids);
    }

    function test_multiEscrow_outOfOrderSettlement() public {
        for (uint256 i = 0; i < 3; i++) {
            _createEscrow(escrowOwner, 1000000);
        }

        _settle(2, 1000000);
        _settle(0, 1000000);
        _settle(1, 1000000);

        for (uint256 i = 0; i < 3; i++) {
            vm.prank(escrowOwner);
            vm.expectEmit(true, false, false, false);
            emit IEscrowEvents.EscrowRedeemed(i);
            escrow.redeem(i);
        }
    }

    function test_crossChain_multipleRelayersSettleSameEscrow() public {
        address relayer2 = makeAddr("relayer2");

        _createEscrow(escrowOwner, 1000000);

        transmitter.setAmountToMint(500000);
        usdc.mint(address(transmitter), 500000);
        bytes memory message = buildMockCCTPV2Message(0);

        vm.prank(relayer);
        vm.expectEmit(true, true, false, true);
        emit ICCTPV2ConfidentialEscrowReceiver.EscrowSettled(0, relayer, 500000, 500000);
        receiver.settle(message, "");

        usdc.mint(address(transmitter), 500000);

        vm.prank(relayer2);
        vm.expectEmit(true, true, false, true);
        emit ICCTPV2ConfidentialEscrowReceiver.EscrowSettled(0, relayer2, 500000, 500000);
        receiver.settle(message, "");

        vm.prank(escrowOwner);
        vm.expectEmit(true, false, false, false);
        emit IEscrowEvents.EscrowRedeemed(0);
        escrow.redeem(0);
    }

    function test_crossChain_overpaymentStillAllowsRedemption() public {
        _createEscrow(escrowOwner, 1000000);

        _settle(0, 2000000);

        vm.prank(escrowOwner);
        vm.expectEmit(true, false, false, false);
        emit IEscrowEvents.EscrowRedeemed(0);
        escrow.redeem(0);
    }

    function test_errorRecovery_failedSettlementDoesNotAffectOtherEscrows() public {
        _createEscrow(escrowOwner, 1000000);

        transmitter.setAmountToMint(1000000);
        usdc.mint(address(transmitter), 1000000);

        vm.prank(relayer);
        vm.expectRevert();
        receiver.settle(buildMockCCTPV2Message(999), "");

        vm.prank(relayer);
        vm.expectEmit(true, true, false, false);
        emit ICCTPV2ConfidentialEscrowReceiver.EscrowSettled(0, relayer, 1000000, 1000000);
        receiver.settle(buildMockCCTPV2Message(0), "");

        vm.prank(escrowOwner);
        vm.expectEmit(true, false, false, false);
        emit IEscrowEvents.EscrowRedeemed(0);
        escrow.redeem(0);
    }

    function test_errorRecovery_cctpMessageFailureRecovery() public {
        _createEscrow(escrowOwner, 1000000);

        transmitter.setShouldSucceed(false);

        vm.prank(relayer);
        vm.expectRevert();
        receiver.settle(buildMockCCTPV2Message(0), "");

        transmitter.setShouldSucceed(true);
        transmitter.setAmountToMint(1000000);
        usdc.mint(address(transmitter), 1000000);

        vm.prank(relayer);
        vm.expectEmit(true, true, false, false);
        emit ICCTPV2ConfidentialEscrowReceiver.EscrowSettled(0, relayer, 1000000, 1000000);
        receiver.settle(buildMockCCTPV2Message(0), "");
    }

    function test_accessControl_nonOwnerRedeemDoesNotPreventOwnerRedeem() public {
        _createEscrow(escrowOwner, 1000000);

        _settle(0, 1000000);

        vm.prank(secondEscrowOwner);
        escrow.redeem(0);

        vm.prank(escrowOwner);
        vm.expectEmit(true, false, false, false);
        emit IEscrowEvents.EscrowRedeemed(0);
        escrow.redeem(0);
    }

    function test_accessControl_anyAddressCanRelaySettlement() public {
        _createEscrow(escrowOwner, 1000000);

        for (uint256 i = 0; i < 5; i++) {
            address settlerAddr = makeAddr(string(abi.encodePacked("settler", i)));
            transmitter.setAmountToMint(200000);
            usdc.mint(address(transmitter), 200000);
            bytes memory message = buildMockCCTPV2Message(0);

            vm.prank(settlerAddr);
            vm.expectEmit(true, true, false, true);
            emit ICCTPV2ConfidentialEscrowReceiver.EscrowSettled(0, settlerAddr, 200000, 200000);
            receiver.settle(message, "");
        }
    }
}
