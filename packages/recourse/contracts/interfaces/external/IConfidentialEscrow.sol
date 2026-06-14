// SPDX-License-Identifier: FSL-1.1-ALv2
pragma solidity ^0.8.24;

import {euint64, eaddress} from "@fhenixprotocol/cofhe-contracts/FHE.sol";

/// @title IConfidentialEscrow — Recourse-side view of the FHE escrow engine
/// @notice External-facing subset of the confidential escrow contract that the recourse
///         package depends on. Mirrors a slice of the canonical `IConfidentialEscrow`
///         declared in the escrow package, exposing only the functions the
///         `CoverageManager` needs to call.
/// @dev When the canonical interface changes (e.g., new signature on `setUnderwriterFee`),
///      keep this stub in sync — both the signature and the NatSpec.
interface IConfidentialEscrow {
    /// @notice Checks whether an escrow has been created
    /// @param escrowId The escrow identifier to query
    /// @return True if the escrow exists
    function exists(uint256 escrowId) external view returns (bool);

    /// @notice Returns the encrypted target amount of an escrow
    /// @param escrowId The escrow identifier
    /// @return amount The encrypted target amount
    function getAmount(uint256 escrowId) external view returns (euint64 amount);

    /// @notice Stamps the underwriter fee at slot 2; restricted to the coverage manager
    /// @dev Branchless auth: `effectiveBps` is silently zeroed via `FHE.select` if `holder`
    ///      is neither the escrow owner nor caller. Sum-invariant violation also silently
    ///      caps via `FHE.select` (no revert to avoid leaking encrypted state).
    /// @param escrowId The escrow identifier the fee applies to
    /// @param holder The encrypted address of the coverage holder used for the auth check
    /// @param effectiveBps The encrypted fee in basis points computed by the coverage manager
    /// @param recipient The address that will receive the fee at redemption
    function setUnderwriterFee(uint256 escrowId, eaddress holder, euint64 effectiveBps, address recipient) external;
}
