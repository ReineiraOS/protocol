// SPDX-License-Identifier: FSL-1.1-ALv2
// Copyright (c) 2026 Reineira Labs Limited All rights reserved.
pragma solidity ^0.8.24;

import {IFHERC20} from "fhenix-confidential-contracts/contracts/interfaces/IFHERC20.sol";
import {ICore} from "@reineira-os/shared/contracts/interfaces/core/ICore.sol";
import {IPoolFactoryEvents} from "@reineira-os/shared/contracts/interfaces/core/IPoolFactoryEvents.sol";

/// @title IConfidentialPoolFactory — Central registry for recourse pools (FHE variant)
/// @notice Anyone may call createPool() to deploy a new ConfidentialRecoursePool. The
///         caller becomes the immutable Pool Creator; they choose the initial Pool
///         Manager (defaults to the creator), an optional Guardian, and whether the
///         pool is open (anyone may purchase coverage) or private (purchase requires
///         a Manager-signed EIP-712 voucher). See whitepaper §7.2 / §7.10.
interface IConfidentialPoolFactory is ICore, IPoolFactoryEvents {
    /// @notice Adds a token to the allowlist (owner only)
    /// @param token The token address to allow
    function addAllowedToken(address token) external;

    /// @notice Removes a token from the allowlist (owner only)
    /// @param token The token address to remove
    function removeAllowedToken(address token) external;

    /// @notice Returns true if the token is in the allowlist
    function isAllowedToken(address token) external view returns (bool);

    /// @notice Deploys a new ConfidentialRecoursePool with the caller as the immutable Pool Creator
    /// @param paymentToken The FHERC20 token the pool accepts (must be in allowlist)
    /// @param initialManager Initial Pool Manager; if address(0), defaults to the caller
    /// @param guardian Pool Guardian; zero address allowed (no in-pool powers in v1)
    /// @param isOpen True for open pools (anyone may purchase coverage); false for
    ///        private pools (purchase requires a Manager-signed EIP-712 voucher).
    ///        This flag is immutable for the lifetime of the pool.
    /// @return poolId Sequential pool identifier
    /// @return pool Address of the deployed ConfidentialRecoursePool
    function createPool(
        IFHERC20 paymentToken,
        address initialManager,
        address guardian,
        bool isOpen
    ) external returns (uint256 poolId, address pool);

    /// @notice Returns the pool address for a given poolId
    function pool(uint256 poolId) external view returns (address);

    /// @notice Returns the total number of pools created
    function poolCount() external view returns (uint256);

    /// @notice Returns true if the address is a pool deployed by this factory
    function isPool(address pool) external view returns (bool);
}
