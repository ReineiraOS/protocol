// SPDX-License-Identifier: FSL-1.1-ALv2
// Copyright (c) 2026 Reineira Labs Limited All rights reserved.
pragma solidity ^0.8.24;

/// @title IYieldAdapter
/// @notice Normalized surface a StrategyRouter uses to deploy idle recourse-pool liquidity
///         into an external yield venue (e.g. AAVE, a Morpho/ERC-4626 vault). One adapter
///         wraps one venue and one underlying asset. Implementations MUST value positions in
///         a manipulation-resistant way (e.g. ERC-4626 `convertToAssets`, AAVE scaled balance
///         times liquidity index) and MUST tolerate venue illiquidity on withdrawal.
interface IYieldAdapter {
    /// @notice Emitted when `assets` of the underlying are supplied to the venue.
    event Deposited(uint256 assets);

    /// @notice Emitted when `assets` of the underlying are withdrawn from the venue.
    event Withdrawn(uint256 assets);

    /// @notice The underlying ERC-20 asset this adapter accepts.
    function asset() external view returns (address);

    /// @notice Current value of the adapter's venue position, denominated in `asset()`.
    function totalAssets() external view returns (uint256);

    /// @notice Amount currently withdrawable, bounded by available venue liquidity.
    function maxWithdraw() external view returns (uint256);

    /// @notice Supply `assets` of the underlying to the venue. Caller must have approved this adapter.
    function deposit(uint256 assets) external;

    /// @notice Withdraw up to `assets` from the venue to `receiver`.
    /// @return withdrawn The amount actually withdrawn, which may be less than requested if the
    ///         venue cannot fully honor the request.
    function withdraw(uint256 assets, address receiver) external returns (uint256 withdrawn);
}
