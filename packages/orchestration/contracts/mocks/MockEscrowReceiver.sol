// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {ICCTPV2EscrowReceiver} from "@reineira-os/shared/contracts/interfaces/external/ICCTPV2EscrowReceiver.sol";

contract MockEscrowReceiver is ICCTPV2EscrowReceiver {
    bool public shouldSucceed = true;
    uint256 public lastEscrowId;

    function setShouldSucceed(bool success) external {
        shouldSucceed = success;
    }

    function settle(bytes calldata message, bytes calldata) external {
        if (!shouldSucceed) {
            revert MessageReceiveFailed();
        }

        if (message.length >= 280) {
            lastEscrowId = abi.decode(message[248:], (uint256));
        }
    }

    function buildHookData(uint256 escrowId) external pure returns (bytes memory) {
        return abi.encode(escrowId);
    }
}
