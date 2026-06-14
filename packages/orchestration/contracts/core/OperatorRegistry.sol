// SPDX-License-Identifier: FSL-1.1-ALv2
// Copyright (c) 2026 Reineira Labs Limited All rights reserved.
pragma solidity ^0.8.24;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {EnumerableSet} from "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import {TestnetPausableBase} from "@reineira-os/shared/contracts/common/TestnetPausableBase.sol";
import {IOperatorRegistry} from "../interfaces/core/IOperatorRegistry.sol";

interface ISanctionsOracle {
    function isSanctioned(address addr) external view returns (bool);
}

contract OperatorRegistry is IOperatorRegistry, TestnetPausableBase {
    using SafeERC20 for IERC20;
    using EnumerableSet for EnumerableSet.AddressSet;

    uint256 public constant UNBOND_PERIOD = 7 days;

    IERC20 public stakingToken;
    ISanctionsOracle public sanctionsOracle;
    address public monitor;
    address public slashingManager;

    uint256 public minStake;
    uint256 public exclusiveWindow;
    uint256 public permissionlessDelay;

    mapping(address => OperatorInfo) private _operators;
    mapping(bytes32 => TaskClaim) private _claims;
    EnumerableSet.AddressSet private _activeOperators;

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor(address trustedForwarder_) TestnetPausableBase(trustedForwarder_) {
        _disableInitializers();
    }

    function initialize(
        address owner_,
        address stakingToken_,
        uint256 minStake_,
        uint256 exclusiveWindow_,
        uint256 permissionlessDelay_
    ) external initializer {
        if (stakingToken_ == address(0)) revert ZeroAddress();

        __TestnetPausableBase_init(owner_);

        stakingToken = IERC20(stakingToken_);
        minStake = minStake_;
        exclusiveWindow = exclusiveWindow_;
        permissionlessDelay = permissionlessDelay_;
    }

    function registerOperator(uint256 amount) external nonReentrant whenNotPaused {
        if (_operators[msg.sender].isActive) revert AlreadyRegistered();
        if (_operators[msg.sender].slashed) revert PermanentlySlashed();
        if (amount < minStake) revert InsufficientStake();
        _checkSanctions(msg.sender);

        stakingToken.safeTransferFrom(msg.sender, address(this), amount);

        _operators[msg.sender] = OperatorInfo({stake: amount, unbondRequestTime: 0, isActive: true, slashed: false});

        _activeOperators.add(msg.sender);

        emit OperatorRegistered(msg.sender, amount);
    }

    function addStake(uint256 amount) external nonReentrant whenNotPaused {
        if (!_operators[msg.sender].isActive) revert NotRegistered();
        if (amount == 0) revert ZeroAmount();
        if (_operators[msg.sender].unbondRequestTime != 0) revert UnbondingInProgress();

        stakingToken.safeTransferFrom(msg.sender, address(this), amount);
        _operators[msg.sender].stake += amount;

        emit StakeAdded(msg.sender, amount);
    }

    function requestUnbond() external nonReentrant {
        OperatorInfo storage operator = _operators[msg.sender];
        if (!operator.isActive) revert NotRegistered();
        if (operator.unbondRequestTime != 0) revert UnbondingInProgress();

        operator.unbondRequestTime = block.timestamp;
        operator.isActive = false;
        _activeOperators.remove(msg.sender);

        uint256 unlockTime = block.timestamp + UNBOND_PERIOD;
        emit UnbondRequested(msg.sender, unlockTime);
    }

    function withdrawStake() external nonReentrant {
        OperatorInfo storage operator = _operators[msg.sender];
        if (operator.stake == 0) revert NotRegistered();
        if (operator.unbondRequestTime == 0) revert NoUnbondRequest();
        if (block.timestamp < operator.unbondRequestTime + UNBOND_PERIOD) revert UnbondingNotComplete();

        uint256 amount = operator.stake;
        operator.stake = 0;
        operator.unbondRequestTime = 0;

        stakingToken.safeTransfer(msg.sender, amount);

        emit StakeWithdrawn(msg.sender, amount);
    }

    function claimTask(bytes32 taskHash) external nonReentrant whenNotPaused {
        if (!_operators[msg.sender].isActive) revert NotActive();
        if (_claims[taskHash].operator != address(0)) revert TaskAlreadyClaimed();

        _claims[taskHash] = TaskClaim({operator: msg.sender, claimTime: block.timestamp, executed: false});

        emit TaskClaimed(taskHash, msg.sender);
    }

    function markExecuted(bytes32 taskHash, address operator) external nonReentrant {
        if (msg.sender != monitor && msg.sender != owner()) revert NotAuthorized();

        TaskClaim storage claim = _claims[taskHash];
        if (claim.executed) revert TaskAlreadyExecuted();

        claim.executed = true;

        emit TaskExecuted(taskHash, operator);
    }

    function slash(address operator, uint256 amount, bytes32 evidence) external nonReentrant {
        if (msg.sender != slashingManager && msg.sender != owner()) revert NotAuthorized();
        if (amount == 0) revert ZeroAmount();

        OperatorInfo storage operatorInfo = _operators[operator];
        if (operatorInfo.stake == 0) revert NotRegistered();

        uint256 slashAmount = amount > operatorInfo.stake ? operatorInfo.stake : amount;
        operatorInfo.stake -= slashAmount;
        operatorInfo.slashed = true;

        if (operatorInfo.isActive) {
            operatorInfo.isActive = false;
            _activeOperators.remove(operator);
        }

        address recipient = msg.sender == slashingManager ? slashingManager : owner();
        stakingToken.safeTransfer(recipient, slashAmount);

        emit OperatorSlashed(operator, slashAmount, evidence);
    }

    function setMonitor(address monitor_) external onlyOwner {
        if (monitor_ == address(0)) revert ZeroAddress();
        address oldMonitor = monitor;
        monitor = monitor_;
        emit MonitorUpdated(oldMonitor, monitor_);
    }

    function setSlashingManager(address slashingManager_) external onlyOwner {
        if (slashingManager_ == address(0)) revert ZeroAddress();
        address oldManager = slashingManager;
        slashingManager = slashingManager_;
        emit SlashingManagerUpdated(oldManager, slashingManager_);
    }

    function setConfig(uint256 minStake_, uint256 exclusiveWindow_, uint256 permissionlessDelay_) external onlyOwner {
        minStake = minStake_;
        exclusiveWindow = exclusiveWindow_;
        permissionlessDelay = permissionlessDelay_;
        emit ConfigUpdated(minStake_, exclusiveWindow_, permissionlessDelay_);
    }

    function setSanctionsOracle(address oracle) external onlyOwner {
        sanctionsOracle = ISanctionsOracle(oracle);
    }

    function getOperatorInfo(address operator) external view returns (OperatorInfo memory) {
        return _operators[operator];
    }

    function getTaskClaim(bytes32 taskHash) external view returns (TaskClaim memory) {
        return _claims[taskHash];
    }

    function isOperatorActive(address operator) external view returns (bool) {
        return _operators[operator].isActive;
    }

    function canExecuteTask(address caller, bytes32 taskHash) external view returns (bool) {
        OperatorInfo storage callerInfo = _operators[caller];
        if (callerInfo.slashed) {
            return false;
        }

        TaskClaim storage claim = _claims[taskHash];

        if (claim.executed) {
            return false;
        }

        if (claim.operator == address(0)) {
            return callerInfo.isActive;
        }

        if (caller == claim.operator) {
            return true;
        }

        uint256 timeSinceClaim = block.timestamp - claim.claimTime;

        if (timeSinceClaim < exclusiveWindow) {
            return false;
        }

        if (timeSinceClaim >= permissionlessDelay) {
            return true;
        }

        return callerInfo.isActive;
    }

    function getActiveOperators() external view returns (address[] memory) {
        return _activeOperators.values();
    }

    function activeOperatorCount() external view returns (uint256) {
        return _activeOperators.length();
    }

    function _checkSanctions(address addr) private view {
        if (address(sanctionsOracle) != address(0) && sanctionsOracle.isSanctioned(addr)) {
            revert Sanctioned();
        }
    }
}
