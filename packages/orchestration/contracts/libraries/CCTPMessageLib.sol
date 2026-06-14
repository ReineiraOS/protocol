// SPDX-License-Identifier: FSL-1.1-ALv2
// Copyright (c) 2026 Reineira Labs Limited All rights reserved.
pragma solidity ^0.8.24;

/**
 * @title CCTPMessageLib
 * @notice Library for parsing CCTP V2 messages with hook data
 * @dev CCTP V2 BurnMessage structure (after header):
 *      - Bytes 0-215:   CCTP header (version, sourceDomain, destDomain, nonce, sender, recipient, destCaller)
 *      - Bytes 216-247: Amount (uint256) - transfer amount
 *      - Bytes 248-279: Mint Recipient (bytes32)
 *      - Bytes 280-311: Fee Payer (bytes32)
 *      - Bytes 312-343: Max Fee (uint256)
 *      - Bytes 344-375: Finality Threshold + extra fields
 *      - Bytes 376+:    Hook Data (ABI-encoded escrowId for our use case)
 */
library CCTPMessageLib {
    error MalformedMessage();

    uint256 private constant HOOK_DATA_OFFSET = 376;
    uint256 private constant AMOUNT_OFFSET = 216;
    uint256 private constant MIN_MESSAGE_LENGTH = 408;

    function extractEscrowId(bytes memory message) internal pure returns (uint256 escrowId) {
        if (message.length < MIN_MESSAGE_LENGTH) {
            revert MalformedMessage();
        }
        assembly {
            escrowId := mload(add(add(message, 32), HOOK_DATA_OFFSET))
        }
    }

    function extractAmount(bytes memory message) internal pure returns (uint256 amount) {
        if (message.length < AMOUNT_OFFSET + 32) {
            revert MalformedMessage();
        }
        assembly {
            amount := mload(add(add(message, 32), AMOUNT_OFFSET))
        }
    }

    function extractMessageHash(bytes memory message) internal pure returns (bytes32) {
        return keccak256(message);
    }

    function validate(bytes memory message) internal pure returns (bool) {
        return message.length >= MIN_MESSAGE_LENGTH;
    }
}
