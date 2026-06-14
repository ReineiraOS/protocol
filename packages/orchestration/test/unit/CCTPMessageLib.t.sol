// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {MockCCTPMessageLib} from "../../contracts/mocks/MockCCTPMessageLib.sol";
import {CCTPMessageLib} from "../../contracts/libraries/CCTPMessageLib.sol";

contract CCTPMessageLibTest is Test {
    MockCCTPMessageLib lib;

    uint256 constant AMOUNT_OFFSET = 216;
    uint256 constant MIN_MESSAGE_LENGTH = 408;

    function setUp() public {
        lib = new MockCCTPMessageLib();
    }

    function _buildCCTPMessage(uint256 amount, uint256 escrowId) internal pure returns (bytes memory) {
        bytes memory header = new bytes(216);
        return abi.encodePacked(header, amount, bytes32(0), bytes32(0), bytes32(0), bytes32(0), escrowId);
    }

    function _buildShortMessage(uint256 length) internal pure returns (bytes memory) {
        return new bytes(length);
    }

    function test_extractEscrowId_valid_message() public view {
        bytes memory message = _buildCCTPMessage(1000000, 12345);
        assertEq(lib.extractEscrowId(message), 12345);
    }

    function test_extractEscrowId_large_value() public view {
        uint256 escrowId = type(uint128).max;
        bytes memory message = _buildCCTPMessage(1000000, escrowId);
        assertEq(lib.extractEscrowId(message), escrowId);
    }

    function test_extractEscrowId_zero() public view {
        bytes memory message = _buildCCTPMessage(1000000, 0);
        assertEq(lib.extractEscrowId(message), 0);
    }

    function test_extractEscrowId_reverts_short_message() public {
        bytes memory shortMessage = _buildShortMessage(MIN_MESSAGE_LENGTH - 1);
        vm.expectRevert(CCTPMessageLib.MalformedMessage.selector);
        lib.extractEscrowId(shortMessage);
    }

    function test_extractAmount_valid_message() public view {
        bytes memory message = _buildCCTPMessage(1000000, 12345);
        assertEq(lib.extractAmount(message), 1000000);
    }

    function test_extractAmount_large_value() public view {
        uint256 amount = type(uint128).max;
        bytes memory message = _buildCCTPMessage(amount, 12345);
        assertEq(lib.extractAmount(message), amount);
    }

    function test_extractAmount_zero() public view {
        bytes memory message = _buildCCTPMessage(0, 12345);
        assertEq(lib.extractAmount(message), 0);
    }

    function test_extractAmount_reverts_short_message() public {
        bytes memory shortMessage = _buildShortMessage(AMOUNT_OFFSET + 31);
        vm.expectRevert(CCTPMessageLib.MalformedMessage.selector);
        lib.extractAmount(shortMessage);
    }

    function test_extractAmount_exact_boundary() public view {
        bytes memory header = new bytes(AMOUNT_OFFSET);
        uint256 amount = 999999;
        bytes memory message = abi.encodePacked(header, amount);
        assertEq(lib.extractAmount(message), amount);
    }

    function test_extractMessageHash_keccak256() public view {
        bytes memory message = _buildCCTPMessage(1000000, 12345);
        assertEq(lib.extractMessageHash(message), keccak256(message));
    }

    function test_extractMessageHash_different_messages() public view {
        bytes memory message1 = _buildCCTPMessage(1000000, 12345);
        bytes memory message2 = _buildCCTPMessage(2000000, 67890);

        assertTrue(lib.extractMessageHash(message1) != lib.extractMessageHash(message2));
    }

    function test_extractMessageHash_same_message() public view {
        bytes memory message = _buildCCTPMessage(1000000, 12345);
        assertEq(lib.extractMessageHash(message), lib.extractMessageHash(message));
    }

    function test_validate_gte_min_length() public view {
        bytes memory message = _buildCCTPMessage(1000000, 12345);
        assertTrue(lib.validate(message));
    }

    function test_validate_exactly_min_length() public view {
        bytes memory message = _buildShortMessage(MIN_MESSAGE_LENGTH);
        assertTrue(lib.validate(message));
    }

    function test_validate_lt_min_length() public view {
        bytes memory shortMessage = _buildShortMessage(MIN_MESSAGE_LENGTH - 1);
        assertFalse(lib.validate(shortMessage));
    }

    function test_validate_empty_message() public view {
        assertFalse(lib.validate(""));
    }

    function test_validate_gt_min_length() public view {
        bytes memory longMessage = _buildShortMessage(MIN_MESSAGE_LENGTH + 100);
        assertTrue(lib.validate(longMessage));
    }

    function test_message_structure_all_fields() public view {
        bytes memory message = _buildCCTPMessage(5000000, 999);
        assertEq(lib.extractAmount(message), 5000000);
        assertEq(lib.extractEscrowId(message), 999);
    }

    function test_message_structure_max_uint256() public view {
        uint256 maxUint256 = type(uint256).max;
        bytes memory message = _buildCCTPMessage(maxUint256, maxUint256);
        assertEq(lib.extractAmount(message), maxUint256);
        assertEq(lib.extractEscrowId(message), maxUint256);
    }
}
