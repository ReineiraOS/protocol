// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {CCTPMessageLib} from "../libraries/CCTPMessageLib.sol";

contract MockCCTPMessageLib {
    using CCTPMessageLib for bytes;

    function extractEscrowId(bytes memory message) external pure returns (uint256) {
        return message.extractEscrowId();
    }

    function extractAmount(bytes memory message) external pure returns (uint256) {
        return message.extractAmount();
    }

    function extractMessageHash(bytes memory message) external pure returns (bytes32) {
        return message.extractMessageHash();
    }

    function validate(bytes memory message) external pure returns (bool) {
        return message.validate();
    }
}
