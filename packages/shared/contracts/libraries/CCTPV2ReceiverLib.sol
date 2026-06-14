// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 Reineira Labs Limited All rights reserved.
pragma solidity ^0.8.24;

library CCTPV2ReceiverLib {
    uint256 internal constant HOOK_DATA_OFFSET = 376;

    error MessageReceiveFailed();
    error ZeroAmount();
    error EscrowNotFound(uint256 escrowId);
    error MalformedHookData();

    event EscrowSettled(uint256 indexed escrowId, address indexed relayer, uint256 usdcAmount, uint256 escrowAmount);

    function extractEscrowId(bytes calldata message) internal pure returns (uint256 escrowId) {
        if (message.length < HOOK_DATA_OFFSET + 32) revert MalformedHookData();
        escrowId = abi.decode(message[HOOK_DATA_OFFSET:], (uint256));
    }

    function buildHookData(uint256 escrowId) internal pure returns (bytes memory) {
        return abi.encode(escrowId);
    }
}
