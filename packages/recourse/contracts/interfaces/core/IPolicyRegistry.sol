// SPDX-License-Identifier: FSL-1.1-ALv2
// Copyright (c) 2026 Reineira Labs Limited All rights reserved.
pragma solidity ^0.8.24;

import {ICore} from "@reineira-os/shared/contracts/interfaces/core/ICore.sol";
import {IPolicyRegistryEvents} from "@reineira-os/shared/contracts/interfaces/core/IPolicyRegistryEvents.sol";

/// @title IPolicyRegistry — Central registry for IUnderwriterPolicy contracts (plain variant)
/// @notice Developers deploy their own IUnderwriterPolicy implementation, then register
///         it here. RecoursePool.addPolicy() validates against this registry.
///         For the confidential variant, see IConfidentialPolicyRegistry.
interface IPolicyRegistry is ICore, IPolicyRegistryEvents {
    /// @notice Registers a deployed IUnderwriterPolicy contract
    /// @param policy The policy contract address to register
    /// @return policyId Sequential policy identifier
    function registerPolicy(address policy) external returns (uint256 policyId);

    /// @notice Returns the policy address for a given policyId
    /// @param policyId The policy identifier to look up
    function policy(uint256 policyId) external view returns (address);

    /// @notice Returns the total number of policies registered
    function policyCount() external view returns (uint256);

    /// @notice Returns true if the address is a registered policy
    /// @param policy The address to check
    function isPolicy(address policy) external view returns (bool);
}
