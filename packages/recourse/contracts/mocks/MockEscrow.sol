// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IEscrow} from "../interfaces/external/IEscrow.sol";

contract MockEscrow is IEscrow {
    mapping(uint256 => bool) private _exists;
    mapping(uint256 => uint256) private _amounts;

    struct FeeRecord {
        uint16 bps;
        address recipient;
        bool set;
    }

    mapping(uint256 => FeeRecord) private _fees;

    function setExists(uint256 escrowId, bool val) external {
        _exists[escrowId] = val;
    }

    function setAmount(uint256 escrowId, uint256 amount) external {
        _amounts[escrowId] = amount;
    }

    function exists(uint256 escrowId) external view returns (bool) {
        return _exists[escrowId];
    }

    function getAmount(uint256 escrowId) external view returns (uint256) {
        return _amounts[escrowId];
    }

    function setUnderwriterFee(uint256 escrowId, address, uint16 effectiveBps, address recipient_) external {
        _fees[escrowId] = FeeRecord(effectiveBps, recipient_, true);
    }

    function feeSet(uint256 escrowId) external view returns (bool) {
        return _fees[escrowId].set;
    }

    function getFeeRecipient(uint256 escrowId) external view returns (address) {
        return _fees[escrowId].recipient;
    }

    function getFeeBps(uint256 escrowId) external view returns (uint16) {
        return _fees[escrowId].bps;
    }
}
