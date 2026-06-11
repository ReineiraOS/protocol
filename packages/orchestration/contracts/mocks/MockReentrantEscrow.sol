// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import {IEscrow} from "@reineira-os/shared/contracts/interfaces/core/IEscrow.sol";
import {IERC165} from "@openzeppelin/contracts/utils/introspection/IERC165.sol";
import {IPayoutManifest} from "../interfaces/core/IPayoutManifest.sol";

contract MockReentrantEscrow is IEscrow {
    IPayoutManifest public manifest;
    uint256 public reentrantEscrowId;
    bytes32 public reentrantInvocationId;
    uint8 public reentrantGateId;
    uint256 public callDepth;

    function setManifest(address manifest_) external {
        manifest = IPayoutManifest(manifest_);
    }

    function setReentrantParams(uint256 escrowId, bytes32 invocationId, uint8 gateId) external {
        reentrantEscrowId = escrowId;
        reentrantInvocationId = invocationId;
        reentrantGateId = gateId;
    }

    function release(uint256, address, bytes calldata) external {
        if (callDepth == 0) {
            callDepth++;
            manifest.onGateFired(reentrantEscrowId, reentrantInvocationId, reentrantGateId);
        }
    }

    // Unused IEscrow stubs
    function create(bytes calldata, address, bytes calldata) external returns (uint256) {
        return 0;
    }
    function create(address, uint256, address, bytes calldata) external returns (uint256) {
        return 0;
    }
    function fund(uint256, bytes calldata) external {}
    function isFunded(uint256) external view returns (bool) {
        return true;
    }
    function budget(uint256) external view returns (bytes memory) {
        return "";
    }
    function redeem(uint256) external {}
    function redeemMultiple(uint256[] calldata) external {}
    function total() external view returns (uint256) {
        return 0;
    }
    function registerFeeModule(uint8, address) external {}
    function setCoverageManager(address) external {}
    function getFeeModule(uint8) external view returns (address) {
        return address(0);
    }
    function status(uint256) external view returns (Phase) {
        return Phase.Open;
    }
    function exists(uint256) external view returns (bool) {
        return true;
    }
    function supportsInterface(bytes4 interfaceId) external pure returns (bool) {
        return interfaceId == type(IEscrow).interfaceId || interfaceId == type(IERC165).interfaceId;
    }
}
