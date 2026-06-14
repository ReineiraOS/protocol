// SPDX-License-Identifier: FSL-1.1-ALv2
pragma solidity ^0.8.25;

import {Script, console} from "forge-std/Script.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {OperatorRegistry} from "../contracts/core/OperatorRegistry.sol";
import {FeeManager} from "../contracts/core/FeeManager.sol";
import {TaskExecutor} from "../contracts/core/TaskExecutor.sol";
import {CCTPHandler} from "../contracts/handlers/CCTPHandler.sol";
import {MockGovernanceToken} from "../contracts/mocks/MockGovernanceToken.sol";
import {TaskLib} from "../contracts/libraries/TaskLib.sol";

contract DeployOrchestration is Script {
    function _deployProxy(address impl, bytes memory initData) internal returns (address) {
        return address(new ERC1967Proxy(impl, initData));
    }

    function run() external {
        uint256 deployerKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerKey);
        address trustedForwarder = vm.envOr("TRUSTED_FORWARDER", address(0));
        address escrowReceiver = vm.envAddress("ESCROW_RECEIVER_ADDRESS");
        address stakingTokenAddr = vm.envOr("STAKING_TOKEN_ADDRESS", address(0));

        vm.startBroadcast(deployerKey);

        if (stakingTokenAddr == address(0)) {
            stakingTokenAddr = address(new MockGovernanceToken());
            console.log("MockGovernanceToken:", stakingTokenAddr);
        }

        address registry = _deployProxy(
            address(new OperatorRegistry(trustedForwarder)),
            abi.encodeCall(
                OperatorRegistry.initialize,
                (
                    deployer,
                    stakingTokenAddr,
                    vm.envOr("MIN_STAKE", uint256(5000e18)),
                    vm.envOr("EXCLUSIVE_WINDOW", uint256(60)),
                    vm.envOr("PERMISSIONLESS_DELAY", uint256(600))
                )
            )
        );
        console.log("OperatorRegistry:", registry);

        address feeManager = _deployProxy(
            address(new FeeManager(trustedForwarder)),
            abi.encodeCall(
                FeeManager.initialize,
                (deployer, stakingTokenAddr, deployer, vm.envOr("OPERATOR_FEE_BPS", uint256(50)))
            )
        );
        console.log("FeeManager:", feeManager);

        address executor = _deployProxy(
            address(new TaskExecutor(trustedForwarder)),
            abi.encodeCall(TaskExecutor.initialize, (deployer, registry, feeManager))
        );
        console.log("TaskExecutor:", executor);

        address handler = _deployProxy(
            address(new CCTPHandler(trustedForwarder)),
            abi.encodeCall(CCTPHandler.initialize, (deployer, escrowReceiver, executor))
        );
        console.log("CCTPHandler:", handler);

        OperatorRegistry(registry).setMonitor(executor);
        FeeManager(feeManager).setFeeCollector(executor);
        TaskExecutor(executor).registerHandler(TaskLib.TASK_CCTP_RELAY, handler);

        vm.stopBroadcast();
    }
}
