// SPDX-License-Identifier: FSL-1.1-ALv2
pragma solidity ^0.8.25;

import {Script, console} from "forge-std/Script.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {OperatorRegistry} from "../contracts/core/OperatorRegistry.sol";
import {FeeManager} from "../contracts/core/FeeManager.sol";
import {TaskExecutor} from "../contracts/core/TaskExecutor.sol";
import {CCTPHandler} from "../contracts/handlers/CCTPHandler.sol";
import {OperatorSlashingManager} from "../contracts/core/OperatorSlashingManager.sol";

contract UpgradeRegistry is Script {
    function run() external {
        uint256 deployerKey = vm.envUint("PRIVATE_KEY");
        address proxy = vm.envAddress("PROXY_ADDRESS");
        address trustedForwarder = vm.envOr("TRUSTED_FORWARDER", address(0));

        vm.startBroadcast(deployerKey);
        OperatorRegistry newImpl = new OperatorRegistry(trustedForwarder);
        UUPSUpgradeable(proxy).upgradeToAndCall(address(newImpl), "");
        console.log("OperatorRegistry upgraded. New impl:", address(newImpl));
        vm.stopBroadcast();
    }
}

contract UpgradeFeeManager is Script {
    function run() external {
        uint256 deployerKey = vm.envUint("PRIVATE_KEY");
        address proxy = vm.envAddress("PROXY_ADDRESS");
        address trustedForwarder = vm.envOr("TRUSTED_FORWARDER", address(0));

        vm.startBroadcast(deployerKey);
        FeeManager newImpl = new FeeManager(trustedForwarder);
        UUPSUpgradeable(proxy).upgradeToAndCall(address(newImpl), "");
        console.log("FeeManager upgraded. New impl:", address(newImpl));
        vm.stopBroadcast();
    }
}

contract UpgradeTaskExecutor is Script {
    function run() external {
        uint256 deployerKey = vm.envUint("PRIVATE_KEY");
        address proxy = vm.envAddress("PROXY_ADDRESS");
        address trustedForwarder = vm.envOr("TRUSTED_FORWARDER", address(0));

        vm.startBroadcast(deployerKey);
        TaskExecutor newImpl = new TaskExecutor(trustedForwarder);
        UUPSUpgradeable(proxy).upgradeToAndCall(address(newImpl), "");
        console.log("TaskExecutor upgraded. New impl:", address(newImpl));
        vm.stopBroadcast();
    }
}

contract UpgradeCCTPHandler is Script {
    function run() external {
        uint256 deployerKey = vm.envUint("PRIVATE_KEY");
        address proxy = vm.envAddress("PROXY_ADDRESS");
        address trustedForwarder = vm.envOr("TRUSTED_FORWARDER", address(0));

        vm.startBroadcast(deployerKey);
        CCTPHandler newImpl = new CCTPHandler(trustedForwarder);
        UUPSUpgradeable(proxy).upgradeToAndCall(address(newImpl), "");
        console.log("CCTPHandler upgraded. New impl:", address(newImpl));
        vm.stopBroadcast();
    }
}

contract UpgradeSlashingManager is Script {
    function run() external {
        uint256 deployerKey = vm.envUint("PRIVATE_KEY");
        address proxy = vm.envAddress("PROXY_ADDRESS");
        address trustedForwarder = vm.envOr("TRUSTED_FORWARDER", address(0));

        vm.startBroadcast(deployerKey);
        OperatorSlashingManager newImpl = new OperatorSlashingManager(trustedForwarder);
        UUPSUpgradeable(proxy).upgradeToAndCall(address(newImpl), "");
        console.log("OperatorSlashingManager upgraded. New impl:", address(newImpl));
        vm.stopBroadcast();
    }
}
