// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 Reineira Labs Limited All rights reserved.
pragma solidity ^0.8.24;

library FeeLib {
    enum FeeKind {
        Condition,
        Underwriter,
        Reserved
    }

    uint256 internal constant MAX_FEE_KIND = 3;
    uint16 internal constant MAX_TOTAL_BPS = 10000;

    function isValidKind(uint8 kind) internal pure returns (bool) {
        return uint256(kind) < MAX_FEE_KIND;
    }
}
