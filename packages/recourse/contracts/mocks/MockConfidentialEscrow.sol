// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {FHE, euint64, eaddress} from "@fhenixprotocol/cofhe-contracts/FHE.sol";
import {IConfidentialEscrow} from "../interfaces/external/IConfidentialEscrow.sol";

contract MockConfidentialEscrow is IConfidentialEscrow {
    mapping(uint256 => bool) private _exists;
    mapping(uint256 => euint64) private _amounts;

    struct FeeRecord {
        euint64 bps;
        address recipient;
        bool set;
    }

    mapping(uint256 => FeeRecord) private _fees;

    function setExists(uint256 escrowId, bool val) external {
        _exists[escrowId] = val;
    }

    function setAmount(uint256 escrowId, uint64 amount, address allowedCaller) external {
        euint64 encrypted = FHE.asEuint64(amount);
        FHE.allowThis(encrypted);
        FHE.allow(encrypted, allowedCaller);
        _amounts[escrowId] = encrypted;
    }

    function exists(uint256 escrowId) external view returns (bool) {
        return _exists[escrowId];
    }

    function getAmount(uint256 escrowId) external view returns (euint64 amount) {
        return _amounts[escrowId];
    }

    function setUnderwriterFee(uint256 escrowId, eaddress, euint64 effectiveBps, address recipient_) external {
        FHE.allowThis(effectiveBps);
        _fees[escrowId] = FeeRecord(effectiveBps, recipient_, true);
    }

    function feeSet(uint256 escrowId) external view returns (bool) {
        return _fees[escrowId].set;
    }

    function getFeeRecipient(uint256 escrowId) external view returns (address) {
        return _fees[escrowId].recipient;
    }
}
