// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import {IERC20} from "@openzeppelin/contracts/interfaces/IERC20.sol";

contract MockCCTPV2MessageTransmitter {
    IERC20 public usdc;
    bool public shouldSucceed = true;
    uint256 public amountToMint;

    constructor(address usdc_) {
        usdc = IERC20(usdc_);
    }

    function setAmountToMint(uint256 amount) external {
        amountToMint = amount;
    }

    function setShouldSucceed(bool success) external {
        shouldSucceed = success;
    }

    function receiveMessage(bytes calldata, bytes calldata) external returns (bool) {
        if (!shouldSucceed) {
            return false;
        }

        if (amountToMint > 0) {
            MockUSDCMintable(address(usdc)).mint(msg.sender, amountToMint);
        }

        return true;
    }
}

interface MockUSDCMintable {
    function mint(address to, uint256 amount) external;
}
