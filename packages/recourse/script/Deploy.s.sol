// SPDX-License-Identifier: FSL-1.1-ALv2
pragma solidity ^0.8.25;

import {Script, console} from "forge-std/Script.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {PolicyRegistry} from "../contracts/core/PolicyRegistry.sol";
import {PoolFactory} from "../contracts/core/PoolFactory.sol";
import {RecoursePool} from "../contracts/core/RecoursePool.sol";
import {CoverageManager} from "../contracts/core/CoverageManager.sol";

contract DeployRecourse is Script {
    address constant USDC_ARBITRUM_SEPOLIA = 0x75faf114eafb1BDbe2F0316DF893fd58CE46AA4d;

    function run() external {
        uint256 deployerKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerKey);
        address trustedForwarder = vm.envOr("TRUSTED_FORWARDER", address(0));
        address escrowAddress = vm.envAddress("ESCROW_ADDRESS");
        address usdcAddr = vm.envOr("USDC_ADDRESS", USDC_ARBITRUM_SEPOLIA);

        vm.startBroadcast(deployerKey);

        PolicyRegistry policyRegistryImpl = new PolicyRegistry(trustedForwarder);
        PolicyRegistry policyRegistry = PolicyRegistry(
            address(
                new ERC1967Proxy(address(policyRegistryImpl), abi.encodeCall(PolicyRegistry.initialize, (deployer)))
            )
        );
        console.log("PolicyRegistry:", address(policyRegistry));

        RecoursePool poolImpl = new RecoursePool(trustedForwarder);
        console.log("RecoursePool (impl):", address(poolImpl));

        CoverageManager coverageManagerImpl = new CoverageManager(trustedForwarder);
        CoverageManager coverageManager = CoverageManager(
            address(
                new ERC1967Proxy(
                    address(coverageManagerImpl),
                    abi.encodeCall(CoverageManager.initialize, (deployer, deployer))
                )
            )
        );
        console.log("CoverageManager:", address(coverageManager));

        coverageManager.setEscrow(escrowAddress);

        PoolFactory poolFactoryImpl = new PoolFactory(trustedForwarder);
        PoolFactory poolFactory = PoolFactory(
            address(
                new ERC1967Proxy(
                    address(poolFactoryImpl),
                    abi.encodeCall(
                        PoolFactory.initialize,
                        (deployer, address(poolImpl), address(coverageManager), address(policyRegistry))
                    )
                )
            )
        );
        console.log("PoolFactory:", address(poolFactory));

        coverageManager.setPoolFactory(address(poolFactory));
        poolFactory.addAllowedToken(usdcAddr);

        vm.stopBroadcast();
    }
}
