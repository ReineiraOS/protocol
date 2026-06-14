// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {FHE, ebool, euint64} from "@fhenixprotocol/cofhe-contracts/FHE.sol";
import {ERC165} from "@openzeppelin/contracts/utils/introspection/ERC165.sol";
import {IERC165} from "@openzeppelin/contracts/utils/introspection/IERC165.sol";
import {IConfidentialUnderwriterPolicy} from "@reineira-os/shared/contracts/interfaces/plugins/IConfidentialUnderwriterPolicy.sol";

contract MockConfidentialUnderwriterPolicy is IConfidentialUnderwriterPolicy, ERC165 {
    uint64 private _riskScoreValue;
    bool private _judgeResultValue;

    constructor() {
        _riskScoreValue = 500;
        _judgeResultValue = true;
    }

    function setRiskScore(uint64 score) external {
        _riskScoreValue = score;
    }

    function setJudgeResult(bool result) external {
        _judgeResultValue = result;
    }

    function onPolicySet(uint256, bytes calldata) external {}

    function evaluateRisk(uint256, bytes calldata) external returns (euint64) {
        euint64 score = FHE.asEuint64(_riskScoreValue);
        FHE.allowThis(score);
        FHE.allow(score, msg.sender);
        return score;
    }

    function judge(uint256, bytes calldata) external returns (ebool) {
        ebool result = FHE.asEbool(_judgeResultValue);
        FHE.allowThis(result);
        FHE.allow(result, msg.sender);
        return result;
    }

    function supportsInterface(bytes4 interfaceId) public view override(ERC165, IERC165) returns (bool) {
        return interfaceId == type(IConfidentialUnderwriterPolicy).interfaceId || super.supportsInterface(interfaceId);
    }
}
