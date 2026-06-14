// SPDX-License-Identifier: FSL-1.1-ALv2
// Copyright (c) 2026 Reineira Labs Limited All rights reserved.
pragma solidity ^0.8.24;

library TaskLib {
    bytes32 public constant TASK_CCTP_RELAY = keccak256("CCTP_RELAY");
    bytes32 public constant TASK_AUTOMATION = keccak256("AUTOMATION");
    bytes32 public constant TASK_AGENT_CALL = keccak256("AGENT_CALL");

    function generateTaskHash(bytes32 taskType, bytes calldata payload) internal pure returns (bytes32) {
        return keccak256(abi.encodePacked(taskType, keccak256(payload)));
    }

    function generateTaskHashFromMessage(bytes32 taskType, bytes32 messageHash) internal pure returns (bytes32) {
        return keccak256(abi.encodePacked(taskType, messageHash));
    }
}
