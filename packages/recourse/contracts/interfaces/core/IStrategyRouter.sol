// SPDX-License-Identifier: FSL-1.1-ALv2
// Copyright (c) 2026 Reineira Labs Limited All rights reserved.
pragma solidity ^0.8.24;

import {ICore} from "@reineira-os/shared/contracts/interfaces/core/ICore.sol";

/// @title IStrategyRouter
/// @notice Manager surface for routing idle recourse-pool liquidity into pluggable
///         yield venues (`IYieldAdapter`). v1 is owner-gated (single Manager); the
///         pool↔router operational hook and the full role split (Allocator / Guardian)
///         are deferred per ADR-0002.
///
///         Mutability follows the ADR-0002 matrix: actions that **increase external
///         risk** (attach adapter, raise `maxDebt`, raise `maxDeploymentBps`) are
///         **timelocked**; actions that **reduce external risk** (detach, lower caps)
///         are **instant**.
interface IStrategyRouter is ICore {
    // --- events ---

    event AdapterAttachSubmitted(address indexed adapter, uint256 unlockAt);
    event AdapterAttached(address indexed adapter);
    event AdapterDetached(address indexed adapter);

    event MaxDebtRaiseSubmitted(address indexed adapter, uint256 newCap, uint256 unlockAt);
    event MaxDebtSet(address indexed adapter, uint256 newCap);

    event MaxDeploymentBpsRaiseSubmitted(uint16 newBps, uint256 unlockAt);
    event MaxDeploymentBpsSet(uint16 newBps);

    event ClaimsBufferBpsSet(uint16 newBps);
    event MinIdleReserveSet(uint256 newReserve);

    event Deposited(address indexed adapter, uint256 assets);
    event Withdrawn(address indexed adapter, uint256 assets);

    // --- errors ---

    error InvalidAdapter();
    error AdapterAssetMismatch();
    error AdapterAlreadyAttached();
    error AdapterNotAttached();
    error AttachNotPending();
    error MaxDebtRaiseNotPending();
    error MaxDeploymentBpsRaiseNotPending();
    error TimelockNotElapsed(uint256 unlockAt);
    error MaxAdaptersReached();
    error NotARaise();
    error NotALower();
    error InvalidBps(uint16 bps);
    error AdapterMaxDebtExceeded(uint256 requested, uint256 available);
    error AdapterStillHasDebt(uint256 deployed);

    // --- views ---

    /// @notice Timelock between submit and execute for risk-increasing actions.
    function TIMELOCK_DELAY() external view returns (uint256);

    /// @notice Upper bound on the number of attached adapters.
    function MAX_ADAPTERS() external view returns (uint16);

    /// @notice The underlying ERC-20 asset this router routes.
    function asset() external view returns (address);

    function isAdapterAttached(address adapter) external view returns (bool);
    function adapters() external view returns (address[] memory);

    function maxDebt(address adapter) external view returns (uint256);
    function deployed(address adapter) external view returns (uint256);
    function totalDeployed() external view returns (uint256);

    function maxDeploymentBps() external view returns (uint16);
    function claimsBufferBps() external view returns (uint16);
    function minIdleReserve() external view returns (uint256);

    function pendingAttach(address adapter) external view returns (uint256 unlockAt);
    function pendingMaxDebt(address adapter) external view returns (uint256 newCap, uint256 unlockAt);
    function pendingMaxDeploymentBps() external view returns (uint16 newBps, uint256 unlockAt);

    // --- adapter management ---

    /// @notice Queue an adapter for attachment. Anyone can `executeAttachAdapter` after the timelock.
    function submitAttachAdapter(address adapter) external;

    /// @notice Finalize an attachment after the timelock has elapsed.
    function executeAttachAdapter(address adapter) external;

    /// @notice Instantly detach an adapter (risk-reducing).
    function detachAdapter(address adapter) external;

    // --- caps ---

    /// @notice Queue an increase of an adapter's `maxDebt`.
    function submitMaxDebtRaise(address adapter, uint256 newCap) external;

    /// @notice Finalize a queued `maxDebt` increase after the timelock.
    function executeMaxDebtRaise(address adapter) external;

    /// @notice Instantly lower an adapter's `maxDebt` (risk-reducing).
    function lowerMaxDebt(address adapter, uint256 newCap) external;

    /// @notice Queue an increase of `maxDeploymentBps` (capped at `PoolRiskLib.MAX_DEPLOYMENT_CEILING_BPS`).
    function submitMaxDeploymentBpsRaise(uint16 newBps) external;

    /// @notice Finalize a queued `maxDeploymentBps` increase after the timelock.
    function executeMaxDeploymentBpsRaise() external;

    /// @notice Instantly lower `maxDeploymentBps` (risk-reducing).
    function lowerMaxDeploymentBps(uint16 newBps) external;

    function setClaimsBufferBps(uint16 newBps) external;
    function setMinIdleReserve(uint256 newReserve) external;

    // --- operations ---

    /// @notice Pull `amount` of `asset()` from the caller and supply it to `adapter`.
    /// @param  totalAssets         Caller-supplied pool valuation used for the reserve check.
    /// @param  outstandingCoverage Caller-supplied outstanding coverage used for the claims buffer.
    function deposit(address adapter, uint256 amount, uint256 totalAssets, uint256 outstandingCoverage) external;

    /// @notice Withdraw `amount` of `asset()` from `adapter` to `receiver`.
    /// @return withdrawn Actual amount withdrawn (may be less than requested if the venue is illiquid).
    function withdraw(address adapter, uint256 amount, address receiver) external returns (uint256 withdrawn);
}
