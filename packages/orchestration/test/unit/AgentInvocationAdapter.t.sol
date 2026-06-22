// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

import {AgentInvocationAdapter} from "../../contracts/core/AgentInvocationAdapter.sol";
import {IAgentInvocationAdapter} from "../../contracts/interfaces/core/IAgentInvocationAdapter.sol";
import {IAgenticJob} from "../../contracts/interfaces/core/IAgenticJob.sol";
import {IAgentConfigRegistry} from "../../contracts/interfaces/core/IAgentConfigRegistry.sol";
import {MockAgentConfigRegistry} from "../../contracts/mocks/MockAgentConfigRegistry.sol";
import {MockQuorumAttestedResolver} from "../../contracts/mocks/MockQuorumAttestedResolver.sol";
import {MockAgentCoverageManager} from "../../contracts/mocks/MockAgentCoverageManager.sol";
import {MockEscrow} from "../../contracts/mocks/MockEscrow.sol";
import {MockConditionResolver} from "../../contracts/mocks/MockConditionResolver.sol";

contract AgentInvocationAdapterTest is Test {
    AgentInvocationAdapter adapter;
    MockAgentConfigRegistry registry;
    MockQuorumAttestedResolver quorumResolver;
    MockAgentCoverageManager coverageManager;
    MockEscrow escrow;
    MockConditionResolver inputResolver;
    MockConditionResolver outputResolver;

    address owner;
    address client;
    address agent;
    address unauthorized;

    uint256 agentPrivateKey;

    function setUp() public {
        owner = makeAddr("owner");
        client = makeAddr("client");
        unauthorized = makeAddr("unauthorized");

        agentPrivateKey = 0x42;
        agent = vm.addr(agentPrivateKey);

        registry = new MockAgentConfigRegistry();
        quorumResolver = new MockQuorumAttestedResolver();
        coverageManager = new MockAgentCoverageManager();
        escrow = new MockEscrow();
        inputResolver = new MockConditionResolver();
        outputResolver = new MockConditionResolver();

        inputResolver.setCondition(0, true);
        outputResolver.setCondition(0, true);
        outputResolver.setCondition(1, true);

        AgentInvocationAdapter impl = new AgentInvocationAdapter(address(0));
        bytes memory initData = abi.encodeCall(
            AgentInvocationAdapter.initialize,
            (owner, address(escrow), address(registry), address(coverageManager))
        );
        ERC1967Proxy proxy = new ERC1967Proxy(address(impl), initData);
        adapter = AgentInvocationAdapter(address(proxy));
    }

    function _buildAgentConfig() internal returns (IAgentConfigRegistry.AgentConfig memory) {
        address[] memory inputResolvers = new address[](1);
        inputResolvers[0] = address(inputResolver);

        address[] memory outputResolvers = new address[](1);
        outputResolvers[0] = address(outputResolver);

        address[] memory pools = new address[](1);
        pools[0] = makeAddr("pool1");

        address[] memory policies = new address[](1);
        policies[0] = makeAddr("policy1");

        return IAgentConfigRegistry.AgentConfig({
            agent: agent,
            inputResolvers: inputResolvers,
            outputResolvers: outputResolvers,
            quorumResolver: address(quorumResolver),
            payoutSchema: abi.encode("test-schema"),
            minQuorum: 3,
            coveragePools: pools,
            coveragePolicies: policies
        });
    }

    function _buildCoverageParams() internal returns (IAgenticJob.CoverageParam[] memory) {
        IAgenticJob.CoverageParam[] memory params = new IAgenticJob.CoverageParam[](1);
        params[0] = IAgenticJob.CoverageParam({
            pool: makeAddr("pool1"),
            policy: makeAddr("policy1"),
            coverageAmount: 1000,
            coverageExpiry: block.timestamp + 1 days,
            policyData: hex"00",
            riskProof: hex"00"
        });
        return params;
    }

    function _signVerdict(uint256 privateKey, uint256 invocationId, bytes memory verdict) internal returns (bytes memory) {
        bytes32 hash = keccak256(abi.encodePacked(invocationId, verdict));
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(privateKey, hash);
        return abi.encodePacked(r, s, v);
    }

    // ==================== 9-step pipeline success ====================

    function test_openInvocation_success() public {
        IAgentConfigRegistry.AgentConfig memory config = _buildAgentConfig();
        registry.setAgentConfig(agent, config);

        IAgenticJob.CoverageParam[] memory coverageParams = _buildCoverageParams();

        vm.prank(client);
        uint256 invocationId = adapter.openInvocation(
            agent,
            abi.encode(address(client), uint256(1000)),
            abi.encode(uint256(500)),
            hex"00",
            coverageParams
        );

        assertEq(invocationId, 0);

        (address returnedAgent, address returnedClient, uint256 escrowId, IAgenticJob.InvocationStatus status) =
            adapter.getInvocation(invocationId);
        assertEq(returnedAgent, agent);
        assertEq(returnedClient, client);
        assertEq(uint256(status), uint256(IAgenticJob.InvocationStatus.Opened));
        assertTrue(escrowId > 0);

        assertTrue(quorumResolver.isInputGateTriggered(escrowId));
        assertFalse(quorumResolver.isOutputGateTriggered(escrowId));

        uint256[] memory coverages = adapter.getCoverages(invocationId);
        assertEq(coverages.length, 1);

        bytes memory manifest = adapter.getPayoutManifest(escrowId);
        assertEq(keccak256(manifest), keccak256(config.payoutSchema));
    }

    function test_submitFinalVerdict_success() public {
        IAgentConfigRegistry.AgentConfig memory config = _buildAgentConfig();
        registry.setAgentConfig(agent, config);

        IAgenticJob.CoverageParam[] memory coverageParams = _buildCoverageParams();

        vm.prank(client);
        uint256 invocationId = adapter.openInvocation(
            agent,
            abi.encode(address(client), uint256(1000)),
            abi.encode(uint256(500)),
            hex"00",
            coverageParams
        );

        (, , uint256 escrowId, ) = adapter.getInvocation(invocationId);

        bytes memory verdict = abi.encode("success");
        bytes memory agentSig = _signVerdict(agentPrivateKey, invocationId, verdict);
        bytes memory quorumSigs = hex"deadbeef";

        quorumResolver.setQuorumValid(true);

        vm.expectEmit(true, false, false, true);
        emit IAgenticJob.VerdictSubmitted(invocationId, keccak256(abi.encodePacked(invocationId, verdict)));

        vm.prank(client);
        adapter.submitFinalVerdict(invocationId, verdict, agentSig, quorumSigs);

        (, , , IAgenticJob.InvocationStatus status) = adapter.getInvocation(invocationId);
        assertEq(uint256(status), uint256(IAgenticJob.InvocationStatus.VerdictSubmitted));
        assertTrue(quorumResolver.isOutputGateTriggered(escrowId));
    }

    function test_completeInvocation_success() public {
        IAgentConfigRegistry.AgentConfig memory config = _buildAgentConfig();
        registry.setAgentConfig(agent, config);

        IAgenticJob.CoverageParam[] memory coverageParams = _buildCoverageParams();

        vm.prank(client);
        uint256 invocationId = adapter.openInvocation(
            agent,
            abi.encode(address(client), uint256(1000)),
            abi.encode(uint256(500)),
            hex"00",
            coverageParams
        );

        (, , uint256 escrowId, ) = adapter.getInvocation(invocationId);

        bytes memory verdict = abi.encode("success");
        bytes memory agentSig = _signVerdict(agentPrivateKey, invocationId, verdict);
        bytes memory quorumSigs = hex"deadbeef";

        quorumResolver.setQuorumValid(true);
        quorumResolver.setConditionMet(true);

        vm.prank(client);
        adapter.submitFinalVerdict(invocationId, verdict, agentSig, quorumSigs);

        vm.expectEmit(true, true, false, false);
        emit IAgenticJob.InvocationCompleted(invocationId, escrowId);

        adapter.completeInvocation(invocationId);

        (, , , IAgenticJob.InvocationStatus status) = adapter.getInvocation(invocationId);
        assertEq(uint256(status), uint256(IAgenticJob.InvocationStatus.Completed));
    }

    // ==================== Failure modes ====================

    function test_openInvocation_revertInvalidAgent() public {
        IAgenticJob.CoverageParam[] memory coverageParams = _buildCoverageParams();

        vm.prank(client);
        vm.expectRevert(IAgenticJob.InvalidAgent.selector);
        adapter.openInvocation(
            agent,
            abi.encode(address(client), uint256(1000)),
            abi.encode(uint256(500)),
            hex"00",
            coverageParams
        );
    }

    function test_openInvocation_revertInputConditionsNotMet() public {
        IAgentConfigRegistry.AgentConfig memory config = _buildAgentConfig();
        registry.setAgentConfig(agent, config);

        inputResolver.setCondition(0, false);

        IAgenticJob.CoverageParam[] memory coverageParams = _buildCoverageParams();

        vm.prank(client);
        vm.expectRevert(
            abi.encodeWithSelector(IAgenticJob.InputConditionsNotMet.selector, 0, address(inputResolver))
        );
        adapter.openInvocation(
            agent,
            abi.encode(address(client), uint256(1000)),
            abi.encode(uint256(500)),
            hex"00",
            coverageParams
        );
    }

    function test_openInvocation_revertEmptyCoverageParams() public {
        IAgentConfigRegistry.AgentConfig memory config = _buildAgentConfig();
        registry.setAgentConfig(agent, config);

        IAgenticJob.CoverageParam[] memory coverageParams = new IAgenticJob.CoverageParam[](0);

        vm.prank(client);
        vm.expectRevert(IAgentInvocationAdapter.EmptyCoverageParams.selector);
        adapter.openInvocation(
            agent,
            abi.encode(address(client), uint256(1000)),
            abi.encode(uint256(500)),
            hex"00",
            coverageParams
        );
    }

    function test_openInvocation_revertCoverageAttachmentFailed() public {
        IAgentConfigRegistry.AgentConfig memory config = _buildAgentConfig();
        registry.setAgentConfig(agent, config);

        coverageManager.setGlobalFail(true);

        IAgenticJob.CoverageParam[] memory coverageParams = _buildCoverageParams();

        vm.prank(client);
        vm.expectRevert();
        adapter.openInvocation(
            agent,
            abi.encode(address(client), uint256(1000)),
            abi.encode(uint256(500)),
            hex"00",
            coverageParams
        );
    }

    function test_submitFinalVerdict_revertInvocationNotFound() public {
        bytes memory verdict = abi.encode("success");
        bytes memory agentSig = _signVerdict(agentPrivateKey, 999, verdict);

        vm.prank(client);
        vm.expectRevert(IAgenticJob.InvocationNotFound.selector);
        adapter.submitFinalVerdict(999, verdict, agentSig, hex"00");
    }

    function test_submitFinalVerdict_revertInvocationNotOpen() public {
        IAgentConfigRegistry.AgentConfig memory config = _buildAgentConfig();
        registry.setAgentConfig(agent, config);

        IAgenticJob.CoverageParam[] memory coverageParams = _buildCoverageParams();

        vm.prank(client);
        uint256 invocationId = adapter.openInvocation(
            agent,
            abi.encode(address(client), uint256(1000)),
            abi.encode(uint256(500)),
            hex"00",
            coverageParams
        );

        bytes memory verdict = abi.encode("success");
        bytes memory agentSig = _signVerdict(agentPrivateKey, invocationId, verdict);

        vm.prank(client);
        adapter.submitFinalVerdict(invocationId, verdict, agentSig, hex"00");

        vm.prank(client);
        vm.expectRevert(IAgenticJob.AlreadySubmitted.selector);
        adapter.submitFinalVerdict(invocationId, verdict, agentSig, hex"00");
    }

    function test_submitFinalVerdict_revertInvalidVerdict() public {
        IAgentConfigRegistry.AgentConfig memory config = _buildAgentConfig();
        registry.setAgentConfig(agent, config);

        IAgenticJob.CoverageParam[] memory coverageParams = _buildCoverageParams();

        vm.prank(client);
        uint256 invocationId = adapter.openInvocation(
            agent,
            abi.encode(address(client), uint256(1000)),
            abi.encode(uint256(500)),
            hex"00",
            coverageParams
        );

        vm.prank(client);
        vm.expectRevert(IAgenticJob.InvalidVerdict.selector);
        adapter.submitFinalVerdict(invocationId, "", hex"00", hex"00");
    }

    function test_submitFinalVerdict_revertInvalidSignature() public {
        IAgentConfigRegistry.AgentConfig memory config = _buildAgentConfig();
        registry.setAgentConfig(agent, config);

        IAgenticJob.CoverageParam[] memory coverageParams = _buildCoverageParams();

        vm.prank(client);
        uint256 invocationId = adapter.openInvocation(
            agent,
            abi.encode(address(client), uint256(1000)),
            abi.encode(uint256(500)),
            hex"00",
            coverageParams
        );

        bytes memory verdict = abi.encode("success");
        uint256 wrongKey = 0x99;
        bytes memory wrongSig = _signVerdict(wrongKey, invocationId, verdict);

        vm.prank(client);
        vm.expectRevert(IAgenticJob.InvalidSignature.selector);
        adapter.submitFinalVerdict(invocationId, verdict, wrongSig, hex"00");
    }

    function test_submitFinalVerdict_revertQuorumNotReached() public {
        IAgentConfigRegistry.AgentConfig memory config = _buildAgentConfig();
        registry.setAgentConfig(agent, config);

        IAgenticJob.CoverageParam[] memory coverageParams = _buildCoverageParams();

        vm.prank(client);
        uint256 invocationId = adapter.openInvocation(
            agent,
            abi.encode(address(client), uint256(1000)),
            abi.encode(uint256(500)),
            hex"00",
            coverageParams
        );

        bytes memory verdict = abi.encode("success");
        bytes memory agentSig = _signVerdict(agentPrivateKey, invocationId, verdict);

        quorumResolver.setQuorumValid(false);

        vm.prank(client);
        vm.expectRevert(IAgenticJob.QuorumNotReached.selector);
        adapter.submitFinalVerdict(invocationId, verdict, agentSig, hex"00");
    }

    function test_submitFinalVerdict_revertOutputConditionsNotMet() public {
        IAgentConfigRegistry.AgentConfig memory config = _buildAgentConfig();
        registry.setAgentConfig(agent, config);

        IAgenticJob.CoverageParam[] memory coverageParams = _buildCoverageParams();

        vm.prank(client);
        uint256 invocationId = adapter.openInvocation(
            agent,
            abi.encode(address(client), uint256(1000)),
            abi.encode(uint256(500)),
            hex"00",
            coverageParams
        );

        (, , uint256 escrowId, ) = adapter.getInvocation(invocationId);
        outputResolver.setCondition(escrowId, false);

        bytes memory verdict = abi.encode("success");
        bytes memory agentSig = _signVerdict(agentPrivateKey, invocationId, verdict);

        quorumResolver.setQuorumValid(true);

        vm.prank(client);
        vm.expectRevert(
            abi.encodeWithSelector(IAgenticJob.OutputConditionsNotMet.selector, escrowId, address(outputResolver))
        );
        adapter.submitFinalVerdict(invocationId, verdict, agentSig, hex"00");
    }

    // ==================== completeInvocation failures ====================

    function test_completeInvocation_revertInvocationNotFound() public {
        vm.expectRevert(IAgenticJob.InvocationNotFound.selector);
        adapter.completeInvocation(999);
    }

    function test_completeInvocation_revertNotOpen() public {
        IAgentConfigRegistry.AgentConfig memory config = _buildAgentConfig();
        registry.setAgentConfig(agent, config);

        IAgenticJob.CoverageParam[] memory coverageParams = _buildCoverageParams();

        vm.prank(client);
        uint256 invocationId = adapter.openInvocation(
            agent,
            abi.encode(address(client), uint256(1000)),
            abi.encode(uint256(500)),
            hex"00",
            coverageParams
        );

        vm.expectRevert(IAgenticJob.InvocationNotOpen.selector);
        adapter.completeInvocation(invocationId);
    }

    function test_completeInvocation_revertOutputConditionsNotMet() public {
        IAgentConfigRegistry.AgentConfig memory config = _buildAgentConfig();
        registry.setAgentConfig(agent, config);

        IAgenticJob.CoverageParam[] memory coverageParams = _buildCoverageParams();

        vm.prank(client);
        uint256 invocationId = adapter.openInvocation(
            agent,
            abi.encode(address(client), uint256(1000)),
            abi.encode(uint256(500)),
            hex"00",
            coverageParams
        );

        bytes memory verdict = abi.encode("success");
        bytes memory agentSig = _signVerdict(agentPrivateKey, invocationId, verdict);

        quorumResolver.setQuorumValid(true);
        quorumResolver.setConditionMet(false);

        vm.prank(client);
        adapter.submitFinalVerdict(invocationId, verdict, agentSig, hex"00");

        vm.expectRevert(
            abi.encodeWithSelector(IAgenticJob.OutputConditionsNotMet.selector, invocationId, address(quorumResolver))
        );
        adapter.completeInvocation(invocationId);
    }

    // ==================== failInvocation ====================

    function test_failInvocation_client() public {
        IAgentConfigRegistry.AgentConfig memory config = _buildAgentConfig();
        registry.setAgentConfig(agent, config);

        IAgenticJob.CoverageParam[] memory coverageParams = _buildCoverageParams();

        vm.prank(client);
        uint256 invocationId = adapter.openInvocation(
            agent,
            abi.encode(address(client), uint256(1000)),
            abi.encode(uint256(500)),
            hex"00",
            coverageParams
        );

        vm.prank(client);
        adapter.failInvocation(invocationId, "timeout");

        (, , , IAgenticJob.InvocationStatus status) = adapter.getInvocation(invocationId);
        assertEq(uint256(status), uint256(IAgenticJob.InvocationStatus.Failed));
    }

    function test_failInvocation_owner() public {
        IAgentConfigRegistry.AgentConfig memory config = _buildAgentConfig();
        registry.setAgentConfig(agent, config);

        IAgenticJob.CoverageParam[] memory coverageParams = _buildCoverageParams();

        vm.prank(client);
        uint256 invocationId = adapter.openInvocation(
            agent,
            abi.encode(address(client), uint256(1000)),
            abi.encode(uint256(500)),
            hex"00",
            coverageParams
        );

        vm.prank(owner);
        adapter.failInvocation(invocationId, "timeout");

        (, , , IAgenticJob.InvocationStatus status) = adapter.getInvocation(invocationId);
        assertEq(uint256(status), uint256(IAgenticJob.InvocationStatus.Failed));
    }

    function test_failInvocation_revertUnauthorized() public {
        IAgentConfigRegistry.AgentConfig memory config = _buildAgentConfig();
        registry.setAgentConfig(agent, config);

        IAgenticJob.CoverageParam[] memory coverageParams = _buildCoverageParams();

        vm.prank(client);
        uint256 invocationId = adapter.openInvocation(
            agent,
            abi.encode(address(client), uint256(1000)),
            abi.encode(uint256(500)),
            hex"00",
            coverageParams
        );

        vm.prank(unauthorized);
        vm.expectRevert(AgentInvocationAdapter.Unauthorized.selector);
        adapter.failInvocation(invocationId, "timeout");
    }

    function test_failInvocation_revertAlreadyCompleted() public {
        IAgentConfigRegistry.AgentConfig memory config = _buildAgentConfig();
        registry.setAgentConfig(agent, config);

        IAgenticJob.CoverageParam[] memory coverageParams = _buildCoverageParams();

        vm.prank(client);
        uint256 invocationId = adapter.openInvocation(
            agent,
            abi.encode(address(client), uint256(1000)),
            abi.encode(uint256(500)),
            hex"00",
            coverageParams
        );

        bytes memory verdict = abi.encode("success");
        bytes memory agentSig = _signVerdict(agentPrivateKey, invocationId, verdict);

        quorumResolver.setQuorumValid(true);
        quorumResolver.setConditionMet(true);

        vm.prank(client);
        adapter.submitFinalVerdict(invocationId, verdict, agentSig, hex"00");

        adapter.completeInvocation(invocationId);

        vm.prank(client);
        vm.expectRevert(IAgenticJob.AlreadySubmitted.selector);
        adapter.failInvocation(invocationId, "timeout");
    }

    // ==================== Admin functions ====================

    function test_setAgentRegistry() public {
        MockAgentConfigRegistry newRegistry = new MockAgentConfigRegistry();

        vm.prank(owner);
        adapter.setAgentRegistry(address(newRegistry));

        assertEq(adapter.agentRegistry(), address(newRegistry));
    }

    function test_setEscrow() public {
        MockEscrow newEscrow = new MockEscrow();

        vm.prank(owner);
        adapter.setEscrow(address(newEscrow));

        assertEq(adapter.escrow(), address(newEscrow));
    }

    function test_setCoverageManager() public {
        MockAgentCoverageManager newManager = new MockAgentCoverageManager();

        vm.prank(owner);
        adapter.setCoverageManager(address(newManager));

        assertEq(adapter.coverageManager(), address(newManager));
    }

    function test_setAgentRegistry_revertZeroAddress() public {
        vm.prank(owner);
        vm.expectRevert(IAgentInvocationAdapter.ZeroAddress.selector);
        adapter.setAgentRegistry(address(0));
    }

    function test_setEscrow_revertZeroAddress() public {
        vm.prank(owner);
        vm.expectRevert(IAgentInvocationAdapter.ZeroAddress.selector);
        adapter.setEscrow(address(0));
    }

    function test_setCoverageManager_revertZeroAddress() public {
        vm.prank(owner);
        vm.expectRevert(IAgentInvocationAdapter.ZeroAddress.selector);
        adapter.setCoverageManager(address(0));
    }

    function test_admin_revertNotOwner() public {
        vm.prank(unauthorized);
        vm.expectRevert();
        adapter.setAgentRegistry(address(1));
    }

    // ==================== Multiple coverages ====================

    function test_openInvocation_multipleCoverages() public {
        IAgentConfigRegistry.AgentConfig memory config = _buildAgentConfig();
        registry.setAgentConfig(agent, config);

        IAgenticJob.CoverageParam[] memory coverageParams = new IAgenticJob.CoverageParam[](3);
        for (uint256 i = 0; i < 3; i++) {
            coverageParams[i] = IAgenticJob.CoverageParam({
                pool: makeAddr(string.concat("pool", vm.toString(i))),
                policy: makeAddr(string.concat("policy", vm.toString(i))),
                coverageAmount: 1000 * (i + 1),
                coverageExpiry: block.timestamp + 1 days,
                policyData: hex"00",
                riskProof: hex"00"
            });
        }

        vm.prank(client);
        uint256 invocationId = adapter.openInvocation(
            agent,
            abi.encode(address(client), uint256(1000)),
            abi.encode(uint256(500)),
            hex"00",
            coverageParams
        );

        uint256[] memory coverages = adapter.getCoverages(invocationId);
        assertEq(coverages.length, 3);
    }
}
