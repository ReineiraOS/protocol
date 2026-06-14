// SPDX-License-Identifier: FSL-1.1-ALv2
pragma solidity ^0.8.25;

import {Script, console} from "forge-std/Script.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {ConfidentialEscrow} from "../contracts/core/ConfidentialEscrow.sol";
import {CCTPV2ConfidentialEscrowReceiver} from "../contracts/receivers/CCTPV2ConfidentialEscrowReceiver.sol";

contract DeployConfidentialEscrow is Script {
    address constant USDC_ARBITRUM_SEPOLIA = 0x75faf114eafb1BDbe2F0316DF893fd58CE46AA4d;
    address constant CCTP_TRANSMITTER_ARBITRUM_SEPOLIA = 0xE737e5cEBEEBa77EFE34D4aa090756590b1CE275;

    function run() external {
        uint256 deployerKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerKey);
        address trustedForwarder = vm.envOr("TRUSTED_FORWARDER", address(0));
        address confidentialToken = vm.envAddress("CONFIDENTIAL_TOKEN_ADDRESS");
        address usdcAddr = vm.envOr("USDC_ADDRESS", USDC_ARBITRUM_SEPOLIA);
        address transmitterAddr = vm.envOr("CCTP_TRANSMITTER_ADDRESS", CCTP_TRANSMITTER_ARBITRUM_SEPOLIA);

        vm.startBroadcast(deployerKey);

        ConfidentialEscrow escrowImpl = new ConfidentialEscrow(trustedForwarder);
        ConfidentialEscrow escrow = ConfidentialEscrow(
            address(
                new ERC1967Proxy(
                    address(escrowImpl),
                    abi.encodeCall(ConfidentialEscrow.initialize, (deployer, confidentialToken))
                )
            )
        );
        console.log("ConfidentialEscrow:", address(escrow));

        CCTPV2ConfidentialEscrowReceiver receiverImpl = new CCTPV2ConfidentialEscrowReceiver(trustedForwarder);
        CCTPV2ConfidentialEscrowReceiver receiver = CCTPV2ConfidentialEscrowReceiver(
            address(
                new ERC1967Proxy(
                    address(receiverImpl),
                    abi.encodeCall(
                        CCTPV2ConfidentialEscrowReceiver.initialize,
                        (deployer, transmitterAddr, usdcAddr, confidentialToken, address(escrow))
                    )
                )
            )
        );
        console.log("CCTPV2ConfidentialEscrowReceiver:", address(receiver));

        vm.stopBroadcast();
    }
}
