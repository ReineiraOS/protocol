// SPDX-License-Identifier: FSL-1.1-ALv2
// Copyright (c) 2026 Reineira Labs Limited All rights reserved.
pragma solidity ^0.8.24;

import {euint64, InEuint64} from "@fhenixprotocol/cofhe-contracts/FHE.sol";
import {IFHERC20} from "fhenix-confidential-contracts/contracts/interfaces/IFHERC20.sol";
import {ICore} from "@reineira-os/shared/contracts/interfaces/core/ICore.sol";
import {IRecoursePoolEvents} from "@reineira-os/shared/contracts/interfaces/core/IRecoursePoolEvents.sol";

/// @title IConfidentialRecoursePool — Per-pool liquidity container (FHE variant)
/// @notice Deployed by ConfidentialPoolFactory. Holds three roles per whitepaper §7.2:
///         - Creator (immutable): retains policy authorship (addPolicy/removePolicy)
///           across manager transfers; set at pool deployment by the factory caller.
///         - Manager (transferable): parameter custody, premium claims, signs
///           EIP-712 coverage-invite vouchers for closed pools.
///         - Guardian (set at init, no in-pool powers in v1): reserved for emergency
///           operations introduced in DEV-116.
///         LPs stake encrypted amounts; CoverageManager calls payClaim/receivePremium
///         on dispute resolution.
interface IConfidentialRecoursePool is ICore, IRecoursePoolEvents {
    /// @notice Returns the immutable Pool Creator address (whitepaper §7.2)
    function creator() external view returns (address);

    /// @notice Returns the current Pool Manager address (transferable, whitepaper §7.2)
    function manager() external view returns (address);

    /// @notice Returns the Guardian address (no in-pool powers in v1; reserved for DEV-116)
    function guardian() external view returns (address);

    /// @notice Returns whether the pool is open (anyone may purchase coverage) or
    ///         private (purchase requires an EIP-712 voucher signed by the Manager)
    /// @return open True when the pool is open; false when closed/private
    function isOpen() external view returns (bool open);

    /// @notice Returns the EIP-712 domain separator used for coverage-invite vouchers
    /// @dev Bound to chainId + this pool's address per OpenZeppelin EIP-712 v4 helper.
    ///      CoverageManager calls this to verify voucher signatures against the current Manager.
    function domainSeparator() external view returns (bytes32);

    /// @notice Transfers the Manager role to a new address (one-step, Manager-initiated)
    /// @param newManager New Manager address; must be non-zero and different from current
    /// @dev Reverts with ZeroAddress if newManager == address(0), SameAddress if no-op,
    ///      NotManager if caller is not the current Manager.
    function transferManager(address newManager) external;

    /// @notice Returns the FHERC20 token this pool accepts
    function paymentToken() external view returns (IFHERC20);

    /// @notice Returns the CoverageManager authorized to call payClaim/receivePremium
    function coverageManager() external view returns (address);

    /// @notice Adds an IConfidentialUnderwriterPolicy to the pool's allowed set (Creator only — §7.2)
    /// @param policy The policy contract address to allow
    function addPolicy(address policy) external;

    /// @notice Removes an IConfidentialUnderwriterPolicy from the pool's allowed set (Creator only — §7.2)
    /// @param policy The policy contract address to remove
    function removePolicy(address policy) external;

    /// @notice Returns true if the policy is allowed on this pool
    /// @param policy The policy contract address to check
    function isPolicy(address policy) external view returns (bool);

    /// @notice Stakes encrypted amount into this pool
    /// @param encryptedAmount Encrypted stake amount
    /// @return stakeId Identifier for the new stake position
    function stake(InEuint64 calldata encryptedAmount) external returns (uint256 stakeId);

    /// @notice Withdraws a stake position
    /// @param stakeId The stake position to withdraw
    function unstake(uint256 stakeId) external;

    /// @notice Called by CoverageManager when a dispute succeeds — pays claim from pool
    /// @param coverageId The coverage being claimed
    /// @param amount Encrypted claim amount
    /// @return actualPayout The actual encrypted amount transferred (capped by pool liquidity)
    function payClaim(uint256 coverageId, euint64 amount) external returns (euint64 actualPayout);

    /// @notice Called by CoverageManager when escrow premium fee is collected
    /// @param coverageId The coverage receiving the premium
    /// @param premium Encrypted premium amount
    function receivePremium(uint256 coverageId, euint64 premium) external;

    /// @notice Returns the encrypted amount for a given stake position
    /// @param stakeId The stake position to query
    function stakedAmount(uint256 stakeId) external view returns (euint64);

    /// @notice Returns the total encrypted liquidity available in the pool
    function totalLiquidity() external view returns (euint64);

    /// @notice Returns the encrypted rewards earned by a stake position
    /// @param stakeId The stake position to query
    function pendingRewards(uint256 stakeId) external view returns (euint64);

    /// @notice LP claims earned premium rewards for a stake position
    /// @param stakeId The stake position to claim rewards for
    function claimRewards(uint256 stakeId) external;

    /// @notice Manager claims their share of accumulated premiums (Manager only — §7.2)
    /// @param encryptedAmount Encrypted withdrawal amount
    function claimPremiums(InEuint64 calldata encryptedAmount) external;
}
