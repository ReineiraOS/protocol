// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 Reineira Labs Limited All rights reserved.
pragma solidity ^0.8.24;

library CoverageLib {
    enum CoverageStatus {
        None,
        Active,
        Disputed,
        Claimed,
        Expired
    }

    error CoverageDoesNotExist();
    error NotActiveStatus();
    error NotCoverageHolder();
    error InvalidPool();
    error InvalidPolicy();
    error InvalidExpiry();
    error EscrowDoesNotExist();
    error EscrowNotConfigured();
    error PoolFactoryNotConfigured();
    error DisputeRejected();
    error NotManager();
    error InvitePoolMismatch();
    error InviteeMismatch();
    error InviteExpired();
    error InviteExhausted();
    error InviteAlreadyRevoked();
    error InviteSignerMismatch();
    error CoverageAlreadyPaid();
    error MaxCoveragesReached();

    function validateCoverageExists(CoverageStatus status) internal pure {
        if (status == CoverageStatus.None) revert CoverageDoesNotExist();
    }

    function validateActiveStatus(CoverageStatus status) internal pure {
        if (status != CoverageStatus.Active) revert NotActiveStatus();
    }

    function validateHolder(address coverageHolder, address caller) internal pure {
        if (caller != coverageHolder) revert NotCoverageHolder();
    }

    function validateExpiry(uint256 expiry, uint256 nowTs) internal pure {
        if (expiry <= nowTs) revert InvalidExpiry();
    }
}
