// SPDX-License-Identifier: FSL-1.1-ALv2
pragma solidity ^0.8.25;

import {FHETestBase} from "@reineira-os/shared/test/FHETestBase.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {CCTPV2ConfidentialEscrowReceiver} from "../../contracts/receivers/CCTPV2ConfidentialEscrowReceiver.sol";
import {ConfidentialEscrow} from "../../contracts/core/ConfidentialEscrow.sol";
import {MockUSDC} from "@reineira-os/shared/contracts/mocks/MockUSDC.sol";
import {MockConfidentialToken} from "../../contracts/mocks/MockConfidentialToken.sol";
import {MockCCTPV2MessageTransmitter} from "../../contracts/mocks/MockCCTPV2MessageTransmitter.sol";

contract CCTPV2ConfidentialEscrowReceiverTest is FHETestBase {
    CCTPV2ConfidentialEscrowReceiver public receiver;
    ConfidentialEscrow public escrow;
    MockUSDC public usdc;
    MockConfidentialToken public token;
    MockCCTPV2MessageTransmitter public transmitter;

    address public owner;
    address public relayer;

    function setUp() public {
        _initFHE();
        owner = makeAddr("owner");
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

    function _deployReceiverWithParams(
        address owner_,
        address transmitter_,
        address usdc_,
        address confidentialUsdc_,
        address escrow_
    ) internal returns (CCTPV2ConfidentialEscrowReceiver) {
        CCTPV2ConfidentialEscrowReceiver impl = new CCTPV2ConfidentialEscrowReceiver(address(0));
        return
            CCTPV2ConfidentialEscrowReceiver(
                address(
                    new ERC1967Proxy(
                        address(impl),
                        abi.encodeCall(
                            CCTPV2ConfidentialEscrowReceiver.initialize,
                            (owner_, transmitter_, usdc_, confidentialUsdc_, escrow_)
                        )
                    )
                )
            );
    }

    // --- Deployment ---

    function test_deployment_setsCorrectStorageVariables() public view {
        assertEq(address(receiver.cctpV2Transmitter()), address(transmitter));
        assertEq(address(receiver.usdc()), address(usdc));
        assertEq(address(receiver.confidentialUsdc()), address(token));
        assertEq(address(receiver.escrow()), address(escrow));
    }

    function test_deployment_revertsOnZeroTransmitter() public {
        CCTPV2ConfidentialEscrowReceiver impl = new CCTPV2ConfidentialEscrowReceiver(address(0));
        bytes memory initData = abi.encodeCall(
            CCTPV2ConfidentialEscrowReceiver.initialize,
            (owner, address(0), address(usdc), address(token), address(escrow))
        );
        vm.expectRevert();
        new ERC1967Proxy(address(impl), initData);
    }

    function test_deployment_revertsOnZeroUsdc() public {
        CCTPV2ConfidentialEscrowReceiver impl = new CCTPV2ConfidentialEscrowReceiver(address(0));
        bytes memory initData = abi.encodeCall(
            CCTPV2ConfidentialEscrowReceiver.initialize,
            (owner, address(transmitter), address(0), address(token), address(escrow))
        );
        vm.expectRevert();
        new ERC1967Proxy(address(impl), initData);
    }

    function test_deployment_revertsOnZeroConfidentialUsdc() public {
        CCTPV2ConfidentialEscrowReceiver impl = new CCTPV2ConfidentialEscrowReceiver(address(0));
        bytes memory initData = abi.encodeCall(
            CCTPV2ConfidentialEscrowReceiver.initialize,
            (owner, address(transmitter), address(usdc), address(0), address(escrow))
        );
        vm.expectRevert();
        new ERC1967Proxy(address(impl), initData);
    }

    function test_deployment_revertsOnZeroEscrow() public {
        CCTPV2ConfidentialEscrowReceiver impl = new CCTPV2ConfidentialEscrowReceiver(address(0));
        bytes memory initData = abi.encodeCall(
            CCTPV2ConfidentialEscrowReceiver.initialize,
            (owner, address(transmitter), address(usdc), address(token), address(0))
        );
        vm.expectRevert();
        new ERC1967Proxy(address(impl), initData);
    }

    // --- buildHookData ---

    function test_buildHookData_encodesEscrowId() public view {
        uint256 escrowId = 42;
        bytes memory hookData = receiver.buildHookData(escrowId);
        assertEq(hookData, abi.encode(escrowId));
    }

    function test_buildHookData_encodesZeroId() public view {
        bytes memory hookData = receiver.buildHookData(0);
        assertEq(hookData, abi.encode(uint256(0)));
    }

    function test_buildHookData_encodesMaxUint256() public view {
        uint256 maxId = type(uint256).max;
        bytes memory hookData = receiver.buildHookData(maxId);
        assertEq(hookData, abi.encode(maxId));
    }

    // --- settle ---

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
        transmitter.setAmountToMint(1000000);
        usdc.mint(address(transmitter), 1000000);
        bytes memory message = buildMockCCTPV2Message(999);

        vm.prank(relayer);
        vm.expectRevert();
        receiver.settle(message, "");
    }

    function test_settle_revertsOnMalformedMessage() public {
        transmitter.setAmountToMint(1000000);
        usdc.mint(address(transmitter), 1000000);
        bytes memory shortMessage = new bytes(100);

        vm.prank(relayer);
        vm.expectRevert();
        receiver.settle(shortMessage, "");
    }
}
