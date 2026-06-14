// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {MockTaskLib} from "../../contracts/mocks/MockTaskLib.sol";

contract TaskLibTest is Test {
    MockTaskLib lib;

    function setUp() public {
        lib = new MockTaskLib();
    }

    function test_TASK_CCTP_RELAY_constant() public view {
        assertEq(lib.TASK_CCTP_RELAY(), keccak256("CCTP_RELAY"));
    }

    function test_TASK_AUTOMATION_constant() public view {
        assertEq(lib.TASK_AUTOMATION(), keccak256("AUTOMATION"));
    }

    function test_TASK_AGENT_CALL_constant() public view {
        assertEq(lib.TASK_AGENT_CALL(), keccak256("AGENT_CALL"));
    }

    function test_constants_are_unique() public view {
        bytes32 cctpRelay = lib.TASK_CCTP_RELAY();
        bytes32 automation = lib.TASK_AUTOMATION();
        bytes32 agentCall = lib.TASK_AGENT_CALL();

        assertTrue(cctpRelay != automation);
        assertTrue(cctpRelay != agentCall);
        assertTrue(automation != agentCall);
    }

    function test_generateTaskHash_from_payload() public view {
        bytes32 taskType = lib.TASK_CCTP_RELAY();
        bytes memory payload = "test payload";

        bytes32 taskHash = lib.generateTaskHash(taskType, payload);
        bytes32 payloadHash = keccak256(payload);
        bytes32 expectedHash = keccak256(abi.encodePacked(taskType, payloadHash));

        assertEq(taskHash, expectedHash);
    }

    function test_generateTaskHash_different_payloads() public view {
        bytes32 taskType = lib.TASK_CCTP_RELAY();

        bytes32 hash1 = lib.generateTaskHash(taskType, "payload 1");
        bytes32 hash2 = lib.generateTaskHash(taskType, "payload 2");

        assertTrue(hash1 != hash2);
    }

    function test_generateTaskHash_different_task_types() public view {
        bytes32 cctpRelay = lib.TASK_CCTP_RELAY();
        bytes32 automation = lib.TASK_AUTOMATION();
        bytes memory payload = "same payload";

        bytes32 hash1 = lib.generateTaskHash(cctpRelay, payload);
        bytes32 hash2 = lib.generateTaskHash(automation, payload);

        assertTrue(hash1 != hash2);
    }

    function test_generateTaskHash_same_inputs() public view {
        bytes32 taskType = lib.TASK_CCTP_RELAY();
        bytes memory payload = "consistent payload";

        bytes32 hash1 = lib.generateTaskHash(taskType, payload);
        bytes32 hash2 = lib.generateTaskHash(taskType, payload);

        assertEq(hash1, hash2);
    }

    function test_generateTaskHash_empty_payload() public view {
        bytes32 taskType = lib.TASK_CCTP_RELAY();
        bytes memory emptyPayload = "";

        bytes32 taskHash = lib.generateTaskHash(taskType, emptyPayload);
        bytes32 payloadHash = keccak256(emptyPayload);
        bytes32 expectedHash = keccak256(abi.encodePacked(taskType, payloadHash));

        assertEq(taskHash, expectedHash);
    }

    function test_generateTaskHash_large_payload() public view {
        bytes32 taskType = lib.TASK_CCTP_RELAY();
        bytes memory largePayload = new bytes(10000);
        for (uint256 i = 0; i < 10000; i++) {
            largePayload[i] = "x";
        }

        bytes32 taskHash = lib.generateTaskHash(taskType, largePayload);
        bytes32 payloadHash = keccak256(largePayload);
        bytes32 expectedHash = keccak256(abi.encodePacked(taskType, payloadHash));

        assertEq(taskHash, expectedHash);
    }

    function test_generateTaskHashFromMessage_from_message_hash() public view {
        bytes32 taskType = lib.TASK_CCTP_RELAY();
        bytes32 messageHash = keccak256("test message");

        bytes32 taskHash = lib.generateTaskHashFromMessage(taskType, messageHash);
        bytes32 expectedHash = keccak256(abi.encodePacked(taskType, messageHash));

        assertEq(taskHash, expectedHash);
    }

    function test_generateTaskHashFromMessage_different_hashes() public view {
        bytes32 taskType = lib.TASK_CCTP_RELAY();
        bytes32 messageHash1 = keccak256("message 1");
        bytes32 messageHash2 = keccak256("message 2");

        bytes32 hash1 = lib.generateTaskHashFromMessage(taskType, messageHash1);
        bytes32 hash2 = lib.generateTaskHashFromMessage(taskType, messageHash2);

        assertTrue(hash1 != hash2);
    }

    function test_generateTaskHashFromMessage_different_types() public view {
        bytes32 cctpRelay = lib.TASK_CCTP_RELAY();
        bytes32 automation = lib.TASK_AUTOMATION();
        bytes32 messageHash = keccak256("same message");

        bytes32 hash1 = lib.generateTaskHashFromMessage(cctpRelay, messageHash);
        bytes32 hash2 = lib.generateTaskHashFromMessage(automation, messageHash);

        assertTrue(hash1 != hash2);
    }

    function test_generateTaskHashFromMessage_consistency_with_generateTaskHash() public view {
        bytes32 taskType = lib.TASK_CCTP_RELAY();
        bytes memory payload = "test payload";
        bytes32 payloadHash = keccak256(payload);

        bytes32 hashFromPayload = lib.generateTaskHash(taskType, payload);
        bytes32 hashFromMessageHash = lib.generateTaskHashFromMessage(taskType, payloadHash);

        assertEq(hashFromPayload, hashFromMessageHash);
    }

    function test_generateTaskHashFromMessage_zero_hash() public view {
        bytes32 taskType = lib.TASK_CCTP_RELAY();
        bytes32 zeroHash = bytes32(0);

        bytes32 taskHash = lib.generateTaskHashFromMessage(taskType, zeroHash);
        bytes32 expectedHash = keccak256(abi.encodePacked(taskType, zeroHash));

        assertEq(taskHash, expectedHash);
    }
}
