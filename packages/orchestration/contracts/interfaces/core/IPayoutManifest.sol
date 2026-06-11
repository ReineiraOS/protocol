// SPDX-License-Identifier: BUSL-1.1
// Copyright (c) 2026 Reineira Labs Limited All rights reserved.
pragma solidity ^0.8.25;

import {InEuint64} from "@fhenixprotocol/cofhe-contracts/FHE.sol";

/// @title IPayoutManifest
/// @notice Interface for the declarative multi-recipient payout authority.
///         Holds per-invocation encrypted-amount / plaintext-recipient schema lines
///         and authorizes IEscrow.release calls when gates fire.
interface IPayoutManifest {
    /// @notice Emitted when a payout schema is registered for an escrow+invocation
    /// @param escrowId The escrow the schema applies to
    /// @param invocationId The unique invocation identifier
    /// @param lineCount Number of payout lines in the schema
    event SchemaRegistered(uint256 indexed escrowId, bytes32 indexed invocationId, uint256 lineCount);

    /// @notice Emitted when a gate fires for an invocation
    /// @param escrowId The escrow identifier
    /// @param invocationId The invocation identifier
    /// @param gateId The gate that fired
    event GateFired(uint256 indexed escrowId, bytes32 indexed invocationId, uint8 indexed gateId);

    /// @notice Emitted when a single schema line is released to a recipient
    /// @param escrowId The escrow identifier
    /// @param invocationId The invocation identifier
    /// @param lineIndex The index of the released line in the schema
    /// @param recipient The address that received the release
    event LineReleased(
        uint256 indexed escrowId,
        bytes32 indexed invocationId,
        uint8 indexed lineIndex,
        address recipient
    );

    /// @notice Thrown when attempting to fire a gate that has already been consumed for this invocation
    error GateAlreadyConsumed(bytes32 invocationId, uint8 gateId);

    /// @notice Thrown when a caller is not authorized to fire a gate
    error UnauthorizedGateCaller(uint8 gateId, address caller);

    /// @notice Thrown when a schema already exists for the given escrow+invocation
    error SchemaAlreadyExists(uint256 escrowId, bytes32 invocationId);

    /// @notice Thrown when a schema is not found for the given escrow+invocation
    error SchemaNotFound(uint256 escrowId, bytes32 invocationId);

    /// @notice Thrown when attempting to register an empty schema
    error EmptySchema();

    /// @notice Thrown when input arrays have mismatched lengths
    error InvalidSchemaLength();

    /// @notice Thrown when a line has an invalid gate mask
    error InvalidGateMask(uint8 lineIndex, uint8 gateMask);

    /// @notice Thrown when a line has a zero-address recipient
    error InvalidRecipient(uint8 lineIndex);

    /// @notice Thrown when an invalid gate id is provided
    error InvalidGateId(uint8 gateId);

    /// @notice Thrown when an invalid escrow address is provided
    error InvalidEscrow();

    /// @notice Input struct for schema registration
    struct PayoutLineInput {
        InEuint64 amount;
        address recipient;
        uint8 requiredGateMask;
    }

    /// @notice Maximum number of gates supported (2)
    function MAX_GATES() external view returns (uint8);

    /// @notice Initializes the contract with an owner and escrow reference
    /// @param owner_ The contract owner
    /// @param escrow_ The IEscrow contract to release funds from
    function initialize(address owner_, address escrow_) external;

    /// @notice Registers a declarative payout schema for an escrow+invocation
    /// @dev Owner-only. Verifies encrypted inputs and grants permanent FHE.allow.
    /// @param escrowId The escrow identifier
    /// @param invocationId The unique invocation identifier
    /// @param lines Array of payout lines (encrypted amount, recipient, gate mask)
    function registerSchema(uint256 escrowId, bytes32 invocationId, PayoutLineInput[] calldata lines) external;

    /// @notice Called by an authorized gate caller when a gate fires
    /// @dev Marks the gate consumed, then releases all satisfied schema lines.
    ///      Reverts if gate already consumed, caller unauthorized, or schema missing.
    /// @param escrowId The escrow identifier
    /// @param invocationId The unique invocation identifier
    /// @param gateId The gate that fired (0 or 1)
    function onGateFired(uint256 escrowId, bytes32 invocationId, uint8 gateId) external;

    /// @notice Sets the authorized caller for a gate
    /// @param gateId The gate identifier (0 or 1)
    /// @param caller The address authorized to fire this gate
    function setGateCaller(uint8 gateId, address caller) external;

    /// @notice Updates the IEscrow reference
    /// @param escrow_ The new escrow contract address
    function setEscrow(address escrow_) external;

    /// @notice Returns whether a gate has been consumed for an invocation
    function isGateConsumed(bytes32 invocationId, uint8 gateId) external view returns (bool);

    /// @notice Returns the authorized caller for a gate
    function gateCaller(uint8 gateId) external view returns (address);

    /// @notice Returns the IEscrow contract address
    function escrow() external view returns (address);

    /// @notice Returns whether a schema exists for an escrow+invocation
    function schemaExists(uint256 escrowId, bytes32 invocationId) external view returns (bool);

    /// @notice Returns a schema line at a given index
    /// @param escrowId The escrow identifier
    /// @param invocationId The invocation identifier
    /// @param lineIndex The line index
    /// @return amount The encrypted amount handle (as uint256 for interface compatibility)
    /// @return recipient The plaintext recipient address
    /// @return requiredGateMask The bitmask of required gates
    function getSchemaLine(
        uint256 escrowId,
        bytes32 invocationId,
        uint256 lineIndex
    ) external view returns (uint256 amount, address recipient, uint8 requiredGateMask);

    /// @notice Returns whether a specific line has been released
    function isLineReleased(uint256 escrowId, bytes32 invocationId, uint256 lineIndex) external view returns (bool);

    /// @notice Returns the number of lines in a schema
    function getSchemaLineCount(uint256 escrowId, bytes32 invocationId) external view returns (uint256);
}
