// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {FHE, euint64, InEuint64} from "@fhenixprotocol/cofhe-contracts/FHE.sol";
import {FHERC20} from "fhenix-confidential-contracts/contracts/FHERC20/FHERC20.sol";

contract MockConfidentialToken is FHERC20 {
    constructor() FHERC20("Mock Confidential Token", "MCT", 6, "") {}

    function mint(address to, InEuint64 calldata encryptedAmount) external returns (euint64) {
        euint64 amount = FHE.asEuint64(encryptedAmount);
        return _mint(to, amount);
    }

    function mintPlain(address to, uint64 amount) external returns (euint64) {
        return _mint(to, FHE.asEuint64(amount));
    }

    function burn(address from, euint64 amount) external returns (euint64) {
        return _burn(from, amount);
    }
}
