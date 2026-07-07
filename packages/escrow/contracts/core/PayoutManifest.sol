// SPDX-License-Identifier: BUSL-1.1
// Copyright (c) 2026 Reineira Labs Limited All rights reserved.
pragma solidity ^0.8.25;

import {FHE, euint64, InEuint64} from "@fhenixprotocol/cofhe-contracts/FHE.sol";
import {FHEMeta} from "@reineira-os/shared/contracts/common/FHEMeta.sol";
import {IEscrow} from "@reineira-os/shared/contracts/interfaces/core/IEscrow.sol";
import {TestnetCoreBase} from "@reineira-os/shared/contracts/common/TestnetCoreBase.sol";
import {IPayoutManifest} from "../interfaces/core/IPayoutManifest.sol";

contract PayoutManifest is IPayoutManifest, TestnetCoreBase {
    uint8 public constant MAX_GATES = 2;

    struct PayoutLine {
        euint64 amount;
        address recipient;
        uint8 requiredGateMask;
    }

    struct PayoutSchema {
        PayoutLine[] lines;
        mapping(uint256 => bool) released;
        bool exists;
    }

    /// @custom:storage-location erc7201:reineira.storage.PayoutManifest
    struct PayoutManifestStorage {
        mapping(bytes32 => mapping(uint8 => bool)) consumed;
        mapping(uint8 => address) gateCallers;
        mapping(uint256 => mapping(bytes32 => PayoutSchema)) schemas;
        IEscrow escrow;
    }

    bytes32 private constant PAYOUT_MANIFEST_STORAGE_LOCATION =
        0x1f9fb62f305306063fa95221f7263189160648be96caa38ffbb1f7e2e70dd900;

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor(address trustedForwarder_) TestnetCoreBase(trustedForwarder_) {
        _disableInitializers();
    }

    function initialize(address owner_, address escrow_) external initializer {
        if (escrow_ == address(0)) revert InvalidEscrow();
        __TestnetCoreBase_init(owner_);
        PayoutManifestStorage storage $ = _getPayoutManifestStorage();
        $.escrow = IEscrow(escrow_);
    }

    // ── Schema management ───────────────────────────────────────

    function registerSchema(
        uint256 escrowId,
        bytes32 invocationId,
        PayoutLineInput[] calldata lines
    ) external onlyOwner {
        uint256 lineCount = lines.length;
        if (lineCount == 0) revert EmptySchema();

        PayoutManifestStorage storage $ = _getPayoutManifestStorage();
        PayoutSchema storage schema = $.schemas[escrowId][invocationId];
        if (schema.exists) revert SchemaAlreadyExists(escrowId, invocationId);

        schema.exists = true;

        address sender = msg.sender;

        for (uint256 i = 0; i < lineCount; i++) {
            PayoutLineInput calldata input = lines[i];
            if (input.recipient == address(0)) revert InvalidRecipient(uint8(i));
            if (input.requiredGateMask == 0 || input.requiredGateMask > 3) {
                revert InvalidGateMask(uint8(i), input.requiredGateMask);
            }

            euint64 amount = FHEMeta.asEuint64(input.amount, sender);
            FHE.allowThis(amount);

            schema.lines.push(
                PayoutLine({amount: amount, recipient: input.recipient, requiredGateMask: input.requiredGateMask})
            );
        }

        emit SchemaRegistered(escrowId, invocationId, lineCount);
    }

    // ── Gate firing ───────────────────────────────────────────────

    function onGateFired(uint256 escrowId, bytes32 invocationId, uint8 gateId) external nonReentrant {
        // checks
        if (gateId >= MAX_GATES) revert InvalidGateId(gateId);

        PayoutManifestStorage storage $ = _getPayoutManifestStorage();
        if ($.gateCallers[gateId] != msg.sender) revert UnauthorizedGateCaller(gateId, msg.sender);
        if ($.consumed[invocationId][gateId]) revert GateAlreadyConsumed(invocationId, gateId);

        PayoutSchema storage schema = $.schemas[escrowId][invocationId];
        if (!schema.exists) revert SchemaNotFound(escrowId, invocationId);

        // effects
        $.consumed[invocationId][gateId] = true;
        uint8 consumedMask = _consumedMask(invocationId);

        uint256 lineCount = schema.lines.length;
        for (uint256 i = 0; i < lineCount; i++) {
            if (schema.released[i]) continue;

            PayoutLine storage line = schema.lines[i];
            if ((line.requiredGateMask & ~consumedMask) != 0) continue;

            schema.released[i] = true;

            // interactions: call IEscrow.release for each satisfied line
            bytes memory amountBytes = abi.encode(line.amount);
            $.escrow.release(escrowId, line.recipient, amountBytes);

            emit LineReleased(escrowId, invocationId, uint8(i), line.recipient);
        }

        emit GateFired(escrowId, invocationId, gateId);
    }

    // ── Admin ─────────────────────────────────────────────────────

    function setGateCaller(uint8 gateId, address caller) external onlyOwner {
        if (gateId >= MAX_GATES) revert InvalidGateId(gateId);
        _getPayoutManifestStorage().gateCallers[gateId] = caller;
    }

    function setEscrow(address escrow_) external onlyOwner {
        if (escrow_ == address(0)) revert InvalidEscrow();
        _getPayoutManifestStorage().escrow = IEscrow(escrow_);
    }

    // ── Views ─────────────────────────────────────────────────────

    function isGateConsumed(bytes32 invocationId, uint8 gateId) external view returns (bool) {
        return _getPayoutManifestStorage().consumed[invocationId][gateId];
    }

    function gateCaller(uint8 gateId) external view returns (address) {
        return _getPayoutManifestStorage().gateCallers[gateId];
    }

    function escrow() external view returns (address) {
        return address(_getPayoutManifestStorage().escrow);
    }

    function schemaExists(uint256 escrowId, bytes32 invocationId) external view returns (bool) {
        return _getPayoutManifestStorage().schemas[escrowId][invocationId].exists;
    }

    function getSchemaLine(
        uint256 escrowId,
        bytes32 invocationId,
        uint256 lineIndex
    ) external view returns (uint256 amount, address recipient, uint8 requiredGateMask) {
        PayoutSchema storage schema = _getPayoutManifestStorage().schemas[escrowId][invocationId];
        if (!schema.exists) revert SchemaNotFound(escrowId, invocationId);
        if (lineIndex >= schema.lines.length) revert InvalidSchemaLength();

        PayoutLine storage line = schema.lines[lineIndex];
        return (uint256(euint64.unwrap(line.amount)), line.recipient, line.requiredGateMask);
    }

    function isLineReleased(uint256 escrowId, bytes32 invocationId, uint256 lineIndex) external view returns (bool) {
        return _getPayoutManifestStorage().schemas[escrowId][invocationId].released[lineIndex];
    }

    function getSchemaLineCount(uint256 escrowId, bytes32 invocationId) external view returns (uint256) {
        PayoutSchema storage schema = _getPayoutManifestStorage().schemas[escrowId][invocationId];
        if (!schema.exists) revert SchemaNotFound(escrowId, invocationId);
        return schema.lines.length;
    }

    // ── Internal ──────────────────────────────────────────────────

    function _getPayoutManifestStorage() private pure returns (PayoutManifestStorage storage $) {
        assembly {
            $.slot := PAYOUT_MANIFEST_STORAGE_LOCATION
        }
    }

    function _consumedMask(bytes32 invocationId) private view returns (uint8 mask) {
        PayoutManifestStorage storage $ = _getPayoutManifestStorage();
        if ($.consumed[invocationId][0]) mask |= 1;
        if ($.consumed[invocationId][1]) mask |= 2;
    }
}
