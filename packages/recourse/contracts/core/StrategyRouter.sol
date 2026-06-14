// SPDX-License-Identifier: FSL-1.1-ALv2
// Copyright (c) 2026 Reineira Labs Limited All rights reserved.
pragma solidity ^0.8.24;

import {IERC20} from "@openzeppelin/contracts/interfaces/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import {TestnetCoreBase} from "@reineira-os/shared/contracts/common/TestnetCoreBase.sol";
import {PoolRiskLib} from "@reineira-os/shared/contracts/libraries/PoolRiskLib.sol";

import {IStrategyRouter} from "../interfaces/core/IStrategyRouter.sol";
import {IYieldAdapter} from "../interfaces/plugins/IYieldAdapter.sol";

contract StrategyRouter is IStrategyRouter, TestnetCoreBase {
    using SafeERC20 for IERC20;

    uint256 public constant TIMELOCK_DELAY = 1 days;
    uint16 public constant MAX_ADAPTERS = 16;
    uint16 internal constant BPS_DENOMINATOR = 10000;

    address private _asset;
    uint16 private _maxDeploymentBps;
    uint16 private _claimsBufferBps;
    uint256 private _minIdleReserve;

    address[] private _adapterList;
    // 1-based index into `_adapterList`; 0 means not attached.
    mapping(address => uint256) private _adapterIndex;

    mapping(address => uint256) private _maxDebt;
    mapping(address => uint256) private _deployed;

    mapping(address => uint256) private _pendingAttachUnlockAt;
    mapping(address => uint256) private _pendingMaxDebtCap;
    mapping(address => uint256) private _pendingMaxDebtUnlockAt;

    uint16 private _pendingMaxDeploymentBpsValue;
    uint256 private _pendingMaxDeploymentBpsUnlockAt;

    uint256[40] private __gap;

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor(address trustedForwarder_) TestnetCoreBase(trustedForwarder_) {
        _disableInitializers();
    }

    function initialize(address owner_, address asset_) external initializer {
        if (owner_ == address(0)) revert ZeroAddress();
        if (asset_ == address(0)) revert ZeroAddress();

        __TestnetCoreBase_init(owner_);

        _asset = asset_;

        emit CoreInitialized(owner_);
    }

    // --- views ---

    function asset() external view returns (address) {
        return _asset;
    }

    function isAdapterAttached(address adapter) external view returns (bool) {
        return _adapterIndex[adapter] != 0;
    }

    function adapters() external view returns (address[] memory) {
        return _adapterList;
    }

    function maxDebt(address adapter) external view returns (uint256) {
        return _maxDebt[adapter];
    }

    function deployed(address adapter) external view returns (uint256) {
        return _deployed[adapter];
    }

    function totalDeployed() external view returns (uint256) {
        uint256 sum;
        uint256 n = _adapterList.length;
        for (uint256 i = 0; i < n; i++) {
            sum += _deployed[_adapterList[i]];
        }
        return sum;
    }

    function maxDeploymentBps() external view returns (uint16) {
        return _maxDeploymentBps;
    }

    function claimsBufferBps() external view returns (uint16) {
        return _claimsBufferBps;
    }

    function minIdleReserve() external view returns (uint256) {
        return _minIdleReserve;
    }

    function pendingAttach(address adapter) external view returns (uint256 unlockAt) {
        return _pendingAttachUnlockAt[adapter];
    }

    function pendingMaxDebt(address adapter) external view returns (uint256 newCap, uint256 unlockAt) {
        return (_pendingMaxDebtCap[adapter], _pendingMaxDebtUnlockAt[adapter]);
    }

    function pendingMaxDeploymentBps() external view returns (uint16 newBps, uint256 unlockAt) {
        return (_pendingMaxDeploymentBpsValue, _pendingMaxDeploymentBpsUnlockAt);
    }

    // --- adapter management ---

    function submitAttachAdapter(address adapter) external nonReentrant onlyOwner {
        if (adapter == address(0)) revert InvalidAdapter();
        if (_adapterIndex[adapter] != 0) revert AdapterAlreadyAttached();
        if (_adapterList.length >= MAX_ADAPTERS) revert MaxAdaptersReached();
        if (IYieldAdapter(adapter).asset() != _asset) revert AdapterAssetMismatch();

        uint256 unlockAt = block.timestamp + TIMELOCK_DELAY;
        _pendingAttachUnlockAt[adapter] = unlockAt;
        emit AdapterAttachSubmitted(adapter, unlockAt);
    }

    function executeAttachAdapter(address adapter) external nonReentrant {
        uint256 unlockAt = _pendingAttachUnlockAt[adapter];
        if (unlockAt == 0) revert AttachNotPending();
        if (block.timestamp < unlockAt) revert TimelockNotElapsed(unlockAt);
        if (_adapterIndex[adapter] != 0) revert AdapterAlreadyAttached();
        if (_adapterList.length >= MAX_ADAPTERS) revert MaxAdaptersReached();

        delete _pendingAttachUnlockAt[adapter];
        _adapterList.push(adapter);
        _adapterIndex[adapter] = _adapterList.length;
        emit AdapterAttached(adapter);
    }

    function detachAdapter(address adapter) external nonReentrant onlyOwner {
        uint256 idx = _adapterIndex[adapter];
        if (idx == 0) revert AdapterNotAttached();
        if (_deployed[adapter] != 0) revert AdapterStillHasDebt(_deployed[adapter]);

        uint256 lastIdx = _adapterList.length;
        if (idx != lastIdx) {
            address last = _adapterList[lastIdx - 1];
            _adapterList[idx - 1] = last;
            _adapterIndex[last] = idx;
        }
        _adapterList.pop();
        delete _adapterIndex[adapter];
        delete _maxDebt[adapter];
        delete _pendingMaxDebtCap[adapter];
        delete _pendingMaxDebtUnlockAt[adapter];

        emit AdapterDetached(adapter);
    }

    // --- caps ---

    function submitMaxDebtRaise(address adapter, uint256 newCap) external nonReentrant onlyOwner {
        if (_adapterIndex[adapter] == 0) revert AdapterNotAttached();
        if (newCap <= _maxDebt[adapter]) revert NotARaise();

        uint256 unlockAt = block.timestamp + TIMELOCK_DELAY;
        _pendingMaxDebtCap[adapter] = newCap;
        _pendingMaxDebtUnlockAt[adapter] = unlockAt;
        emit MaxDebtRaiseSubmitted(adapter, newCap, unlockAt);
    }

    function executeMaxDebtRaise(address adapter) external nonReentrant {
        if (_adapterIndex[adapter] == 0) revert AdapterNotAttached();
        uint256 unlockAt = _pendingMaxDebtUnlockAt[adapter];
        if (unlockAt == 0) revert MaxDebtRaiseNotPending();
        if (block.timestamp < unlockAt) revert TimelockNotElapsed(unlockAt);

        uint256 newCap = _pendingMaxDebtCap[adapter];
        delete _pendingMaxDebtCap[adapter];
        delete _pendingMaxDebtUnlockAt[adapter];
        _maxDebt[adapter] = newCap;

        emit MaxDebtSet(adapter, newCap);
    }

    function lowerMaxDebt(address adapter, uint256 newCap) external nonReentrant onlyOwner {
        if (_adapterIndex[adapter] == 0) revert AdapterNotAttached();
        if (newCap >= _maxDebt[adapter]) revert NotALower();

        _maxDebt[adapter] = newCap;
        emit MaxDebtSet(adapter, newCap);
    }

    function submitMaxDeploymentBpsRaise(uint16 newBps) external nonReentrant onlyOwner {
        if (newBps <= _maxDeploymentBps) revert NotARaise();
        PoolRiskLib.validateMaxDeploymentBps(newBps);

        uint256 unlockAt = block.timestamp + TIMELOCK_DELAY;
        _pendingMaxDeploymentBpsValue = newBps;
        _pendingMaxDeploymentBpsUnlockAt = unlockAt;
        emit MaxDeploymentBpsRaiseSubmitted(newBps, unlockAt);
    }

    function executeMaxDeploymentBpsRaise() external nonReentrant {
        uint256 unlockAt = _pendingMaxDeploymentBpsUnlockAt;
        if (unlockAt == 0) revert MaxDeploymentBpsRaiseNotPending();
        if (block.timestamp < unlockAt) revert TimelockNotElapsed(unlockAt);

        uint16 newBps = _pendingMaxDeploymentBpsValue;
        delete _pendingMaxDeploymentBpsValue;
        delete _pendingMaxDeploymentBpsUnlockAt;
        _maxDeploymentBps = newBps;

        emit MaxDeploymentBpsSet(newBps);
    }

    function lowerMaxDeploymentBps(uint16 newBps) external nonReentrant onlyOwner {
        if (newBps >= _maxDeploymentBps) revert NotALower();
        _maxDeploymentBps = newBps;
        emit MaxDeploymentBpsSet(newBps);
    }

    function setClaimsBufferBps(uint16 newBps) external nonReentrant onlyOwner {
        if (newBps > BPS_DENOMINATOR) revert InvalidBps(newBps);
        _claimsBufferBps = newBps;
        emit ClaimsBufferBpsSet(newBps);
    }

    function setMinIdleReserve(uint256 newReserve) external nonReentrant onlyOwner {
        _minIdleReserve = newReserve;
        emit MinIdleReserveSet(newReserve);
    }

    // --- operations ---

    function deposit(
        address adapter,
        uint256 amount,
        uint256 totalAssets_,
        uint256 outstandingCoverage
    ) external nonReentrant onlyOwner {
        if (_adapterIndex[adapter] == 0) revert AdapterNotAttached();

        uint256 cap = _maxDebt[adapter];
        uint256 currentDebt = _deployed[adapter];
        uint256 availableInAdapter = cap > currentDebt ? cap - currentDebt : 0;
        if (amount > availableInAdapter) revert AdapterMaxDebtExceeded(amount, availableInAdapter);

        uint256 currentlyDeployed = _liveTotalDeployed();
        PoolRiskLib.validateDeployment(
            amount,
            totalAssets_,
            currentlyDeployed,
            outstandingCoverage,
            _maxDeploymentBps,
            _claimsBufferBps
        );

        IERC20(_asset).safeTransferFrom(_msgSender(), address(this), amount);
        IERC20(_asset).forceApprove(adapter, amount);

        _deployed[adapter] = currentDebt + amount;

        IYieldAdapter(adapter).deposit(amount);

        emit Deposited(adapter, amount);
    }

    function withdraw(
        address adapter,
        uint256 amount,
        address receiver
    ) external nonReentrant onlyOwner returns (uint256 withdrawn) {
        if (_adapterIndex[adapter] == 0) revert AdapterNotAttached();

        withdrawn = IYieldAdapter(adapter).withdraw(amount, receiver);

        uint256 currentDebt = _deployed[adapter];
        _deployed[adapter] = withdrawn >= currentDebt ? 0 : currentDebt - withdrawn;

        emit Withdrawn(adapter, withdrawn);
    }

    // --- internal ---

    function _liveTotalDeployed() internal view returns (uint256 sum) {
        uint256 n = _adapterList.length;
        for (uint256 i = 0; i < n; i++) {
            sum += IYieldAdapter(_adapterList[i]).totalAssets();
        }
    }
}
