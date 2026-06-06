// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 Reineira Labs Limited All rights reserved.
pragma solidity ^0.8.24;

library EscrowLib {
    error EscrowDoesNotExist(uint256 escrowId);
    error EmptyArray();
    error BatchSizeExceeded(uint256 size, uint256 maxSize);
    error NotCoverageManager();
    error InvalidFeeKind(uint8 kind);
    error FeeBudgetExceeded(uint16 currentSumBps, uint16 requestedBps, uint16 maxBps);
    error TokenNotAllowed(address token);

    function validateExists(bool exists_, uint256 escrowId) internal pure {
        if (!exists_) revert EscrowDoesNotExist(escrowId);
    }

    function validateNonEmpty(uint256 length) internal pure {
        if (length == 0) revert EmptyArray();
    }

    function validateBatchSize(uint256 length, uint256 maxSize) internal pure {
        if (length > maxSize) revert BatchSizeExceeded(length, maxSize);
    }

    function capFee(uint256 fee, uint256 amount) internal pure returns (uint256) {
        return fee <= amount ? fee : amount;
    }
}
