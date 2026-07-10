// SPDX-License-Identifier: FSL-1.1-ALv2
pragma solidity ^0.8.25;

import {Script, console} from "forge-std/Script.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {PolicyRegistry} from "../contracts/core/PolicyRegistry.sol";
import {PoolFactory} from "../contracts/core/PoolFactory.sol";
import {RecoursePool} from "../contracts/core/RecoursePool.sol";
import {CoverageManager} from "../contracts/core/CoverageManager.sol";
import {ICoverageManager} from "../contracts/interfaces/core/ICoverageManager.sol";
import {MockEscrow} from "../contracts/mocks/MockEscrow.sol";
import {MockUnderwriterPolicy} from "../contracts/mocks/MockUnderwriterPolicy.sol";

contract DemoLiveSpike is Script {
    address constant USDC = 0x75faf114eafb1BDbe2F0316DF893fd58CE46AA4d;

    uint256 constant STAKE = 200_000;
    uint256 constant ESCROW_AMOUNT = 100_000;
    uint256 constant COVERAGE = 100_000;
    uint256 constant ESCROW_ID = 1;

    function run() external {
        uint256 opPk = vm.envUint("PRIVATE_KEY");
        address operator = vm.addr(opPk);
        uint256 clientPk = vm.envUint("CLIENT_PK");
        address client = vm.addr(clientPk);
        address tf = vm.envOr("TRUSTED_FORWARDER", address(0));

        vm.startBroadcast(opPk);

        PolicyRegistry registry = PolicyRegistry(
            address(new ERC1967Proxy(address(new PolicyRegistry(tf)), abi.encodeCall(PolicyRegistry.initialize, (operator))))
        );
        RecoursePool poolImpl = new RecoursePool(tf);
        CoverageManager cm = CoverageManager(
            address(
                new ERC1967Proxy(
                    address(new CoverageManager(tf)), abi.encodeCall(CoverageManager.initialize, (operator, operator))
                )
            )
        );
        MockEscrow escrow = new MockEscrow();
        cm.setEscrow(address(escrow));

        PoolFactory factory = PoolFactory(
            address(
                new ERC1967Proxy(
                    address(new PoolFactory(tf)),
                    abi.encodeCall(
                        PoolFactory.initialize, (operator, address(poolImpl), address(cm), address(registry))
                    )
                )
            )
        );
        cm.setPoolFactory(address(factory));
        factory.addAllowedToken(USDC);

        MockUnderwriterPolicy policy = new MockUnderwriterPolicy();
        registry.registerPolicy(address(policy));

        factory.createPool(USDC, address(0), address(0), true);
        address poolAddr = factory.pool(factory.poolCount() - 1);
        RecoursePool pool = RecoursePool(poolAddr);
        pool.addPolicy(address(policy));

        IERC20(USDC).approve(poolAddr, STAKE);
        pool.stake(STAKE);

        escrow.setExists(ESCROW_ID, true);
        escrow.setAmount(ESCROW_ID, ESCROW_AMOUNT);

        uint256 covId = cm.purchaseCoverage(
            client, poolAddr, address(policy), ESCROW_ID, COVERAGE, block.timestamp + 1 days, "", ""
        );

        console.log("coverageManager :", address(cm));
        console.log("pool            :", poolAddr);
        console.log("policy          :", address(policy));
        console.log("escrow (mock)   :", address(escrow));
        console.log("coverageId      :", covId);
        console.log("operator        :", operator);
        console.log("client (holder) :", client);
        console.log("client USDC pre :", IERC20(USDC).balanceOf(client));

        vm.stopBroadcast();

        vm.startBroadcast(clientPk);
        cm.dispute(covId, "");
        vm.stopBroadcast();

        console.log("client USDC post:", IERC20(USDC).balanceOf(client));
        console.log("coverage status :", uint256(cm.coverageStatus(covId)));
    }
}
