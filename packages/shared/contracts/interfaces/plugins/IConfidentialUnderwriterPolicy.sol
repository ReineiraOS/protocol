// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 Reineira Labs Limited All rights reserved.
pragma solidity ^0.8.24;

import {ebool, euint64} from "@fhenixprotocol/cofhe-contracts/FHE.sol";
import {IERC165} from "@openzeppelin/contracts/utils/introspection/IERC165.sol";

/// @title IConfidentialUnderwriterPolicy — Pluggable risk evaluation and dispute resolution (FHE variant)
/// @notice Implement this interface to define a complete underwriter policy
///         for the confidential Recourse protocol. Each underwriter deploys their own policy
///         that determines:
///         1. How coverage-specific data is registered (e.g., dispute identifiers)
///         2. How risk is evaluated from proof data (e.g., zkTLS/zkFetch attestations)
///         3. How disputes are judged when claims are filed
/// @dev Return values are encrypted to prevent on-chain data leakage.
///      Must implement ERC-165 so IConfidentialPolicyRegistry can validate the interface.
///      For the plain (mainnet launch) variant see {IUnderwriterPolicy}.
interface IConfidentialUnderwriterPolicy is IERC165 {
    /// @notice Called by CoverageManager when coverage is created to register policy-specific data
    /// @param coverageId The coverage identifier
    /// @param data Policy-specific configuration data (e.g., PayPal dispute ID)
    function onPolicySet(uint256 coverageId, bytes calldata data) external;

    /// @notice Evaluates risk from proof data and returns an encrypted risk score
    /// @param escrowId The escrow being evaluated
    /// @param riskProof Opaque proof bytes (e.g., zkFetch attestation of dispute data)
    /// @return riskScore Encrypted risk score used to compute the premium
    function evaluateRisk(uint256 escrowId, bytes calldata riskProof) external returns (euint64 riskScore);

    /// @notice Evaluates whether a dispute is valid
    /// @param coverageId The coverage being disputed
    /// @param disputeProof Opaque proof bytes (e.g., zkFetch attestation of dispute resolution)
    /// @return valid Encrypted boolean — true if the dispute is upheld
    function judge(uint256 coverageId, bytes calldata disputeProof) external returns (ebool valid);
}
