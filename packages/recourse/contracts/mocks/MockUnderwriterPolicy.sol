// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {ERC165} from "@openzeppelin/contracts/utils/introspection/ERC165.sol";
import {IERC165} from "@openzeppelin/contracts/utils/introspection/IERC165.sol";
import {IUnderwriterPolicy} from "@reineira-os/shared/contracts/interfaces/plugins/IUnderwriterPolicy.sol";

contract MockUnderwriterPolicy is IUnderwriterPolicy, ERC165 {
    uint256 private _riskScoreValue;
    bool private _judgeResultValue;

    constructor() {
        _riskScoreValue = 500;
        _judgeResultValue = true;
    }

    function setRiskScore(uint256 score) external {
        _riskScoreValue = score;
    }

    function setJudgeResult(bool result) external {
        _judgeResultValue = result;
    }

    function onPolicySet(uint256, bytes calldata) external {}

    function evaluateRisk(uint256, bytes calldata) external view returns (uint256) {
        return _riskScoreValue;
    }

    function judge(uint256, bytes calldata) external view returns (bool) {
        return _judgeResultValue;
    }

    function supportsInterface(bytes4 interfaceId) public view override(ERC165, IERC165) returns (bool) {
        return interfaceId == type(IUnderwriterPolicy).interfaceId || super.supportsInterface(interfaceId);
    }
}
