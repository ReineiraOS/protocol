// SPDX-License-Identifier: FSL-1.1-ALv2
// Copyright (c) 2026 Reineira Labs Limited All rights reserved.
pragma solidity ^0.8.25;

import {euint64, ebool, eaddress, InEuint64, InEaddress} from "@fhenixprotocol/cofhe-contracts/FHE.sol";
import {IFHERC20} from "fhenix-confidential-contracts/contracts/interfaces/IFHERC20.sol";
import {ICore} from "@reineira-os/shared/contracts/interfaces/core/ICore.sol";
import {IEscrowEvents} from "@reineira-os/shared/contracts/interfaces/core/IEscrowEvents.sol";

/// @title IConfidentialEscrow
/// @notice FHE-encrypted variant of IEscrow. Owners, amounts, paid amounts, and fee
///         basis points are stored as encrypted handles. Fees are stamped in encrypted
///         bps at creation/condition-set/coverage-purchase time and distributed
///         proportionally to the paid amount on redeem.
/// @dev FHE specifics:
///      - Auth checks use `FHE.eq` + `FHE.select` (no plaintext branching)
///      - Failed redeems silently transfer zero (no `revert` to avoid leaking state)
///      - Sum-invariant enforcement uses `FHE.select` silent cap, not `revert`
///      For the plain variant, see IEscrow.
interface IConfidentialEscrow is ICore, IEscrowEvents {
    /// @notice The FHERC20 token used to fund escrows in this engine
    /// @return The FHERC20 payment token contract
    function paymentToken() external view returns (IFHERC20);

    /// @notice Opens a new escrow with an encrypted owner and amount
    /// @dev If a non-zero `resolver` is supplied, stamps the condition fee at the condition slot.
    /// @param encryptedOwner The encrypted address of the escrow owner
    /// @param encryptedAmount The encrypted total amount required to fully fund the escrow
    /// @param resolver Optional condition resolver (zero address skips)
    /// @param resolverData Encoded configuration forwarded to the resolver's `onConditionSet`
    /// @return escrowId The assigned escrow identifier
    function create(
        InEaddress calldata encryptedOwner,
        InEuint64 calldata encryptedAmount,
        address resolver,
        bytes calldata resolverData
    ) external returns (uint256 escrowId);

    /// @notice Funds an escrow with an encrypted payment amount
    /// @param escrowId The escrow to fund
    /// @param encryptedPayment The encrypted payment amount
    function fund(uint256 escrowId, InEuint64 calldata encryptedPayment) external;

    /// @notice Funds an escrow using an existing encrypted amount handle
    /// @param escrowId The escrow to fund
    /// @param amount The encrypted amount handle
    function fundFrom(uint256 escrowId, euint64 amount) external;

    /// @notice Redeems a single escrow, distributing stamped fees and forwarding the net to the owner
    /// @dev Always succeeds at the call level; silently transfers zero if auth fails
    /// @param escrowId The escrow to redeem
    function redeem(uint256 escrowId) external;

    /// @notice Redeems multiple escrows in a single transaction
    /// @param escrowIds The escrows to redeem
    function redeemMultiple(uint256[] calldata escrowIds) external;

    /// @notice Checks whether an escrow has been created
    /// @param escrowId The escrow identifier to query
    /// @return True if the escrow exists
    function exists(uint256 escrowId) external view returns (bool);

    /// @notice Returns the encrypted owner of an escrow
    /// @param escrowId The escrow identifier
    /// @return owner The encrypted owner address
    function getOwner(uint256 escrowId) external view returns (eaddress owner);

    /// @notice Returns the encrypted target amount of an escrow
    /// @param escrowId The escrow identifier
    /// @return amount The encrypted target amount
    function getAmount(uint256 escrowId) external view returns (euint64 amount);

    /// @notice Returns the encrypted amount paid toward an escrow
    /// @param escrowId The escrow identifier
    /// @return paidAmount The encrypted paid amount
    function getPaidAmount(uint256 escrowId) external view returns (euint64 paidAmount);

    /// @notice Returns the encrypted redemption status of an escrow
    /// @param escrowId The escrow identifier
    /// @return isRedeemed The encrypted boolean indicating redemption status
    function getRedeemedStatus(uint256 escrowId) external view returns (ebool isRedeemed);

    /// @notice Returns the total number of escrows ever created
    /// @return count The running counter of escrows
    function total() external view returns (uint256 count);

    /// @notice Returns the encrypted caller address stored during escrow creation
    /// @param escrowId The escrow identifier
    /// @return The encrypted caller address
    function getCaller(uint256 escrowId) external view returns (eaddress);

    /// @notice Assigns the coverage manager authorized to call `setUnderwriterFee`
    /// @param coverageManager The new coverage manager address
    function setCoverageManager(address coverageManager) external;

    /// @notice Stamps the underwriter fee at the underwriter slot; restricted to the coverage manager
    /// @dev Branchless auth: `effectiveBps` is silently zeroed via `FHE.select` if `holder`
    ///      is neither the escrow owner nor caller. Sum-invariant violation also silently
    ///      caps via `FHE.select` (no revert to avoid leaking encrypted state).
    /// @param escrowId The escrow identifier the fee applies to
    /// @param holder The encrypted address of the policy holder used for the auth check
    /// @param effectiveBps The encrypted fee in basis points computed by the coverage manager
    /// @param recipient The address that will receive the fee at redemption
    function setUnderwriterFee(uint256 escrowId, eaddress holder, euint64 effectiveBps, address recipient) external;

    /// @notice Reads the stamped fee for a given escrow and fee kind
    /// @param escrowId The escrow identifier
    /// @param kind The fee kind
    /// @return bps The encrypted fee in basis points
    /// @return recipient The address that will receive the fee at redemption
    /// @return set True if the fee has been stamped
    function getFee(uint256 escrowId, uint8 kind) external view returns (euint64 bps, address recipient, bool set);

    /// @notice Returns the running sum of stamped basis points for an escrow (encrypted)
    /// @param escrowId The escrow identifier
    /// @return The encrypted sum of all stamped bps; bounded by `MAX_TOTAL_BPS = 10000` invariant
    function getTotalStampedBps(uint256 escrowId) external view returns (euint64);
}
