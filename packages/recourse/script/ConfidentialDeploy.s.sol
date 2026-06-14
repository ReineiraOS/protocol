// SPDX-License-Identifier: FSL-1.1-ALv2
pragma solidity ^0.8.25;

import {Script, console} from "forge-std/Script.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {ConfidentialPolicyRegistry} from "../contracts/core/ConfidentialPolicyRegistry.sol";
import {ConfidentialPoolFactory} from "../contracts/core/ConfidentialPoolFactory.sol";
import {ConfidentialRecoursePool} from "../contracts/core/ConfidentialRecoursePool.sol";
import {ConfidentialCoverageManager} from "../contracts/core/ConfidentialCoverageManager.sol";

contract DeployConfidentialRecourse is Script {
    function run() external {
        uint256 deployerKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerKey);
        address trustedForwarder = vm.envOr("TRUSTED_FORWARDER", address(0));
        address escrowAddress = vm.envAddress("ESCROW_ADDRESS");

        vm.startBroadcast(deployerKey);

        ConfidentialPolicyRegistry policyRegistryImpl = new ConfidentialPolicyRegistry(trustedForwarder);
        ConfidentialPolicyRegistry policyRegistry = ConfidentialPolicyRegistry(
            address(
                new ERC1967Proxy(
                    address(policyRegistryImpl),
                    abi.encodeCall(ConfidentialPolicyRegistry.initialize, (deployer))
                )
            )
        );
        console.log("ConfidentialPolicyRegistry:", address(policyRegistry));

        ConfidentialRecoursePool poolImpl = new ConfidentialRecoursePool(trustedForwarder);
        console.log("ConfidentialRecoursePool (impl):", address(poolImpl));

        ConfidentialCoverageManager coverageManagerImpl = new ConfidentialCoverageManager(trustedForwarder);
        ConfidentialCoverageManager coverageManager = ConfidentialCoverageManager(
            address(
                new ERC1967Proxy(
                    address(coverageManagerImpl),
                    abi.encodeCall(ConfidentialCoverageManager.initialize, (deployer, deployer))
                )
            )
        );
        console.log("ConfidentialCoverageManager:", address(coverageManager));

        coverageManager.setEscrow(escrowAddress);

        ConfidentialPoolFactory poolFactoryImpl = new ConfidentialPoolFactory(trustedForwarder);
        ConfidentialPoolFactory poolFactory = ConfidentialPoolFactory(
            address(
                new ERC1967Proxy(
                    address(poolFactoryImpl),
                    abi.encodeCall(
                        ConfidentialPoolFactory.initialize,
                        (deployer, address(poolImpl), address(coverageManager), address(policyRegistry))
                    )
                )
            )
        );
        console.log("ConfidentialPoolFactory:", address(poolFactory));

        coverageManager.setPoolFactory(address(poolFactory));

        vm.stopBroadcast();
    }
}
