// SPDX-License-Identifier: FSL-1.1-ALv2
// Copyright (c) 2026 Reineira Labs Limited All rights reserved.
pragma solidity ^0.8.24;

import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {IERC20} from "@openzeppelin/contracts/interfaces/IERC20.sol";
import {IPoolFactory} from "../interfaces/core/IPoolFactory.sol";
import {RecoursePool} from "./RecoursePool.sol";
import {TestnetCoreBase} from "@reineira-os/shared/contracts/common/TestnetCoreBase.sol";
import {PoolFactoryLib} from "@reineira-os/shared/contracts/libraries/PoolFactoryLib.sol";

contract PoolFactory is IPoolFactory, TestnetCoreBase {
    address private _recoursePoolImplementation;
    address private _coverageManager;
    address private _policyRegistry;

    uint256 private _nextPoolId;
    mapping(uint256 => address) private _pools;
    mapping(address => bool) private _isPool;
    mapping(address => bool) private _allowedTokens;

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor(address trustedForwarder_) TestnetCoreBase(trustedForwarder_) {
        _disableInitializers();
    }

    function initialize(
        address owner_,
        address recoursePoolImplementation_,
        address coverageManager_,
        address policyRegistry_
    ) external initializer {
        if (owner_ == address(0)) revert ZeroAddress();
        if (recoursePoolImplementation_ == address(0)) revert ZeroAddress();
        if (coverageManager_ == address(0)) revert ZeroAddress();
        if (policyRegistry_ == address(0)) revert ZeroAddress();

        __TestnetCoreBase_init(owner_);

        _recoursePoolImplementation = recoursePoolImplementation_;
        _coverageManager = coverageManager_;
        _policyRegistry = policyRegistry_;

        emit CoreInitialized(owner_);
    }

    function addAllowedToken(address token_) external onlyOwner {
        if (token_ == address(0)) revert ZeroAddress();
        _allowedTokens[token_] = true;
        emit TokenAllowed(token_);
    }

    function removeAllowedToken(address token_) external onlyOwner {
        _allowedTokens[token_] = false;
        emit TokenRemoved(token_);
    }

    function isAllowedToken(address token_) external view returns (bool) {
        return _allowedTokens[token_];
    }

    function createPool(
        address paymentToken_,
        address initialManager,
        address guardian_,
        bool isOpen_
    ) external returns (uint256 poolId, address pool_) {
        if (paymentToken_ == address(0)) revert ZeroAddress();
        if (!_allowedTokens[paymentToken_]) revert PoolFactoryLib.TokenNotAllowed();

        address creator_ = _msgSender();
        address manager_ = initialManager == address(0) ? creator_ : initialManager;

        bytes memory initData = abi.encodeCall(
            RecoursePool.initialize,
            (creator_, manager_, guardian_, isOpen_, IERC20(paymentToken_), _coverageManager, _policyRegistry)
        );

        ERC1967Proxy proxy = new ERC1967Proxy(_recoursePoolImplementation, initData);
        pool_ = address(proxy);

        poolId = _nextPoolId++;
        _pools[poolId] = pool_;
        _isPool[pool_] = true;

        emit PoolCreated(poolId, pool_, creator_, manager_, guardian_, isOpen_);
    }

    function pool(uint256 poolId) external view returns (address) {
        address addr = _pools[poolId];
        if (addr == address(0)) revert PoolFactoryLib.PoolDoesNotExist();
        return addr;
    }

    function poolCount() external view returns (uint256) {
        return _nextPoolId;
    }

    function isPool(address pool_) external view returns (bool) {
        return _isPool[pool_];
    }
}
