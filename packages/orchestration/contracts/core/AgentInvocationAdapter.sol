// SPDX-License-Identifier: FSL-1.1-ALv2
// Copyright (c) 2026 Reineira Labs Limited All rights reserved.
pragma solidity ^0.8.24;

import {TestnetCoreBase} from "@reineira-os/shared/contracts/common/TestnetCoreBase.sol";
import {IEscrow} from "@reineira-os/shared/contracts/interfaces/core/IEscrow.sol";
import {IConditionResolver} from "@reineira-os/shared/contracts/interfaces/plugins/IConditionResolver.sol";

import {IAgentInvocationAdapter} from "../interfaces/core/IAgentInvocationAdapter.sol";
import {IAgentConfigRegistry} from "../interfaces/core/IAgentConfigRegistry.sol";
import {IQuorumAttestedResolver} from "../interfaces/core/IQuorumAttestedResolver.sol";
import {IAgentCoverageManager} from "../interfaces/core/IAgentCoverageManager.sol";

contract AgentInvocationAdapter is IAgentInvocationAdapter, TestnetCoreBase {
    error Unauthorized();
    /// @custom:storage-location erc7201:reineira.storage.AgentInvocationState
    struct AgentInvocationState {
        IEscrow escrow;
        IAgentConfigRegistry agentRegistry;
        IAgentCoverageManager coverageManager;
        uint256 nextInvocationId;
        mapping(uint256 => Invocation) invocations;
        mapping(uint256 => uint256) escrowToInvocation;
        mapping(uint256 => uint256[]) invocationCoverages;
        mapping(uint256 => bytes) payoutManifests;
    }

    struct Invocation {
        address agent;
        address client;
        uint256 escrowId;
        bytes32 inputHash;
        bytes32 outputHash;
        InvocationStatus status;
        uint256 createdAt;
    }

    bytes32 private constant AGENT_INVOCATION_STORAGE_LOCATION =
        0x8252abd94170de379efac16e2dee3fcce6d5aea934aa646b46846b7a0586cf00;

    uint256[50] private __gap;

    function _getAgentInvocationStorage() private pure returns (AgentInvocationState storage $) {
        assembly {
            $.slot := AGENT_INVOCATION_STORAGE_LOCATION
        }
    }

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor(address trustedForwarder_) TestnetCoreBase(trustedForwarder_) {
        _disableInitializers();
    }

    function initialize(address owner_, address escrow_, address registry_, address coverageManager_) external initializer {
        if (escrow_ == address(0)) revert ZeroAddress();
        if (registry_ == address(0)) revert ZeroAddress();
        if (coverageManager_ == address(0)) revert ZeroAddress();

        __TestnetCoreBase_init(owner_);

        AgentInvocationState storage $ = _getAgentInvocationStorage();
        $.escrow = IEscrow(escrow_);
        $.agentRegistry = IAgentConfigRegistry(registry_);
        $.coverageManager = IAgentCoverageManager(coverageManager_);
    }

    // --- views ---

    function agentRegistry() external view returns (address) {
        return address(_getAgentInvocationStorage().agentRegistry);
    }

    function escrow() external view returns (address) {
        return address(_getAgentInvocationStorage().escrow);
    }

    function coverageManager() external view returns (address) {
        return address(_getAgentInvocationStorage().coverageManager);
    }

    function getInvocation(uint256 invocationId)
        external
        view
        returns (address agent, address client, uint256 escrowId, InvocationStatus status)
    {
        Invocation storage inv = _getAgentInvocationStorage().invocations[invocationId];
        return (inv.agent, inv.client, inv.escrowId, inv.status);
    }

    function getCoverages(uint256 invocationId) external view returns (uint256[] memory coverageIds) {
        return _getAgentInvocationStorage().invocationCoverages[invocationId];
    }

    function getPayoutManifest(uint256 escrowId) external view returns (bytes memory schema) {
        return _getAgentInvocationStorage().payoutManifests[escrowId];
    }

    // --- setters (owner only) ---

    function setAgentRegistry(address registry_) external onlyOwner {
        if (registry_ == address(0)) revert ZeroAddress();
        AgentInvocationState storage $ = _getAgentInvocationStorage();
        address oldRegistry = address($.agentRegistry);
        $.agentRegistry = IAgentConfigRegistry(registry_);
        emit RegistryUpdated(oldRegistry, registry_);
    }

    function setEscrow(address escrow_) external onlyOwner {
        if (escrow_ == address(0)) revert ZeroAddress();
        AgentInvocationState storage $ = _getAgentInvocationStorage();
        address oldEscrow = address($.escrow);
        $.escrow = IEscrow(escrow_);
        emit EscrowUpdated(oldEscrow, escrow_);
    }

    function setCoverageManager(address manager_) external onlyOwner {
        if (manager_ == address(0)) revert ZeroAddress();
        AgentInvocationState storage $ = _getAgentInvocationStorage();
        address oldManager = address($.coverageManager);
        $.coverageManager = IAgentCoverageManager(manager_);
        emit CoverageManagerUpdated(oldManager, manager_);
    }

    // --- 9-step pipeline ---

    function openInvocation(
        address agent,
        bytes calldata escrowInitData,
        bytes calldata fundingProof,
        bytes calldata resolverData,
        CoverageParam[] calldata coverageParams
    ) external nonReentrant returns (uint256 invocationId) {
        AgentInvocationState storage $ = _getAgentInvocationStorage();

        // Step 1: Read agent config from AgentConfigRegistry
        IAgentConfigRegistry.AgentConfig memory config = $.agentRegistry.getAgentConfig(agent);
        if (config.agent == address(0) || !$.agentRegistry.isRegisteredAgent(agent)) {
            revert InvalidAgent();
        }

        // Step 2: Validate input conditions (IConditionResolver[] from agent slots)
        _validateInputConditions(config.inputResolvers);

        // Step 3: Create escrow via IEscrow + register PayoutManifest schema
        uint256 escrowId = $.escrow.create(escrowInitData, config.quorumResolver, resolverData);
        if (escrowId == 0) revert EscrowCreationFailed();

        // Register PayoutManifest schema
        if (config.payoutSchema.length > 0) {
            $.payoutManifests[escrowId] = config.payoutSchema;
            emit PayoutManifestRegistered(escrowId, keccak256(config.payoutSchema));
        }

        // Trigger input gate on QuorumAttestedResolver
        IQuorumAttestedResolver(config.quorumResolver).triggerInputGate(escrowId);

        // Fund escrow
        $.escrow.fund(escrowId, fundingProof);

        // Step 4: Attach N coverages via extended ConfidentialCoverageManager
        uint256[] memory coverageIds = _attachCoverages($.coverageManager, escrowId, coverageParams);

        // Step 5: Emit InvocationOpened event
        invocationId = $.nextInvocationId++;
        $.invocations[invocationId] = Invocation({
            agent: agent,
            client: _msgSender(),
            escrowId: escrowId,
            inputHash: keccak256(escrowInitData),
            outputHash: bytes32(0),
            status: InvocationStatus.Opened,
            createdAt: block.timestamp
        });
        $.escrowToInvocation[escrowId] = invocationId;
        $.invocationCoverages[invocationId] = coverageIds;

        emit InvocationOpened(invocationId, escrowId, agent, _msgSender());
    }

    function submitFinalVerdict(
        uint256 invocationId,
        bytes calldata verdict,
        bytes calldata agentSig,
        bytes calldata quorumSigs
    ) external nonReentrant {
        if (verdict.length == 0) revert InvalidVerdict();

        AgentInvocationState storage $ = _getAgentInvocationStorage();
        Invocation storage inv = $.invocations[invocationId];

        if (inv.status == InvocationStatus.None) revert InvocationNotFound();
        if (inv.status == InvocationStatus.VerdictSubmitted) revert AlreadySubmitted();
        if (inv.status != InvocationStatus.Opened) revert InvocationNotOpen();

        IAgentConfigRegistry.AgentConfig memory config = $.agentRegistry.getAgentConfig(inv.agent);

        // Step 7 (cont): Validate agent signature
        bytes32 verdictHash = keccak256(abi.encodePacked(invocationId, verdict));
        _verifyAgentSignature(inv.agent, verdictHash, agentSig);

        // Step 8: Validate output conditions (IConditionResolver[] from agent slots)
        _validateOutputConditions(config.outputResolvers, inv.escrowId);

        // Step 9: Trigger both gates on QuorumAttestedResolver
        IQuorumAttestedResolver resolver = IQuorumAttestedResolver(config.quorumResolver);

        // Verify quorum signatures before triggering output gate
        bytes memory quorumMessage = abi.encodePacked(inv.escrowId, verdict);
        if (!resolver.verifyQuorum(quorumMessage, quorumSigs)) {
            revert QuorumNotReached();
        }

        resolver.triggerOutputGate(inv.escrowId, verdict, quorumSigs);

        // Update invocation state
        inv.outputHash = verdictHash;
        inv.status = InvocationStatus.VerdictSubmitted;

        emit VerdictSubmitted(invocationId, verdictHash);
    }

    // --- helper: complete invocation (can be called after verdict submission) ---

    function completeInvocation(uint256 invocationId) external nonReentrant {
        AgentInvocationState storage $ = _getAgentInvocationStorage();
        Invocation storage inv = $.invocations[invocationId];

        if (inv.status == InvocationStatus.None) revert InvocationNotFound();
        if (inv.status != InvocationStatus.VerdictSubmitted) revert InvocationNotOpen();

        IAgentConfigRegistry.AgentConfig memory config = $.agentRegistry.getAgentConfig(inv.agent);
        IQuorumAttestedResolver resolver = IQuorumAttestedResolver(config.quorumResolver);

        if (!resolver.isConditionMet(inv.escrowId)) {
            revert OutputConditionsNotMet(invocationId, config.quorumResolver);
        }

        inv.status = InvocationStatus.Completed;
        emit InvocationCompleted(invocationId, inv.escrowId);
    }

    // --- helper: mark invocation as failed (owner or client) ---

    function failInvocation(uint256 invocationId, string calldata reason) external nonReentrant {
        AgentInvocationState storage $ = _getAgentInvocationStorage();
        Invocation storage inv = $.invocations[invocationId];

        if (inv.status == InvocationStatus.None) revert InvocationNotFound();
        if (inv.status == InvocationStatus.Completed || inv.status == InvocationStatus.Failed) {
            revert AlreadySubmitted();
        }

        address sender = _msgSender();
        if (sender != inv.client && sender != owner()) {
            revert Unauthorized();
        }

        inv.status = InvocationStatus.Failed;
        emit InvocationFailed(invocationId, reason);
    }

    // --- internal helpers ---

    function _validateInputConditions(address[] memory resolvers) internal view {
        uint256 len = resolvers.length;
        // Input conditions are validated before escrow creation; use sentinel escrowId = 0
        for (uint256 i = 0; i < len; i++) {
            address resolver = resolvers[i];
            if (resolver != address(0) && !IConditionResolver(resolver).isConditionMet(0)) {
                revert InputConditionsNotMet(0, resolver);
            }
        }
    }

    function _validateOutputConditions(address[] memory resolvers, uint256 escrowId) internal view {
        uint256 len = resolvers.length;
        for (uint256 i = 0; i < len; i++) {
            address resolver = resolvers[i];
            if (resolver != address(0) && !IConditionResolver(resolver).isConditionMet(escrowId)) {
                revert OutputConditionsNotMet(escrowId, resolver);
            }
        }
    }

    function _attachCoverages(
        IAgentCoverageManager manager,
        uint256 escrowId,
        CoverageParam[] calldata params
    ) internal returns (uint256[] memory coverageIds) {
        uint256 len = params.length;
        if (len == 0) revert EmptyCoverageParams();

        coverageIds = new uint256[](len);
        for (uint256 i = 0; i < len; i++) {
            CoverageParam memory p = params[i];
            coverageIds[i] = manager.purchaseCoverage(
                escrowId,
                p.pool,
                p.policy,
                p.coverageAmount,
                p.coverageExpiry,
                p.policyData,
                p.riskProof
            );
        }
    }

    function _verifyAgentSignature(address agent, bytes32 hash, bytes memory sig) internal pure {
        if (sig.length != 65) revert InvalidSignature();

        bytes32 r;
        bytes32 s;
        uint8 v;
        assembly {
            r := mload(add(sig, 32))
            s := mload(add(sig, 64))
            v := byte(0, mload(add(sig, 96)))
        }

        if (v < 27) v += 27;

        address signer = ecrecover(hash, v, r, s);
        if (signer != agent) revert InvalidSignature();
    }
}
