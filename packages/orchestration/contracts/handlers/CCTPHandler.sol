// SPDX-License-Identifier: FSL-1.1-ALv2
// Copyright (c) 2026 Reineira Labs Limited All rights reserved.
pragma solidity ^0.8.24;

import {TestnetPausableBase} from "@reineira-os/shared/contracts/common/TestnetPausableBase.sol";
import {ICCTPHandler} from "../interfaces/handlers/ICCTPHandler.sol";
import {ICCTPV2EscrowReceiver} from "@reineira-os/shared/contracts/interfaces/external/ICCTPV2EscrowReceiver.sol";
import {CCTPMessageLib} from "../libraries/CCTPMessageLib.sol";
import {TaskLib} from "../libraries/TaskLib.sol";

contract CCTPHandler is ICCTPHandler, TestnetPausableBase {
    using CCTPMessageLib for bytes;

    ICCTPV2EscrowReceiver public escrowReceiver;
    address public executor;

    error NotExecutor();

    modifier onlyExecutor() {
        if (msg.sender != executor) revert NotExecutor();
        _;
    }

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor(address trustedForwarder_) TestnetPausableBase(trustedForwarder_) {
        _disableInitializers();
    }

    function initialize(address owner_, address escrowReceiver_, address executor_) external initializer {
        if (escrowReceiver_ == address(0)) revert CCTPMessageLib.MalformedMessage();
        if (executor_ == address(0)) revert CCTPMessageLib.MalformedMessage();

        __TestnetPausableBase_init(owner_);

        escrowReceiver = ICCTPV2EscrowReceiver(escrowReceiver_);
        executor = executor_;
    }

    function executeTask(bytes calldata payload) external onlyExecutor whenNotPaused returns (bytes memory) {
        CCTPPayload memory cctpPayload = abi.decode(payload, (CCTPPayload));

        bytes32 messageHash = cctpPayload.message.extractMessageHash();
        uint256 escrowId = cctpPayload.message.extractEscrowId();
        uint256 amount = cctpPayload.message.extractAmount();

        escrowReceiver.settle(cctpPayload.message, cctpPayload.attestation);

        emit EscrowSettled(messageHash, escrowId, amount);

        return abi.encode(escrowId, amount);
    }

    function validateTask(bytes calldata payload) external pure returns (bool) {
        if (payload.length < 64) return false;

        CCTPPayload memory cctpPayload = abi.decode(payload, (CCTPPayload));
        return cctpPayload.message.validate();
    }

    function getTaskHash(bytes calldata payload) external pure returns (bytes32) {
        CCTPPayload memory cctpPayload = abi.decode(payload, (CCTPPayload));
        return cctpPayload.message.extractMessageHash();
    }

    function taskType() external pure returns (bytes32) {
        return TaskLib.TASK_CCTP_RELAY;
    }

    function setEscrowReceiver(address receiver) external onlyOwner {
        if (receiver == address(0)) revert CCTPMessageLib.MalformedMessage();
        address oldReceiver = address(escrowReceiver);
        escrowReceiver = ICCTPV2EscrowReceiver(receiver);
        emit EscrowReceiverUpdated(oldReceiver, receiver);
    }

    function setExecutor(address executor_) external onlyOwner {
        if (executor_ == address(0)) revert CCTPMessageLib.MalformedMessage();
        address oldExecutor = executor;
        executor = executor_;
        emit ExecutorUpdated(oldExecutor, executor_);
    }
}
