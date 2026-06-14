// SPDX-License-Identifier: FSL-1.1-ALv2
// Copyright (c) 2026 Reineira Labs Limited All rights reserved.
pragma solidity ^0.8.25;

import {IConditionResolver} from "@reineira-os/shared/contracts/interfaces/plugins/IConditionResolver.sol";

abstract contract EscrowCondition {
    event ConditionSet(uint256 indexed escrowId, address indexed resolver);

    error ConditionNotMet(uint256 escrowId);
    error InvalidResolver();

    /// @custom:storage-location erc7201:reineira.storage.EscrowCondition
    struct ConditionStorage {
        mapping(uint256 => IConditionResolver) resolvers;
    }

    // Frozen ERC-7201 slot from this contract's original (pre-rebrand) namespace id, hardcoded to keep
    // UUPS upgrade compatibility with the deployed proxy. It does not match the namespace annotated above
    // and must not be recomputed from it; a clean slot is derived at the next (re)deployment.
    bytes32 private constant CONDITION_STORAGE_LOCATION =
        0xddbe0eff506238e35addb19b3c2d99c00660b3894c8f79a6042996acddf4e100;

    function _getConditionStorage() private pure returns (ConditionStorage storage $) {
        assembly {
            $.slot := CONDITION_STORAGE_LOCATION
        }
    }

    function getConditionResolver(uint256 escrowId) external view returns (address) {
        return address(_getConditionStorage().resolvers[escrowId]);
    }

    function _setCondition(uint256 escrowId, address resolver, bytes calldata resolverData) internal {
        if (resolver.code.length == 0) revert InvalidResolver();
        _getConditionStorage().resolvers[escrowId] = IConditionResolver(resolver);
        IConditionResolver(resolver).onConditionSet(escrowId, resolverData);
        emit ConditionSet(escrowId, resolver);
    }

    function _checkCondition(uint256 escrowId) internal view returns (bool) {
        IConditionResolver resolver = _getConditionStorage().resolvers[escrowId];
        if (address(resolver) == address(0)) return true;
        if (!resolver.isConditionMet(escrowId)) revert ConditionNotMet(escrowId);
        return true;
    }

    function _isConditionMet(uint256 escrowId) internal view returns (bool) {
        IConditionResolver resolver = _getConditionStorage().resolvers[escrowId];
        if (address(resolver) == address(0)) return true;
        return resolver.isConditionMet(escrowId);
    }
}
