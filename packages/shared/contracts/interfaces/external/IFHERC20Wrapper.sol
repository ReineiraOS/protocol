// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.24;

import {IFHERC20} from "fhenix-confidential-contracts/contracts/interfaces/IFHERC20.sol";
import {euint64} from "@fhenixprotocol/cofhe-contracts/FHE.sol";

/// @title IFHERC20Wrapper
/// @notice Interface for wrapping standard ERC20 tokens into confidential FHERC20 tokens
/// @dev Enables conversion between public ERC20 balances and private FHE-encrypted balances
interface IFHERC20Wrapper is IFHERC20 {
    /// @notice Wraps public ERC20 tokens into confidential tokens
    /// @param to The recipient address for the wrapped confidential tokens
    /// @param amount The amount of ERC20 tokens to wrap (in public form)
    function wrap(address to, uint256 amount) external;

    /// @notice Unwraps confidential tokens back to public ERC20 tokens
    /// @param from The address to deduct confidential tokens from
    /// @param to The recipient address for the unwrapped ERC20 tokens
    /// @param amount The FHE-encrypted amount to unwrap
    function unwrap(address from, address to, euint64 amount) external;

    /// @notice Returns the conversion rate between ERC20 decimals and confidential token decimals
    /// @return The multiplier used for decimal conversion (e.g., 1e12 for 18->6 decimal conversion)
    function rate() external view returns (uint256);
}
