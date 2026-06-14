// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import {ERC165} from "@openzeppelin/contracts/utils/introspection/ERC165.sol";
import {IERC165} from "@openzeppelin/contracts/utils/introspection/IERC165.sol";
import {IConditionResolver} from "@reineira-os/shared/contracts/interfaces/plugins/IConditionResolver.sol";

contract MockConditionResolver is IConditionResolver, ERC165 {
    mapping(uint256 => bool) public conditions;
    uint16 public feeBps;
    address public feeRecipient;

    function setCondition(uint256 escrowId, bool met) external {
        conditions[escrowId] = met;
    }

    function setConditionFee(uint16 bps, address recipient) external {
        feeBps = bps;
        feeRecipient = recipient;
    }

    function isConditionMet(uint256 escrowId) external view override returns (bool) {
        return conditions[escrowId];
    }

    function onConditionSet(uint256, bytes calldata) external override {}

    function getConditionFee(uint256) external view override returns (uint16 bps, address recipient) {
        return (feeBps, feeRecipient);
    }

    function supportsInterface(bytes4 interfaceId) public view override(ERC165, IERC165) returns (bool) {
        return interfaceId == type(IConditionResolver).interfaceId || super.supportsInterface(interfaceId);
    }
}
