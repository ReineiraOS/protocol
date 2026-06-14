// SPDX-License-Identifier: FSL-1.1-ALv2
// Copyright (c) 2026 Reineira Labs Limited All rights reserved.
pragma solidity ^0.8.24;

import {TestnetPausableBase} from "@reineira-os/shared/contracts/common/TestnetPausableBase.sol";
import {ITaskExecutor} from "../interfaces/core/ITaskExecutor.sol";
import {ITaskHandler} from "../interfaces/core/ITaskHandler.sol";
import {IOperatorRegistry} from "../interfaces/core/IOperatorRegistry.sol";
import {IFeeManager} from "../interfaces/core/IFeeManager.sol";
import {TaskLib} from "../libraries/TaskLib.sol";

contract TaskExecutor is ITaskExecutor, TestnetPausableBase {
    IOperatorRegistry public registry;
    IFeeManager public feeManager;

    mapping(bytes32 => address) private _handlers;

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor(address trustedForwarder_) TestnetPausableBase(trustedForwarder_) {
        _disableInitializers();
    }

    function initialize(address owner_, address registry_, address feeManager_) external initializer {
        if (registry_ == address(0)) revert ZeroAddress();

        __TestnetPausableBase_init(owner_);

        registry = IOperatorRegistry(registry_);
        if (feeManager_ != address(0)) {
            feeManager = IFeeManager(feeManager_);
        }
    }

    function executeTask(
        bytes32 taskType,
        bytes calldata payload
    ) external nonReentrant whenNotPaused returns (bytes memory result) {
        address handler = _handlers[taskType];
        if (handler == address(0)) revert UnknownTaskType();

        bytes32 taskHash = ITaskHandler(handler).getTaskHash(payload);

        if (!registry.canExecuteTask(msg.sender, taskHash)) {
            revert NotAuthorizedOperator();
        }

        result = ITaskHandler(handler).executeTask(payload);

        registry.markExecuted(taskHash, msg.sender);

        uint256 operatorFee = 0;
        if (address(feeManager) != address(0) && taskType == TaskLib.TASK_CCTP_RELAY) {
            uint256 amount = _extractAmount(payload);
            operatorFee = feeManager.calculateFee(amount);
            feeManager.collectFee(taskHash, msg.sender, amount);
        }

        emit TaskExecuted(taskType, taskHash, msg.sender, operatorFee);
    }

    function registerHandler(bytes32 taskType, address handler) external onlyOwner {
        if (handler == address(0)) revert ZeroAddress();

        bytes32 handlerTaskType = ITaskHandler(handler).taskType();
        if (handlerTaskType != taskType) revert InvalidHandler();

        _handlers[taskType] = handler;
        emit HandlerRegistered(taskType, handler);
    }

    function removeHandler(bytes32 taskType) external onlyOwner {
        delete _handlers[taskType];
        emit HandlerRemoved(taskType);
    }

    function setRegistry(address registry_) external onlyOwner {
        if (registry_ == address(0)) revert ZeroAddress();
        address oldRegistry = address(registry);
        registry = IOperatorRegistry(registry_);
        emit RegistryUpdated(oldRegistry, registry_);
    }

    function setFeeManager(address feeManager_) external onlyOwner {
        if (feeManager_ == address(0)) revert ZeroAddress();
        address oldFeeManager = address(feeManager);
        feeManager = IFeeManager(feeManager_);
        emit FeeManagerUpdated(oldFeeManager, feeManager_);
    }

    function getHandler(bytes32 taskType) external view returns (address) {
        return _handlers[taskType];
    }

    function _extractAmount(bytes calldata payload) private pure returns (uint256 amount) {
        // For CCTP payloads encoded as tuple (bytes,bytes), skip the 32-byte tuple offset
        // then decode (bytes message, bytes attestation) and extract amount at offset 216
        if (payload.length < 96) return 0;

        // Skip first 32 bytes (tuple offset pointer) and decode the inner data
        bytes calldata innerPayload = payload[32:];
        (bytes memory message, ) = abi.decode(innerPayload, (bytes, bytes));

        // Amount is at offset 216 in the CCTP message
        uint256 amountOffset = 216;
        if (message.length < amountOffset + 32) return 0;

        assembly {
            amount := mload(add(add(message, 32), amountOffset))
        }
    }
}
