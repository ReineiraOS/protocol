// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {ERC165} from "@openzeppelin/contracts/utils/introspection/ERC165.sol";
import {IERC165} from "@openzeppelin/contracts/utils/introspection/IERC165.sol";
import {IConditionResolver} from "@reineira-os/shared/contracts/interfaces/plugins/IConditionResolver.sol";
import {IQuorumAttestedResolver} from "../interfaces/core/IQuorumAttestedResolver.sol";

contract MockQuorumAttestedResolver is IQuorumAttestedResolver, ERC165 {
    mapping(uint256 => bool) public inputGates;
    mapping(uint256 => bool) public outputGates;
    bool public quorumValid = true;
    bool public conditionMet = false;
    uint16 public feeBps;
    address public feeRecipient;

    function setConditionMet(bool met) external {
        conditionMet = met;
    }

    function setQuorumValid(bool valid) external {
        quorumValid = valid;
    }

    function setConditionFee(uint16 bps, address recipient) external {
        feeBps = bps;
        feeRecipient = recipient;
    }

    function triggerInputGate(uint256 escrowId) external {
        if (inputGates[escrowId]) revert GateAlreadyTriggered();
        inputGates[escrowId] = true;
        emit InputGateTriggered(escrowId);
    }

    function triggerOutputGate(uint256 escrowId, bytes calldata, bytes calldata) external {
        if (outputGates[escrowId]) revert GateAlreadyTriggered();
        outputGates[escrowId] = true;
        emit OutputGateTriggered(escrowId);
    }

    function isInputGateTriggered(uint256 escrowId) external view returns (bool) {
        return inputGates[escrowId];
    }

    function isOutputGateTriggered(uint256 escrowId) external view returns (bool) {
        return outputGates[escrowId];
    }

    function verifyQuorum(bytes calldata, bytes calldata) external view returns (bool) {
        return quorumValid;
    }

    function isConditionMet(uint256) external view override returns (bool) {
        return conditionMet;
    }

    function onConditionSet(uint256, bytes calldata) external override {}

    function getConditionFee(uint256) external view override returns (uint16 bps, address recipient) {
        return (feeBps, feeRecipient);
    }

    function supportsInterface(bytes4 interfaceId) public view override(ERC165, IERC165) returns (bool) {
        return interfaceId == type(IConditionResolver).interfaceId ||
               interfaceId == type(IQuorumAttestedResolver).interfaceId ||
               super.supportsInterface(interfaceId);
    }
}
