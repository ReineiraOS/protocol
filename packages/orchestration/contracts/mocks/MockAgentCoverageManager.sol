// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IAgentCoverageManager} from "../interfaces/core/IAgentCoverageManager.sol";

contract MockAgentCoverageManager is IAgentCoverageManager {
    uint256 private _nextCoverageId = 1;
    mapping(uint256 => bool) public purchaseFailed;
    bool public globalFail;

    function setPurchaseFail(uint256 escrowId, bool fail) external {
        purchaseFailed[escrowId] = fail;
    }

    function setGlobalFail(bool fail) external {
        globalFail = fail;
    }

    function purchaseCoverage(
        uint256 escrowId,
        address,
        address,
        uint256,
        uint256,
        bytes calldata,
        bytes calldata
    ) external returns (uint256 coverageId) {
        if (globalFail || purchaseFailed[escrowId]) {
            revert("MockAgentCoverageManager: purchase failed");
        }
        coverageId = _nextCoverageId++;
    }
}
