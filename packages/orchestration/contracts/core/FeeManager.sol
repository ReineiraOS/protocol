// SPDX-License-Identifier: FSL-1.1-ALv2
// Copyright (c) 2026 Reineira Labs Limited All rights reserved.
pragma solidity ^0.8.24;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {TestnetCoreBase} from "@reineira-os/shared/contracts/common/TestnetCoreBase.sol";
import {IFeeManager} from "../interfaces/core/IFeeManager.sol";

contract FeeManager is IFeeManager, TestnetCoreBase {
    using SafeERC20 for IERC20;

    uint256 private constant BPS_DENOMINATOR = 10000;
    uint256 private constant MAX_BPS = 10000;

    error NotAuthorized();
    error InsufficientBalance();

    IERC20 public feeToken;
    address public feeCollector;

    uint256 public operatorFeeBps;

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor(address trustedForwarder_) TestnetCoreBase(trustedForwarder_) {
        _disableInitializers();
    }

    function initialize(
        address owner_,
        address feeToken_,
        address feeCollector_,
        uint256 operatorFeeBps_
    ) external initializer {
        if (feeToken_ == address(0)) revert ZeroAddress();
        if (feeCollector_ == address(0)) revert ZeroAddress();
        if (operatorFeeBps_ > MAX_BPS) revert InvalidFeeConfig();

        __TestnetCoreBase_init(owner_);

        feeToken = IERC20(feeToken_);
        feeCollector = feeCollector_;
        operatorFeeBps = operatorFeeBps_;
    }

    function calculateFee(uint256 amount) external view returns (uint256 operatorFee) {
        operatorFee = (amount * operatorFeeBps) / BPS_DENOMINATOR;
    }

    function collectFee(bytes32 taskHash, address operator, uint256 amount) external nonReentrant {
        if (msg.sender != feeCollector && msg.sender != owner()) revert NotAuthorized();
        if (operator == address(0)) revert ZeroAddress();

        uint256 operatorFee = (amount * operatorFeeBps) / BPS_DENOMINATOR;

        if (operatorFee == 0) {
            emit FeeCollected(taskHash, operator, 0);
            return;
        }

        uint256 balance = feeToken.balanceOf(address(this));
        if (balance < operatorFee) revert InsufficientBalance();

        feeToken.safeTransfer(operator, operatorFee);

        emit FeeCollected(taskHash, operator, operatorFee);
    }

    function setFeeConfig(uint256 operatorFeeBps_) external onlyOwner {
        if (operatorFeeBps_ > MAX_BPS) revert InvalidFeeConfig();

        operatorFeeBps = operatorFeeBps_;

        emit FeeConfigUpdated(operatorFeeBps_);
    }

    function setFeeCollector(address collector) external onlyOwner {
        if (collector == address(0)) revert ZeroAddress();
        address oldCollector = feeCollector;
        feeCollector = collector;
        emit FeeCollectorUpdated(oldCollector, collector);
    }

    function setFeeToken(address token) external onlyOwner {
        if (token == address(0)) revert ZeroAddress();
        address oldToken = address(feeToken);
        feeToken = IERC20(token);
        emit FeeTokenUpdated(oldToken, token);
    }
}
