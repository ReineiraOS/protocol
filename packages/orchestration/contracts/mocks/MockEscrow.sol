// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IERC165} from "@openzeppelin/contracts/interfaces/IERC165.sol";
import {IEscrow} from "@reineira-os/shared/contracts/interfaces/core/IEscrow.sol";

contract MockEscrow is IEscrow {
    uint256 private _nextId = 1;
    mapping(uint256 => bool) public funded;
    mapping(uint256 => address) public escrowResolvers;
    bool public createFail;
    bool public fundFail;

    function setCreateFail(bool fail) external {
        createFail = fail;
    }

    function setFundFail(bool fail) external {
        fundFail = fail;
    }

    function create(
        bytes calldata,
        address resolver,
        bytes calldata
    ) external returns (uint256 escrowId) {
        if (createFail) revert InvalidInitData();
        escrowId = _nextId++;
        escrowResolvers[escrowId] = resolver;
        emit EscrowCreated(escrowId);
    }

    function create(
        address,
        uint256,
        address resolver,
        bytes calldata
    ) external returns (uint256 escrowId) {
        if (createFail) revert InvalidInitData();
        escrowId = _nextId++;
        escrowResolvers[escrowId] = resolver;
        emit EscrowCreated(escrowId);
    }

    function fund(uint256 escrowId, bytes calldata) external {
        if (fundFail) revert InvalidFundingProof();
        funded[escrowId] = true;
        emit EscrowFunded(escrowId, msg.sender);
    }

    function isFunded(uint256) external pure returns (bool) {
        return true;
    }

    function budget(uint256) external pure returns (bytes memory) {
        return "";
    }

    function release(uint256, address, bytes calldata) external pure {}

    function status(uint256) external pure returns (Phase) {
        return Phase.Funded;
    }

    function redeem(uint256) external pure {}

    function redeemMultiple(uint256[] calldata) external pure {}

    function exists(uint256 escrowId) external view returns (bool) {
        return escrowId < _nextId;
    }

    function total() external view returns (uint256) {
        return _nextId - 1;
    }

    function setCoverageManager(address) external pure {}

    function supportsInterface(bytes4 interfaceId) external pure returns (bool) {
        return interfaceId == type(IEscrow).interfaceId || interfaceId == type(IERC165).interfaceId;
    }
}
