// SPDX-License-Identifier: FSL-1.1-ALv2
pragma solidity ^0.8.24;

/// @title IEscrow — Recourse-side view of the plain (non-FHE) escrow engine
/// @notice External-facing subset of the plain escrow contract that the recourse
///         package depends on. Mirrors a slice of the canonical `IEscrow` declared
///         in the shared package, exposing only the functions the `CoverageManager`
///         needs to call.
/// @dev When the canonical interface changes (e.g., new signature on `setUnderwriterFee`),
///      keep this stub in sync — both the signature and the NatSpec.
interface IEscrow {
    /// @notice Checks whether an escrow has been created
    /// @param escrowId The escrow identifier to query
    /// @return True if the escrow exists
    function exists(uint256 escrowId) external view returns (bool);

    /// @notice Returns the total amount required to fully fund the escrow
    /// @param escrowId The escrow identifier
    /// @return The target amount
    function getAmount(uint256 escrowId) external view returns (uint256);

    /// @notice Stamps the underwriter fee at slot 2; restricted to the coverage manager
    /// @dev Branchless auth: if `holder` is neither the escrow owner nor caller, the fee
    ///      bps is silently zeroed (preserving privacy in the confidential variant).
    /// @param escrowId The escrow identifier the fee applies to
    /// @param holder The coverage holder used for the auth check
    /// @param effectiveBps The fee in basis points computed by the coverage manager
    /// @param recipient The address that will receive the fee at redemption
    function setUnderwriterFee(uint256 escrowId, address holder, uint16 effectiveBps, address recipient) external;
}
