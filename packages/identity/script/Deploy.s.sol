// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.25;

import {Script, console} from "forge-std/Script.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {AgentIdentityRegistry} from "../contracts/core/AgentIdentityRegistry.sol";
import {AgentReputationRegistry} from "../contracts/core/AgentReputationRegistry.sol";
import {AgentValidationRegistry} from "../contracts/core/AgentValidationRegistry.sol";

contract DeployIdentity is Script {
    function _deployProxy(address impl, bytes memory initData) internal returns (address) {
        return address(new ERC1967Proxy(impl, initData));
    }

    function run() external {
        uint256 deployerKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerKey);
        address trustedForwarder = vm.envOr("TRUSTED_FORWARDER", address(0));

        vm.startBroadcast(deployerKey);

        address identity = _deployProxy(
            address(new AgentIdentityRegistry(trustedForwarder)),
            abi.encodeCall(AgentIdentityRegistry.initialize, (deployer))
        );
        console.log("AgentIdentityRegistry:", identity);

        address reputation = _deployProxy(
            address(new AgentReputationRegistry(trustedForwarder)),
            abi.encodeCall(AgentReputationRegistry.initialize, (deployer, identity))
        );
        console.log("AgentReputationRegistry:", reputation);

        address validation = _deployProxy(
            address(new AgentValidationRegistry(trustedForwarder)),
            abi.encodeCall(AgentValidationRegistry.initialize, (deployer, identity))
        );
        console.log("AgentValidationRegistry:", validation);

        vm.stopBroadcast();
    }
}
