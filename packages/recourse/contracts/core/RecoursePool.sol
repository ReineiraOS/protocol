// SPDX-License-Identifier: FSL-1.1-ALv2
// Copyright (c) 2026 Reineira Labs Limited All rights reserved.
pragma solidity ^0.8.24;

import {IERC20} from "@openzeppelin/contracts/interfaces/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {EIP712Upgradeable} from "@openzeppelin/contracts-upgradeable/utils/cryptography/EIP712Upgradeable.sol";
import {IRecoursePool} from "../interfaces/core/IRecoursePool.sol";
import {IPolicyRegistry} from "../interfaces/core/IPolicyRegistry.sol";
import {TestnetCoreBase} from "@reineira-os/shared/contracts/common/TestnetCoreBase.sol";
import {RecoursePoolLib} from "@reineira-os/shared/contracts/libraries/RecoursePoolLib.sol";

contract RecoursePool is IRecoursePool, TestnetCoreBase, EIP712Upgradeable {
    using SafeERC20 for IERC20;

    struct Stake {
        address owner;
        uint256 amount;
    }

    address private _creator;
    IERC20 private _paymentToken;
    address private _coverageManager;
    address private _policyRegistry;

    uint256 private _nextStakeId;
    uint256 private _totalLiquidity;
    uint256 private _totalPremiums;

    mapping(uint256 => Stake) private _stakes;
    mapping(address => bool) private _allowedPolicies;

    address private _manager;
    address private _guardian;
    bool private _isOpen;

    modifier onlyCreator() {
        if (_msgSender() != _creator) revert RecoursePoolLib.NotCreator();
        _;
    }

    modifier onlyManager() {
        if (_msgSender() != _manager) revert RecoursePoolLib.NotManager();
        _;
    }

    modifier onlyCoverageManager() {
        if (_msgSender() != _coverageManager) revert RecoursePoolLib.NotCoverageManager();
        _;
    }

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor(address trustedForwarder_) TestnetCoreBase(trustedForwarder_) {
        _disableInitializers();
    }

    function initialize(
        address creator_,
        address manager_,
        address guardian_,
        bool isOpen_,
        IERC20 paymentToken_,
        address coverageManager_,
        address policyRegistry_
    ) external initializer {
        if (creator_ == address(0)) revert ZeroAddress();
        if (manager_ == address(0)) revert ZeroAddress();
        if (address(paymentToken_) == address(0)) revert ZeroAddress();
        if (coverageManager_ == address(0)) revert ZeroAddress();
        if (policyRegistry_ == address(0)) revert ZeroAddress();

        __TestnetCoreBase_init(creator_);
        __EIP712_init("Reineira RecoursePool", "1");

        _creator = creator_;
        _manager = manager_;
        _guardian = guardian_;
        _isOpen = isOpen_;
        _paymentToken = paymentToken_;
        _coverageManager = coverageManager_;
        _policyRegistry = policyRegistry_;

        emit CoreInitialized(creator_);
    }

    function creator() external view returns (address) {
        return _creator;
    }

    function manager() external view returns (address) {
        return _manager;
    }

    function guardian() external view returns (address) {
        return _guardian;
    }

    function isOpen() external view returns (bool) {
        return _isOpen;
    }

    function domainSeparator() external view returns (bytes32) {
        return _domainSeparatorV4();
    }

    function transferManager(address newManager) external onlyManager {
        if (newManager == address(0)) revert ZeroAddress();
        if (newManager == _manager) revert RecoursePoolLib.SameAddress();
        address previous = _manager;
        _manager = newManager;
        emit ManagerTransferred(previous, newManager);
    }

    function paymentToken() external view returns (IERC20) {
        return _paymentToken;
    }

    function coverageManager() external view returns (address) {
        return _coverageManager;
    }

    function addPolicy(address policy_) external nonReentrant onlyCreator {
        if (policy_ == address(0)) revert ZeroAddress();
        if (!IPolicyRegistry(_policyRegistry).isPolicy(policy_)) revert RecoursePoolLib.InvalidPolicy();
        _allowedPolicies[policy_] = true;
        emit PolicyAdded(policy_);
    }

    function removePolicy(address policy_) external nonReentrant onlyCreator {
        if (policy_ == address(0)) revert ZeroAddress();
        _allowedPolicies[policy_] = false;
        emit PolicyRemoved(policy_);
    }

    function isPolicy(address policy_) external view returns (bool) {
        return _allowedPolicies[policy_];
    }

    function stake(uint256 amount) external nonReentrant returns (uint256 stakeId) {
        address sender = _msgSender();

        uint256 balanceBefore = _paymentToken.balanceOf(address(this));
        _paymentToken.safeTransferFrom(sender, address(this), amount);
        uint256 actualAmount = _paymentToken.balanceOf(address(this)) - balanceBefore;

        stakeId = _nextStakeId++;
        _stakes[stakeId] = Stake({owner: sender, amount: actualAmount});

        _totalLiquidity += actualAmount;

        emit Staked(stakeId);
    }

    function unstake(uint256 stakeId) external nonReentrant {
        Stake storage s = _stakes[stakeId];
        RecoursePoolLib.validateStakeExists(s.owner != address(0));
        RecoursePoolLib.validateStakeOwner(s.owner, _msgSender());

        uint256 amount = s.amount;
        _totalLiquidity -= amount;

        delete _stakes[stakeId];

        _paymentToken.safeTransfer(_msgSender(), amount);

        emit Unstaked(stakeId);
    }

    function payClaim(uint256 coverageId, uint256 amount) external nonReentrant onlyCoverageManager returns (uint256) {
        uint256 cappedAmount = amount <= _totalLiquidity ? amount : _totalLiquidity;

        _totalLiquidity -= cappedAmount;

        _paymentToken.safeTransfer(_msgSender(), cappedAmount);

        emit ClaimPaid();
        (coverageId);
        return cappedAmount;
    }

    function receivePremium(uint256 coverageId, uint256 premium) external nonReentrant onlyCoverageManager {
        _totalPremiums += premium;

        emit PremiumReceived();
        (coverageId);
    }

    function stakedAmount(uint256 stakeId) external view returns (uint256) {
        RecoursePoolLib.validateStakeExists(_stakes[stakeId].owner != address(0));
        return _stakes[stakeId].amount;
    }

    function totalLiquidity() external view returns (uint256) {
        return _totalLiquidity;
    }

    function pendingRewards(uint256 stakeId) external view returns (uint256) {
        RecoursePoolLib.validateStakeExists(_stakes[stakeId].owner != address(0));
        return 0;
    }

    function claimRewards(uint256 stakeId) external nonReentrant {
        Stake storage s = _stakes[stakeId];
        RecoursePoolLib.validateStakeExists(s.owner != address(0));
        RecoursePoolLib.validateStakeOwner(s.owner, _msgSender());
        emit RewardsClaimed(stakeId);
    }

    function claimPremiums(uint256 amount) external nonReentrant onlyManager {
        address sender = _msgSender();

        uint256 cappedAmount = amount <= _totalPremiums ? amount : _totalPremiums;

        _totalPremiums -= cappedAmount;

        _paymentToken.safeTransfer(sender, cappedAmount);
    }
}
