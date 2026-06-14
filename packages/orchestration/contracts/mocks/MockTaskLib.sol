// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {TaskLib} from "../libraries/TaskLib.sol";

contract MockTaskLib {
    function TASK_CCTP_RELAY() external pure returns (bytes32) {
        return TaskLib.TASK_CCTP_RELAY;
    }

    function TASK_AUTOMATION() external pure returns (bytes32) {
        return TaskLib.TASK_AUTOMATION;
    }

    function TASK_AGENT_CALL() external pure returns (bytes32) {
        return TaskLib.TASK_AGENT_CALL;
    }

    function generateTaskHash(bytes32 taskType, bytes calldata payload) external pure returns (bytes32) {
        return TaskLib.generateTaskHash(taskType, payload);
    }

    function generateTaskHashFromMessage(bytes32 taskType, bytes32 messageHash) external pure returns (bytes32) {
        return TaskLib.generateTaskHashFromMessage(taskType, messageHash);
    }
}
