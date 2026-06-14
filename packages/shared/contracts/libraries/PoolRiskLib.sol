// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 Reineira Labs Limited All rights reserved.
pragma solidity ^0.8.24;

import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";

/// @title PoolRiskLib
/// @notice Reserve math governing how much idle recourse-pool liquidity may be deployed
///         to external yield venues. Enforces a structural floor (a fixed share of assets
///         held liquid) plus a claims buffer scaled to outstanding coverage, so that claims
///         and redemptions remain serviceable while idle capital earns yield.
library PoolRiskLib {
    uint16 internal constant BPS_DENOMINATOR = 10000;

    /// @notice Hard ceiling on the share of pool assets deployable to external venues.
    ///         Managers may configure a lower limit freely; raising toward this ceiling is
    ///         expected to be timelocked at the call site. The ceiling itself is immutable.
    uint16 internal constant MAX_DEPLOYMENT_CEILING_BPS = 7000;

    error MaxDeploymentTooHigh(uint16 bps);
    error DeploymentExceedsLimit(uint256 requested, uint256 available);

    /// @notice Minimum liquid (idle) capital the pool must retain.
    /// @return The structural floor `(1 - maxDeploymentBps)` of assets plus a claims buffer
    ///         of `claimsBufferBps` of outstanding coverage, each rounded up.
    function requiredLiquidity(
        uint256 totalAssets,
        uint256 outstandingCoverage,
        uint16 maxDeploymentBps,
        uint16 claimsBufferBps
    ) internal pure returns (uint256) {
        uint256 structuralFloor = Math.mulDiv(
            totalAssets,
            BPS_DENOMINATOR - maxDeploymentBps,
            BPS_DENOMINATOR,
            Math.Rounding.Ceil
        );
        uint256 claimsBuffer = Math.mulDiv(outstandingCoverage, claimsBufferBps, BPS_DENOMINATOR, Math.Rounding.Ceil);
        return structuralFloor + claimsBuffer;
    }

    /// @notice Additional amount that may be deployed to external venues right now.
    function maxDeployable(
        uint256 totalAssets,
        uint256 currentlyDeployed,
        uint256 outstandingCoverage,
        uint16 maxDeploymentBps,
        uint16 claimsBufferBps
    ) internal pure returns (uint256) {
        uint256 reserved = requiredLiquidity(totalAssets, outstandingCoverage, maxDeploymentBps, claimsBufferBps) +
            currentlyDeployed;
        if (totalAssets <= reserved) {
            return 0;
        }
        return totalAssets - reserved;
    }

    /// @notice Reverts unless `amount` can be deployed without breaching the reserve.
    function validateDeployment(
        uint256 amount,
        uint256 totalAssets,
        uint256 currentlyDeployed,
        uint256 outstandingCoverage,
        uint16 maxDeploymentBps,
        uint16 claimsBufferBps
    ) internal pure {
        uint256 available = maxDeployable(
            totalAssets,
            currentlyDeployed,
            outstandingCoverage,
            maxDeploymentBps,
            claimsBufferBps
        );
        if (amount > available) {
            revert DeploymentExceedsLimit(amount, available);
        }
    }

    /// @notice Reverts if a configured deployment limit exceeds the immutable ceiling.
    function validateMaxDeploymentBps(uint16 bps) internal pure {
        if (bps > MAX_DEPLOYMENT_CEILING_BPS) {
            revert MaxDeploymentTooHigh(bps);
        }
    }
}
