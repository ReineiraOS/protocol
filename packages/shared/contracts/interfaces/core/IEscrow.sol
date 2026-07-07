// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 Reineira Labs Limited All rights reserved.
pragma solidity ^0.8.24;

import {IERC165} from "@openzeppelin/contracts/interfaces/IERC165.sol";
import {ICore} from "./ICore.sol";
import {IEscrowEvents} from "./IEscrowEvents.sol";

/// @title IEscrow — Core abstraction for escrow engines across funding modes
/// @notice Defines the lifecycle of an escrow: create, fund (possibly in parts), release.
///         This abstraction supports multiple funding modes: FHE confidential (ConfidentialEscrow),
///         future VirtualEscrow + IFundingSource (x402, fiat, attestation, trusted claim).
///         The budget() method returns opaque bytes to support both encrypted and plaintext amounts.
/// @dev Implementations must follow checks-effects-interactions and use SafeERC20 for
///      token transfers. Inherits ICore for shared initialization events and errors.
///      v3 ships only ConfidentialEscrow; VirtualEscrow + IFundingSource planned for v0.3.
interface IEscrow is IERC165, ICore, IEscrowEvents {
    /// @notice Escrow lifecycle phases
    enum Phase {
        Open,
        Funded,
        Released,
        Refunded,
        Disputed
    }
    /// @notice Thrown when the caller is not the escrow owner
    error NotOwner();

    /// @notice Thrown when attempting to redeem an escrow that has not been fully funded
    error NotFullyPaid();

    /// @notice Thrown when attempting to redeem an escrow that has already been redeemed
    error AlreadyRedeemed();

    /// @notice Thrown when initData cannot be decoded
    error InvalidInitData();

    /// @notice Thrown when fundingProof is invalid
    error InvalidFundingProof();

    /// @notice Thrown when amount encoding is invalid
    error InvalidAmountEncoding();

    /// @notice Opens a new escrow with opaque initialization data (abstraction layer)
    /// @dev If a non-zero `resolver` is supplied, stamps the condition fee from
    ///      `resolver.getConditionFee` at the condition slot.
    ///      initData encoding is implementation-specific:
    ///      - ConfidentialEscrow: abi.encode(InEaddress owner, InEuint64 amount)
    ///      - Future VirtualEscrow: abi.encode(address owner, uint256 amount, ...)
    /// @param initData Opaque bytes containing owner, amount, and impl-specific params
    /// @param resolver Optional condition resolver to gate redemption (zero address skips)
    /// @param resolverData Encoded configuration forwarded to the resolver's `onConditionSet`
    /// @return escrowId The assigned escrow identifier
    function create(
        bytes calldata initData,
        address resolver,
        bytes calldata resolverData
    ) external returns (uint256 escrowId);

    /// @notice Opens a new escrow (legacy typed signature for backward compatibility)
    /// @dev Kept for existing callers; new code should use create(bytes, address, bytes)
    /// @param owner_ The address that will be entitled to redeem the escrow
    /// @param amount_ The total amount required to fully fund the escrow
    /// @param resolver Optional condition resolver to gate redemption (zero address skips)
    /// @param resolverData Encoded configuration forwarded to the resolver's `onConditionSet`
    /// @return escrowId The assigned escrow identifier
    function create(
        address owner_,
        uint256 amount_,
        address resolver,
        bytes calldata resolverData
    ) external returns (uint256 escrowId);

    /// @notice Deposits funds into an existing escrow with opaque funding proof
    /// @dev fundingProof encoding is implementation-specific:
    ///      - ConfidentialEscrow: abi.encode(InEuint64 encryptedPayment)
    ///      - Future VirtualEscrow: abi.encode(uint256 amount) or funding-source-specific proof
    /// @param escrowId The target escrow identifier
    /// @param fundingProof Opaque bytes containing payment amount or funding proof
    function fund(uint256 escrowId, bytes calldata fundingProof) external;

    /// @notice Checks if an escrow has been fully funded
    /// @param escrowId The escrow identifier
    /// @return True if paidAmount >= amount
    function isFunded(uint256 escrowId) external view returns (bool);

    /// @notice Returns the budget (target amount) as opaque bytes
    /// @dev This is the key abstraction: ConfidentialEscrow returns abi.encode(euint64),
    ///      future VirtualEscrow returns abi.encode(uint64) or funding-source-specific encoding.
    ///      Consumers decode based on a type discriminator or known implementation.
    /// @param escrowId The escrow identifier
    /// @return Opaque bytes encoding the budget (FHE handle, plaintext, or other)
    function budget(uint256 escrowId) external view returns (bytes memory);

    /// @notice Releases funds from an escrow to a recipient with opaque amount encoding
    /// @dev amount encoding is implementation-specific:
    ///      - ConfidentialEscrow: abi.encode(euint64) or empty for full redemption
    ///      - Future VirtualEscrow: abi.encode(uint256) or empty for full redemption
    /// @param escrowId The escrow identifier
    /// @param recipient The address to receive the funds
    /// @param amount Opaque bytes encoding the amount to release (empty = full)
    function release(uint256 escrowId, address recipient, bytes calldata amount) external;

    /// @notice Returns the current phase of an escrow
    /// @param escrowId The escrow identifier
    /// @return The current Phase enum value
    function status(uint256 escrowId) external view returns (Phase);

    /// @notice Redeems a fully funded escrow (legacy method for backward compatibility)
    /// @param escrowId The escrow identifier to redeem
    function redeem(uint256 escrowId) external;

    /// @notice Redeems multiple fully funded escrows in a single call
    /// @param escrowIds The escrow identifiers to redeem
    function redeemMultiple(uint256[] calldata escrowIds) external;

    /// @notice Checks whether an escrow has been created
    /// @param escrowId The escrow identifier to query
    /// @return True if the escrow exists
    function exists(uint256 escrowId) external view returns (bool);

    /// @notice Returns the number of escrows ever created
    /// @return The running counter of escrows
    function total() external view returns (uint256);

    /// @notice Assigns the coverage manager authorized to call `setUnderwriterFee`
    /// @param coverageManager The new coverage manager address
    function setCoverageManager(address coverageManager) external;

    /// @notice Returns the payment token bound to a specific escrow at creation
    /// @dev Escrows created without an explicit token fall back to the engine default.
    /// @param escrowId The escrow identifier
    /// @return The ERC20/FHERC20 token address used to fund and redeem this escrow
    function paymentTokenOf(uint256 escrowId) external view returns (address);

    /// @notice Adds a token to the per-escrow payment-token allow-list
    /// @dev Owner-only. Allowed tokens may be selected as the payment token at create.
    /// @param token The token address to allow (must be non-zero)
    function addAllowedToken(address token) external;

    /// @notice Removes a token from the per-escrow payment-token allow-list
    /// @dev Owner-only. Does not affect escrows already created with this token.
    /// @param token The token address to disallow
    function removeAllowedToken(address token) external;

    /// @notice Checks whether a token is on the per-escrow payment-token allow-list
    /// @param token The token address to query
    /// @return True if the token may be selected as a payment token at create
    function isAllowedToken(address token) external view returns (bool);
}
