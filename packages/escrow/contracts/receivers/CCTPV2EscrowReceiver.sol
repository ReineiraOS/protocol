// SPDX-License-Identifier: FSL-1.1-ALv2
// Copyright (c) 2026 Reineira Labs Limited All rights reserved.
pragma solidity ^0.8.25;

import {IERC20} from "@openzeppelin/contracts/interfaces/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {TestnetCoreBase} from "@reineira-os/shared/contracts/common/TestnetCoreBase.sol";
import {ICCTPV2EscrowReceiver} from "../interfaces/receivers/ICCTPV2EscrowReceiver.sol";
import {ICCTPV2MessageTransmitter} from "@reineira-os/shared/contracts/interfaces/external/ICCTPV2MessageTransmitter.sol";
import {CCTPV2ReceiverLib} from "@reineira-os/shared/contracts/libraries/CCTPV2ReceiverLib.sol";
import {IEscrow} from "@reineira-os/shared/contracts/interfaces/core/IEscrow.sol";

contract CCTPV2EscrowReceiver is ICCTPV2EscrowReceiver, TestnetCoreBase {
    using SafeERC20 for IERC20;

    ICCTPV2MessageTransmitter public cctpV2Transmitter;
    IERC20 public usdc;
    IEscrow public escrow;

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor(address trustedForwarder_) TestnetCoreBase(trustedForwarder_) {
        _disableInitializers();
    }

    function initialize(
        address owner_,
        address cctpV2Transmitter_,
        address usdc_,
        address escrow_
    ) external initializer {
        if (cctpV2Transmitter_ == address(0)) revert ZeroAddress();
        if (usdc_ == address(0)) revert ZeroAddress();
        if (escrow_ == address(0)) revert ZeroAddress();

        __TestnetCoreBase_init(owner_);

        cctpV2Transmitter = ICCTPV2MessageTransmitter(cctpV2Transmitter_);
        usdc = IERC20(usdc_);
        escrow = IEscrow(escrow_);

        IERC20(usdc_).approve(escrow_, type(uint256).max);
    }

    function settle(bytes calldata message, bytes calldata attestation) external nonReentrant {
        uint256 balanceBefore = usdc.balanceOf(address(this));

        bool success = cctpV2Transmitter.receiveMessage(message, attestation);
        if (!success) revert MessageReceiveFailed();

        uint256 usdcReceived = usdc.balanceOf(address(this)) - balanceBefore;
        if (usdcReceived == 0) revert ZeroAmount();

        uint256 escrowId = CCTPV2ReceiverLib.extractEscrowId(message);

        if (!escrow.exists(escrowId)) {
            revert EscrowNotFound(escrowId);
        }

        escrow.fund(escrowId, abi.encode(usdcReceived));

        emit EscrowSettled(escrowId, _msgSender(), usdcReceived, usdcReceived);
    }

    function buildHookData(uint256 escrowId) external pure returns (bytes memory) {
        return CCTPV2ReceiverLib.buildHookData(escrowId);
    }
}
