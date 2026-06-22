// SPDX-License-Identifier: FSL-1.1-ALv2
// Copyright (c) 2026 Reineira Labs Limited All rights reserved.
pragma solidity ^0.8.24;

/// @title IAgentCoverageManager — Minimal coverage interface for AgentInvocationAdapter
/// @notice Abstracts coverage purchase so AgentInvocationAdapter can attach N coverages
///         without depending on the full confidential or plain coverage manager interface.
/// @dev The extended ConfidentialCoverageManager (AP-15) implements this interface.
interface IAgentCoverageManager {
    /// @notice Purchases coverage for an escrow
    /// @param escrowId The escrow being insured
    /// @param pool The pool backing the coverage
    /// @param policy The policy contract evaluating risk
    /// @param coverageAmount The coverage amount (plain uint256; FHE variant wraps in adapter)
    /// @param coverageExpiry Timestamp when coverage expires
    /// @param policyData Policy-specific configuration
    /// @param riskProof Proof data for risk evaluation
    /// @return coverageId The assigned coverage identifier
    function purchaseCoverage(
        uint256 escrowId,
        address pool,
        address policy,
        uint256 coverageAmount,
        uint256 coverageExpiry,
        bytes calldata policyData,
        bytes calldata riskProof
    ) external returns (uint256 coverageId);
}
