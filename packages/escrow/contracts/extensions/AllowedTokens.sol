// SPDX-License-Identifier: FSL-1.1-ALv2
// Copyright (c) 2026 Reineira Labs Limited All rights reserved.
pragma solidity ^0.8.25;

import {EscrowLib} from "@reineira-os/shared/contracts/libraries/EscrowLib.sol";
import {IEscrowEvents} from "@reineira-os/shared/contracts/interfaces/core/IEscrowEvents.sol";

abstract contract AllowedTokens is IEscrowEvents {
    /// @custom:storage-location erc7201:reineira.storage.AllowedTokens
    struct AllowedTokensStorage {
        mapping(address => bool) allowed;
        mapping(uint256 => address) paymentTokenOf;
    }

    // keccak256(abi.encode(uint256(keccak256("reineira.storage.AllowedTokens")) - 1)) & ~bytes32(uint256(0xff))
    bytes32 private constant ALLOWED_TOKENS_STORAGE_LOCATION =
        0xa34ff427081f28d50fd66eacfbab47ac3001df068b02df5a6fd55fbc551ca700;

    function _getAllowedTokensStorage() private pure returns (AllowedTokensStorage storage $) {
        assembly {
            $.slot := ALLOWED_TOKENS_STORAGE_LOCATION
        }
    }

    function _isAllowedToken(address token) internal view returns (bool) {
        return _getAllowedTokensStorage().allowed[token];
    }

    function _paymentTokenOfRaw(uint256 escrowId) internal view returns (address) {
        return _getAllowedTokensStorage().paymentTokenOf[escrowId];
    }

    function _addAllowedToken(address token) internal {
        _getAllowedTokensStorage().allowed[token] = true;
        emit TokenAllowed(token);
    }

    function _removeAllowedToken(address token) internal {
        _getAllowedTokensStorage().allowed[token] = false;
        emit TokenRemoved(token);
    }

    function _seedAllowedToken(address token) internal {
        _getAllowedTokensStorage().allowed[token] = true;
    }

    function _requireAllowedToken(address token) internal view {
        if (!_getAllowedTokensStorage().allowed[token]) revert EscrowLib.TokenNotAllowed(token);
    }

    function _setPaymentTokenOf(uint256 escrowId, address token) internal {
        _getAllowedTokensStorage().paymentTokenOf[escrowId] = token;
    }
}
