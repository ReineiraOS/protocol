// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 Reineira Labs Limited All rights reserved.
pragma solidity ^0.8.24;

library RecoursePoolLib {
    error NotUnderwriter();
    error NotCoverageManager();
    error NotStakeOwner();
    error StakeDoesNotExist();
    error InvalidPolicy();
    error InsufficientPoolBalance();
    error NotCreator();
    error NotManager();
    error SameAddress();

    function validateStakeExists(bool exists_) internal pure {
        if (!exists_) revert StakeDoesNotExist();
    }

    function validateStakeOwner(address stakeOwner, address caller) internal pure {
        if (stakeOwner != caller) revert NotStakeOwner();
    }
}
