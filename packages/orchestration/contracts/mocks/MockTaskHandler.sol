// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {ITaskHandler} from "../interfaces/core/ITaskHandler.sol";

contract MockTaskHandler is ITaskHandler {
    bytes32 private _taskType;
    bool public shouldFail;

    constructor(bytes32 taskType_) {
        _taskType = taskType_;
    }

    function executeTask(bytes calldata) external view returns (bytes memory) {
        if (shouldFail) revert("MockTaskHandler: execution failed");
        return "";
    }

    function validateTask(bytes calldata) external pure returns (bool) {
        return true;
    }

    function getTaskHash(bytes calldata payload) external pure returns (bytes32) {
        return keccak256(payload);
    }

    function taskType() external view returns (bytes32) {
        return _taskType;
    }

    function setShouldFail(bool fail) external {
        shouldFail = fail;
    }
}
