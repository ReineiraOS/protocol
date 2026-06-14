// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import {Escrow} from "../core/Escrow.sol";

contract MockCoverageManager {
    Escrow public immutable escrow;

    constructor(address escrow_) {
        escrow = Escrow(escrow_);
    }

    function setFee(uint256 escrowId, address holder, uint16 effectiveBps, address recipient) external {
        escrow.setUnderwriterFee(escrowId, holder, effectiveBps, recipient);
    }
}
