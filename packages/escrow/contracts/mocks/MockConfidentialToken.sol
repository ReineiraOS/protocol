// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import {FHE, euint64, InEuint64} from "@fhenixprotocol/cofhe-contracts/FHE.sol";
import {FHERC20} from "fhenix-confidential-contracts/contracts/FHERC20/FHERC20.sol";
import {IFHERC20Wrapper} from "@reineira-os/shared/contracts/interfaces/external/IFHERC20Wrapper.sol";

contract MockConfidentialToken is FHERC20, IFHERC20Wrapper {
    uint256 private constant RATE = 1;

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

    function wrap(address to, uint256 amount) external override {
        // safe: test mock; wrapped amounts are bounded well within uint64 range
        // forge-lint: disable-next-line(unsafe-typecast)
        _mint(to, FHE.asEuint64(uint64(amount / RATE)));
    }

    function unwrap(address from, address to, euint64 amount) external override {
        _burn(from, amount);
        (to);
    }

    function rate() external pure override returns (uint256) {
        return RATE;
    }
}
