// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {CCTPV2Forwarder} from "../../contracts/receivers/CCTPV2Forwarder.sol";
import {MockCCTPV2MessageTransmitter} from "../../contracts/mocks/MockCCTPV2MessageTransmitter.sol";
import {MockUSDC} from "@reineira-os/shared/contracts/mocks/MockUSDC.sol";
import {ICCTPV2Forwarder} from "../../contracts/interfaces/receivers/ICCTPV2Forwarder.sol";
import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";

contract CCTPV2ForwarderTest is Test {
    CCTPV2Forwarder forwarder;
    MockUSDC usdc;
    MockCCTPV2MessageTransmitter transmitter;

    address owner;
    address recipient;
    address relayer;

    function setUp() public {
        owner = makeAddr("owner");
        recipient = makeAddr("recipient");
        relayer = makeAddr("relayer");

        usdc = new MockUSDC();
        transmitter = new MockCCTPV2MessageTransmitter(address(usdc));

        CCTPV2Forwarder impl = new CCTPV2Forwarder(address(0));
        bytes memory initData = abi.encodeCall(
            CCTPV2Forwarder.initialize,
            (owner, address(transmitter), address(usdc))
        );
        ERC1967Proxy proxy = new ERC1967Proxy(address(impl), initData);
        forwarder = CCTPV2Forwarder(address(proxy));

        usdc.mint(address(transmitter), 1_000_000e6);
    }

    function test_deploy_correctParams() public view {
        assertEq(address(forwarder.cctpV2Transmitter()), address(transmitter));
        assertEq(address(forwarder.usdc()), address(usdc));
    }

    function test_deploy_correctOwner() public view {
        assertEq(forwarder.owner(), owner);
    }

    function test_deploy_revertInvalidTransmitter() public {
        CCTPV2Forwarder impl = new CCTPV2Forwarder(address(0));
        bytes memory initData = abi.encodeCall(CCTPV2Forwarder.initialize, (owner, address(0), address(usdc)));
        vm.expectRevert(ICCTPV2Forwarder.InvalidTransmitter.selector);
        new ERC1967Proxy(address(impl), initData);
    }

    function test_deploy_revertInvalidUsdc() public {
        CCTPV2Forwarder impl = new CCTPV2Forwarder(address(0));
        bytes memory initData = abi.encodeCall(CCTPV2Forwarder.initialize, (owner, address(transmitter), address(0)));
        vm.expectRevert(ICCTPV2Forwarder.InvalidUsdc.selector);
        new ERC1967Proxy(address(impl), initData);
    }

    function test_deploy_revertReinitialization() public {
        vm.expectRevert(Initializable.InvalidInitialization.selector);
        forwarder.initialize(owner, address(transmitter), address(usdc));
    }

    function test_receiveAndForward_forwardsToRecipient() public {
        uint256 amount = 100e6;
        transmitter.setAmountToMint(amount);

        bytes memory message = abi.encode(uint256(1));
        bytes memory attestation = "";

        uint256 balanceBefore = usdc.balanceOf(recipient);
        forwarder.receiveAndForward(message, attestation, recipient);
        uint256 balanceAfter = usdc.balanceOf(recipient);

        assertEq(balanceAfter - balanceBefore, amount);
    }

    function test_receiveAndForward_emitMessageReceived() public {
        uint256 amount = 50e6;
        transmitter.setAmountToMint(amount);

        bytes memory message = abi.encode(uint256(1));
        bytes memory attestation = "";
        bytes32 messageHash = keccak256(message);

        vm.expectEmit(true, true, false, true);
        emit ICCTPV2Forwarder.MessageReceived(messageHash, recipient, amount);

        forwarder.receiveAndForward(message, attestation, recipient);
    }

    function test_receiveAndForward_emitTokensForwarded() public {
        uint256 amount = 75e6;
        transmitter.setAmountToMint(amount);

        bytes memory message = abi.encode(uint256(1));
        bytes memory attestation = "";

        vm.expectEmit(true, false, false, true);
        emit ICCTPV2Forwarder.TokensForwarded(recipient, amount);

        forwarder.receiveAndForward(message, attestation, recipient);
    }

    function test_receiveAndForward_revertZeroAddress() public {
        transmitter.setAmountToMint(100e6);

        bytes memory message = abi.encode(uint256(1));
        bytes memory attestation = "";

        vm.expectRevert(ICCTPV2Forwarder.ZeroAddress.selector);
        forwarder.receiveAndForward(message, attestation, address(0));
    }

    function test_receiveAndForward_revertMessageReceiveFailed() public {
        transmitter.setShouldSucceed(false);

        bytes memory message = abi.encode(uint256(1));
        bytes memory attestation = "";

        vm.expectRevert(ICCTPV2Forwarder.MessageReceiveFailed.selector);
        forwarder.receiveAndForward(message, attestation, recipient);
    }

    function test_receiveAndForward_revertZeroAmount() public {
        transmitter.setAmountToMint(0);

        bytes memory message = abi.encode(uint256(1));
        bytes memory attestation = "";

        vm.expectRevert(ICCTPV2Forwarder.ZeroAmount.selector);
        forwarder.receiveAndForward(message, attestation, recipient);
    }

    function test_receiveAndForward_returnCorrectAmount() public {
        uint256 amount = 200e6;
        transmitter.setAmountToMint(amount);

        bytes memory message = abi.encode(uint256(1));
        bytes memory attestation = "";

        uint256 returned = forwarder.receiveAndForward(message, attestation, recipient);
        assertEq(returned, amount);
    }

    function test_receiveAndForward_allowAnyoneToCall() public {
        uint256 amount = 100e6;
        transmitter.setAmountToMint(amount);

        bytes memory message = abi.encode(uint256(1));
        bytes memory attestation = "";

        uint256 balanceBefore = usdc.balanceOf(recipient);

        vm.prank(relayer);
        forwarder.receiveAndForward(message, attestation, recipient);

        uint256 balanceAfter = usdc.balanceOf(recipient);
        assertEq(balanceAfter - balanceBefore, amount);
    }
}
