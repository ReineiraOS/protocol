// SPDX-License-Identifier: FSL-1.1-ALv2
// Copyright (c) 2026 Reineira Labs Limited All rights reserved.
pragma solidity ^0.8.24;

// TODO: TESTNET ONLY - Remove upgradeable pattern for mainnet deployment
// For mainnet, replace TestnetCoreBase with non-upgradeable ReentrancyGuard and remove initializer.

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {TestnetCoreBase} from "@reineira-os/shared/contracts/common/TestnetCoreBase.sol";
import {ICCTPV2Forwarder} from "../interfaces/ICCTPV2Forwarder.sol";
import {ICCTPV2MessageTransmitter} from "@reineira-os/shared/contracts/interfaces/external/ICCTPV2MessageTransmitter.sol";

// TODO: TESTNET ONLY - Remove TestnetCoreBase inheritance for mainnet
contract CCTPV2Forwarder is ICCTPV2Forwarder, TestnetCoreBase {
    using SafeERC20 for IERC20;

    ICCTPV2MessageTransmitter public cctpV2Transmitter;
    IERC20 public usdc;

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor(address trustedForwarder_) TestnetCoreBase(trustedForwarder_) {
        _disableInitializers();
    }

    function initialize(address owner_, address cctpV2Transmitter_, address usdc_) external initializer {
        if (cctpV2Transmitter_ == address(0)) revert InvalidTransmitter();
        if (usdc_ == address(0)) revert InvalidUsdc();

        __TestnetCoreBase_init(owner_);

        cctpV2Transmitter = ICCTPV2MessageTransmitter(cctpV2Transmitter_);
        usdc = IERC20(usdc_);
    }

    function receiveAndForward(
        bytes calldata message,
        bytes calldata attestation,
        address recipient
    ) external nonReentrant returns (uint256 amount) {
        if (recipient == address(0)) revert ZeroAddress();

        uint256 balanceBefore = usdc.balanceOf(address(this));

        bool success = cctpV2Transmitter.receiveMessage(message, attestation);
        if (!success) revert MessageReceiveFailed();

        uint256 balanceAfter = usdc.balanceOf(address(this));
        amount = balanceAfter - balanceBefore;

        if (amount == 0) revert ZeroAmount();

        bytes32 messageHash = keccak256(message);
        emit MessageReceived(messageHash, recipient, amount);

        usdc.safeTransfer(recipient, amount);
        emit TokensForwarded(recipient, amount);
    }
}
