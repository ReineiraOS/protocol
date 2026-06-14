// SPDX-License-Identifier: FSL-1.1-ALv2
// Copyright (c) 2026 Reineira Labs Limited All rights reserved.
pragma solidity ^0.8.24;

import {IERC20} from "@openzeppelin/contracts/interfaces/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IYieldAdapter} from "../interfaces/plugins/IYieldAdapter.sol";

/// @dev Test-only yield venue. Holds the underlying directly; yield is simulated by minting
///      extra underlying into the adapter, and illiquidity by setting a consumable liquidity
///      budget via {setLiquidity}.
contract MockYieldAdapter is IYieldAdapter {
    using SafeERC20 for IERC20;

    IERC20 private immutable _asset;

    bool private _liquidityCapped;
    uint256 private _liquidityBudget;

    constructor(IERC20 asset_) {
        _asset = asset_;
    }

    function asset() external view returns (address) {
        return address(_asset);
    }

    function totalAssets() public view returns (uint256) {
        return _asset.balanceOf(address(this));
    }

    function maxWithdraw() public view returns (uint256) {
        uint256 held = totalAssets();
        if (!_liquidityCapped) {
            return held;
        }
        return _liquidityBudget < held ? _liquidityBudget : held;
    }

    function deposit(uint256 assets) external {
        _asset.safeTransferFrom(msg.sender, address(this), assets);
        emit Deposited(assets);
    }

    function withdraw(uint256 assets, address receiver) external returns (uint256 withdrawn) {
        uint256 available = maxWithdraw();
        withdrawn = assets < available ? assets : available;
        if (_liquidityCapped) {
            _liquidityBudget -= withdrawn;
        }
        _asset.safeTransfer(receiver, withdrawn);
        emit Withdrawn(withdrawn);
    }

    /// @dev Simulate constrained venue liquidity: caps and consumes a withdrawable budget.
    function setLiquidity(uint256 budget) external {
        _liquidityCapped = true;
        _liquidityBudget = budget;
    }
}
