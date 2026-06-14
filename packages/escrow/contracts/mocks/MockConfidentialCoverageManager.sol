// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import {FHE, euint64, eaddress, InEuint64} from "@fhenixprotocol/cofhe-contracts/FHE.sol";
import {InEaddress} from "@fhenixprotocol/cofhe-contracts/ICofhe.sol";
import {IConfidentialEscrow} from "../interfaces/core/IConfidentialEscrow.sol";
import {FHEMeta} from "@reineira-os/shared/contracts/common/FHEMeta.sol";

contract MockConfidentialCoverageManager {
    IConfidentialEscrow public immutable escrow;

    constructor(address escrow_) {
        escrow = IConfidentialEscrow(escrow_);
    }

    function setFee(
        uint256 escrowId,
        InEaddress calldata holder,
        InEuint64 calldata effectiveBps,
        address recipient
    ) external {
        eaddress h = FHEMeta.asEaddress(holder, msg.sender);
        euint64 bps = FHEMeta.asEuint64(effectiveBps, msg.sender);
        FHE.allow(h, address(escrow));
        FHE.allowTransient(bps, address(escrow));
        escrow.setUnderwriterFee(escrowId, h, bps, recipient);
    }
}
