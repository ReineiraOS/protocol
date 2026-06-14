// SPDX-License-Identifier: FSL-1.1-ALv2
pragma solidity ^0.8.25;

import {Script, console} from "forge-std/Script.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {Escrow} from "../contracts/core/Escrow.sol";
import {CCTPV2EscrowReceiver} from "../contracts/receivers/CCTPV2EscrowReceiver.sol";

contract DeployEscrow is Script {
    address constant USDC_ARBITRUM_SEPOLIA = 0x75faf114eafb1BDbe2F0316DF893fd58CE46AA4d;
    address constant CCTP_TRANSMITTER_ARBITRUM_SEPOLIA = 0xE737e5cEBEEBa77EFE34D4aa090756590b1CE275;

    function run() external {
        uint256 deployerKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerKey);
        address trustedForwarder = vm.envOr("TRUSTED_FORWARDER", address(0));
        address usdcAddr = vm.envOr("USDC_ADDRESS", USDC_ARBITRUM_SEPOLIA);
        address transmitterAddr = vm.envOr("CCTP_TRANSMITTER_ADDRESS", CCTP_TRANSMITTER_ARBITRUM_SEPOLIA);

        vm.startBroadcast(deployerKey);

        Escrow escrowImpl = new Escrow(trustedForwarder);
        Escrow escrow = Escrow(
            address(new ERC1967Proxy(address(escrowImpl), abi.encodeCall(Escrow.initialize, (deployer, usdcAddr))))
        );
        console.log("Escrow:", address(escrow));

        CCTPV2EscrowReceiver receiverImpl = new CCTPV2EscrowReceiver(trustedForwarder);
        CCTPV2EscrowReceiver receiver = CCTPV2EscrowReceiver(
            address(
                new ERC1967Proxy(
                    address(receiverImpl),
                    abi.encodeCall(
                        CCTPV2EscrowReceiver.initialize,
                        (deployer, transmitterAddr, usdcAddr, address(escrow))
                    )
                )
            )
        );
        console.log("CCTPV2EscrowReceiver:", address(receiver));

        vm.stopBroadcast();
    }
}
