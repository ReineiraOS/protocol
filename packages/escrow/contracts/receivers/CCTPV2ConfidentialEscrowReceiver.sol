// SPDX-License-Identifier: FSL-1.1-ALv2
// Copyright (c) 2026 Reineira Labs Limited All rights reserved.
pragma solidity ^0.8.25;

import {FHE, euint64} from "@fhenixprotocol/cofhe-contracts/FHE.sol";
import {IERC20} from "@openzeppelin/contracts/interfaces/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {SafeCast} from "@openzeppelin/contracts/utils/math/SafeCast.sol";
import {IFHERC20} from "fhenix-confidential-contracts/contracts/interfaces/IFHERC20.sol";
import {TestnetCoreBase} from "@reineira-os/shared/contracts/common/TestnetCoreBase.sol";
import {ICCTPV2ConfidentialEscrowReceiver} from "../interfaces/receivers/ICCTPV2ConfidentialEscrowReceiver.sol";
import {ICCTPV2MessageTransmitter} from "@reineira-os/shared/contracts/interfaces/external/ICCTPV2MessageTransmitter.sol";
import {IFHERC20Wrapper} from "@reineira-os/shared/contracts/interfaces/external/IFHERC20Wrapper.sol";
import {IEscrow} from "@reineira-os/shared/contracts/interfaces/core/IEscrow.sol";
import {IConfidentialEscrow} from "../interfaces/core/IConfidentialEscrow.sol";

contract CCTPV2ConfidentialEscrowReceiver is ICCTPV2ConfidentialEscrowReceiver, TestnetCoreBase {
    using SafeERC20 for IERC20;

    ICCTPV2MessageTransmitter public cctpV2Transmitter;
    IERC20 public usdc;
    /// @notice Confidential (FHERC20) token that bridged USDC is wrapped into before funding the escrow.
    /// @dev TEMPORARY / INTERIM: the configured token is a placeholder. It is expected to be swapped via
    ///      `setConfidentialUsdc` for a standardized confidential token once a confidential-token standard
    ///      (ERC-7984 / FHERC20 profile) is selected. The protocol is token-agnostic — this address is
    ///      a deployment choice, not a fixed dependency.
    IFHERC20Wrapper public confidentialUsdc;
    IEscrow public escrow;

    uint256 private constant HOOK_DATA_OFFSET = 376;

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor(address trustedForwarder_) TestnetCoreBase(trustedForwarder_) {
        _disableInitializers();
    }

    function initialize(
        address owner_,
        address cctpV2Transmitter_,
        address usdc_,
        address confidentialUsdc_,
        address escrow_
    ) external initializer {
        if (cctpV2Transmitter_ == address(0)) revert ZeroAddress();
        if (usdc_ == address(0)) revert ZeroAddress();
        if (confidentialUsdc_ == address(0)) revert ZeroAddress();
        if (escrow_ == address(0)) revert ZeroAddress();

        __TestnetCoreBase_init(owner_);

        cctpV2Transmitter = ICCTPV2MessageTransmitter(cctpV2Transmitter_);
        usdc = IERC20(usdc_);
        confidentialUsdc = IFHERC20Wrapper(confidentialUsdc_);
        escrow = IEscrow(escrow_);

        IERC20(usdc_).approve(confidentialUsdc_, type(uint256).max);
        IFHERC20(confidentialUsdc_).setOperator(escrow_, type(uint48).max);
    }

    function settle(bytes calldata message, bytes calldata attestation) external nonReentrant {
        uint256 balanceBefore = usdc.balanceOf(address(this));

        bool success = cctpV2Transmitter.receiveMessage(message, attestation);
        if (!success) revert MessageReceiveFailed();

        uint256 usdcReceived = usdc.balanceOf(address(this)) - balanceBefore;
        if (usdcReceived == 0) revert ZeroAmount();

        uint256 escrowId = _extractEscrowId(message);

        if (!escrow.exists(escrowId)) {
            revert EscrowNotFound(escrowId);
        }

        address escrowToken = escrow.paymentTokenOf(escrowId);
        if (escrowToken != address(confidentialUsdc)) {
            revert EscrowTokenMismatch(escrowId, address(confidentialUsdc), escrowToken);
        }

        uint256 rate = confidentialUsdc.rate();
        uint256 amountToWrap = usdcReceived - (usdcReceived % rate);
        if (amountToWrap == 0) revert ZeroAmount();
        confidentialUsdc.wrap(address(this), amountToWrap);

        uint64 confidentialAmount = SafeCast.toUint64(amountToWrap / rate);

        euint64 encryptedAmount = FHE.asEuint64(confidentialAmount);
        FHE.allowTransient(encryptedAmount, address(escrow));
        IConfidentialEscrow(address(escrow)).fundFrom(escrowId, encryptedAmount);

        emit EscrowSettled(escrowId, _msgSender(), usdcReceived, confidentialAmount);
    }

    function _extractEscrowId(bytes calldata message) private pure returns (uint256 escrowId) {
        if (message.length < HOOK_DATA_OFFSET + 32) {
            revert MalformedHookData();
        }

        bytes calldata hookData = message[HOOK_DATA_OFFSET:];
        escrowId = abi.decode(hookData, (uint256));
    }

    function buildHookData(uint256 escrowId) external pure returns (bytes memory) {
        return abi.encode(escrowId);
    }

    function setConfidentialUsdc(address confidentialUsdc_) external onlyOwner {
        if (confidentialUsdc_ == address(0)) revert ZeroAddress();

        usdc.approve(address(confidentialUsdc), 0);

        confidentialUsdc = IFHERC20Wrapper(confidentialUsdc_);

        usdc.approve(confidentialUsdc_, type(uint256).max);

        IFHERC20(confidentialUsdc_).setOperator(address(escrow), type(uint48).max);
    }
}
