// SPDX-License-Identifier: FSL-1.1-ALv2
// Copyright (c) 2026 Reineira Labs Limited All rights reserved.
pragma solidity ^0.8.24;

import {FHE, euint64, InEuint64} from "@fhenixprotocol/cofhe-contracts/FHE.sol";
import {IFHERC20} from "fhenix-confidential-contracts/contracts/interfaces/IFHERC20.sol";
import {EIP712Upgradeable} from "@openzeppelin/contracts-upgradeable/utils/cryptography/EIP712Upgradeable.sol";
import {IConfidentialRecoursePool} from "../interfaces/core/IConfidentialRecoursePool.sol";
import {IConfidentialPolicyRegistry} from "../interfaces/core/IConfidentialPolicyRegistry.sol";
import {TestnetCoreBase} from "@reineira-os/shared/contracts/common/TestnetCoreBase.sol";
import {FHEMeta} from "@reineira-os/shared/contracts/common/FHEMeta.sol";
import {RecoursePoolLib} from "@reineira-os/shared/contracts/libraries/RecoursePoolLib.sol";

contract ConfidentialRecoursePool is IConfidentialRecoursePool, TestnetCoreBase, EIP712Upgradeable {
    struct Stake {
        address owner;
        euint64 amount;
    }

    address private _creator;
    IFHERC20 private _paymentToken;
    address private _coverageManager;
    address private _policyRegistry;

    uint256 private _nextStakeId;
    euint64 private _totalLiquidity;
    euint64 private _totalPremiums;
    euint64 private _encryptedZero;

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
        IFHERC20 paymentToken_,
        address coverageManager_,
        address policyRegistry_
    ) external initializer {
        if (creator_ == address(0)) revert ZeroAddress();
        if (manager_ == address(0)) revert ZeroAddress();
        if (address(paymentToken_) == address(0)) revert ZeroAddress();
        if (coverageManager_ == address(0)) revert ZeroAddress();
        if (policyRegistry_ == address(0)) revert ZeroAddress();

        __TestnetCoreBase_init(creator_);
        __EIP712_init("Reineira ConfidentialRecoursePool", "1");

        _creator = creator_;
        _manager = manager_;
        _guardian = guardian_;
        _isOpen = isOpen_;
        _paymentToken = paymentToken_;
        _coverageManager = coverageManager_;
        _policyRegistry = policyRegistry_;

        _encryptedZero = FHE.asEuint64(0);
        FHE.allowThis(_encryptedZero);
        _totalLiquidity = FHE.asEuint64(0);
        FHE.allowThis(_totalLiquidity);
        _totalPremiums = FHE.asEuint64(0);
        FHE.allowThis(_totalPremiums);

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

    function paymentToken() external view returns (IFHERC20) {
        return _paymentToken;
    }

    function coverageManager() external view returns (address) {
        return _coverageManager;
    }

    function addPolicy(address policy_) external nonReentrant onlyCreator {
        if (policy_ == address(0)) revert ZeroAddress();
        if (!IConfidentialPolicyRegistry(_policyRegistry).isPolicy(policy_)) revert RecoursePoolLib.InvalidPolicy();
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

    function stake(InEuint64 calldata encryptedAmount) external nonReentrant returns (uint256 stakeId) {
        address sender = _msgSender();
        euint64 amount = FHEMeta.asEuint64(encryptedAmount, sender);

        euint64 balanceBefore = _paymentToken.confidentialBalanceOf(address(this));
        FHE.allowTransient(amount, address(_paymentToken));
        _paymentToken.confidentialTransferFrom(sender, address(this), amount);
        euint64 balanceAfter = _paymentToken.confidentialBalanceOf(address(this));
        euint64 actualAmount = FHE.sub(balanceAfter, balanceBefore);

        stakeId = _nextStakeId++;
        _stakes[stakeId] = Stake({owner: sender, amount: actualAmount});

        FHE.allowThis(actualAmount);
        FHE.allow(actualAmount, sender);

        _totalLiquidity = FHE.add(_totalLiquidity, actualAmount);
        FHE.allowThis(_totalLiquidity);

        emit Staked(stakeId);
    }

    function unstake(uint256 stakeId) external nonReentrant {
        Stake storage s = _stakes[stakeId];
        RecoursePoolLib.validateStakeExists(s.owner != address(0));
        RecoursePoolLib.validateStakeOwner(s.owner, _msgSender());

        euint64 amount = s.amount;
        _totalLiquidity = FHE.sub(_totalLiquidity, amount);
        FHE.allowThis(_totalLiquidity);

        delete _stakes[stakeId];

        FHE.allowTransient(amount, address(_paymentToken));
        _paymentToken.confidentialTransfer(_msgSender(), amount);

        emit Unstaked(stakeId);
    }

    function payClaim(uint256 coverageId, euint64 amount) external nonReentrant onlyCoverageManager returns (euint64) {
        euint64 cappedAmount = FHE.select(FHE.lte(amount, _totalLiquidity), amount, _totalLiquidity);

        _totalLiquidity = FHE.sub(_totalLiquidity, cappedAmount);
        FHE.allowThis(_totalLiquidity);

        FHE.allowTransient(cappedAmount, address(_paymentToken));
        FHE.allow(cappedAmount, _msgSender());
        _paymentToken.confidentialTransfer(_msgSender(), cappedAmount);

        emit ClaimPaid();
        (coverageId);
        return cappedAmount;
    }

    function receivePremium(uint256 coverageId, euint64 premium) external nonReentrant onlyCoverageManager {
        _totalPremiums = FHE.add(_totalPremiums, premium);
        FHE.allowThis(_totalPremiums);

        emit PremiumReceived();
        (coverageId);
    }

    function stakedAmount(uint256 stakeId) external view returns (euint64) {
        RecoursePoolLib.validateStakeExists(_stakes[stakeId].owner != address(0));
        return _stakes[stakeId].amount;
    }

    function totalLiquidity() external view returns (euint64) {
        return _totalLiquidity;
    }

    function pendingRewards(uint256 stakeId) external view returns (euint64) {
        RecoursePoolLib.validateStakeExists(_stakes[stakeId].owner != address(0));
        return _encryptedZero;
    }

    function claimRewards(uint256 stakeId) external nonReentrant {
        Stake storage s = _stakes[stakeId];
        RecoursePoolLib.validateStakeExists(s.owner != address(0));
        RecoursePoolLib.validateStakeOwner(s.owner, _msgSender());
        emit RewardsClaimed(stakeId);
    }

    function claimPremiums(InEuint64 calldata encryptedAmount) external nonReentrant onlyManager {
        address sender = _msgSender();
        euint64 amount = FHEMeta.asEuint64(encryptedAmount, sender);

        euint64 cappedAmount = FHE.select(FHE.lte(amount, _totalPremiums), amount, _totalPremiums);

        _totalPremiums = FHE.sub(_totalPremiums, cappedAmount);
        FHE.allowThis(_totalPremiums);

        FHE.allowTransient(cappedAmount, address(_paymentToken));
        _paymentToken.confidentialTransfer(sender, cappedAmount);
    }
}
