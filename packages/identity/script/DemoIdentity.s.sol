// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.25;

import {Script, console} from "forge-std/Script.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {AgentIdentityRegistry} from "../contracts/core/AgentIdentityRegistry.sol";
import {AgentReputationRegistry} from "../contracts/core/AgentReputationRegistry.sol";
import {IAgentIdentityRegistry} from "../contracts/interfaces/core/IAgentIdentityRegistry.sol";

/// Deploys ERC-8004 identity + reputation, registers the demo agent with skill
/// metadata, and records a real client feedback (track record after a miss).
contract DemoIdentity is Script {
    function run() external {
        uint256 opPk = vm.envUint("PRIVATE_KEY");
        address operator = vm.addr(opPk);
        uint256 clientPk = vm.envUint("CLIENT_PK");
        address tf = vm.envOr("TRUSTED_FORWARDER", address(0));

        vm.startBroadcast(opPk);
        AgentIdentityRegistry identity = AgentIdentityRegistry(
            address(
                new ERC1967Proxy(
                    address(new AgentIdentityRegistry(tf)),
                    abi.encodeCall(AgentIdentityRegistry.initialize, (operator))
                )
            )
        );
        AgentReputationRegistry reputation = AgentReputationRegistry(
            address(
                new ERC1967Proxy(
                    address(new AgentReputationRegistry(tf)),
                    abi.encodeCall(AgentReputationRegistry.initialize, (operator, address(identity)))
                )
            )
        );

        IAgentIdentityRegistry.MetadataEntry[] memory md = new IAgentIdentityRegistry.MetadataEntry[](4);
        md[0] = IAgentIdentityRegistry.MetadataEntry("promise", bytes("Fetch and deliver the invoice before the deadline"));
        md[1] = IAgentIdentityRegistry.MetadataEntry("skill", bytes("invoice.fetch"));
        md[2] = IAgentIdentityRegistry.MetadataEntry("maxDamage", bytes("0.10 USDC"));
        md[3] = IAgentIdentityRegistry.MetadataEntry("deadlineTerms", bytes("24h"));
        uint256 agentId = identity.register("https://reineira.xyz/agents/invoice-agent", md);
        vm.stopBroadcast();

        // Client (not the agent owner) leaves negative feedback after the missed deadline.
        vm.startBroadcast(clientPk);
        reputation.giveFeedback(
            agentId, int128(-1), 0, "recourse", "deadline-miss", "", "", keccak256("verdict:deadline-missed")
        );
        vm.stopBroadcast();

        console.log("AGENT_IDENTITY_REGISTRY=%s", address(identity));
        console.log("AGENT_REPUTATION_REGISTRY=%s", address(reputation));
        console.log("AGENT_ID=%s", agentId);
        console.log("AGENT_OWNER=%s", operator);
    }
}
