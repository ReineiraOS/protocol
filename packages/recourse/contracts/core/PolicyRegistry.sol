// SPDX-License-Identifier: FSL-1.1-ALv2
// Copyright (c) 2026 Reineira Labs Limited All rights reserved.
pragma solidity ^0.8.24;

import {ERC165Checker} from "@openzeppelin/contracts/utils/introspection/ERC165Checker.sol";
import {IPolicyRegistry} from "../interfaces/core/IPolicyRegistry.sol";
import {IUnderwriterPolicy} from "@reineira-os/shared/contracts/interfaces/plugins/IUnderwriterPolicy.sol";
import {TestnetCoreBase} from "@reineira-os/shared/contracts/common/TestnetCoreBase.sol";
import {PolicyRegistryLib} from "@reineira-os/shared/contracts/libraries/PolicyRegistryLib.sol";

contract PolicyRegistry is IPolicyRegistry, TestnetCoreBase {
    uint256 private _nextPolicyId;
    mapping(uint256 => address) private _policies;
    mapping(address => bool) private _registered;

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor(address trustedForwarder_) TestnetCoreBase(trustedForwarder_) {
        _disableInitializers();
    }

    function initialize(address owner_) external initializer {
        if (owner_ == address(0)) revert ZeroAddress();
        __TestnetCoreBase_init(owner_);
        emit CoreInitialized(owner_);
    }

    function registerPolicy(address policy_) external onlyOwner returns (uint256 policyId) {
        if (policy_ == address(0)) revert ZeroAddress();
        if (_registered[policy_]) revert PolicyRegistryLib.PolicyAlreadyRegistered();
        if (!ERC165Checker.supportsInterface(policy_, type(IUnderwriterPolicy).interfaceId)) {
            revert PolicyRegistryLib.InvalidPolicyInterface();
        }

        policyId = _nextPolicyId++;
        _policies[policyId] = policy_;
        _registered[policy_] = true;

        emit PolicyRegistered(policyId, policy_, _msgSender());
    }

    function policy(uint256 policyId) external view returns (address) {
        address addr = _policies[policyId];
        if (addr == address(0)) revert PolicyRegistryLib.PolicyDoesNotExist();
        return addr;
    }

    function policyCount() external view returns (uint256) {
        return _nextPolicyId;
    }

    function isPolicy(address policy_) external view returns (bool) {
        return _registered[policy_];
    }
}
