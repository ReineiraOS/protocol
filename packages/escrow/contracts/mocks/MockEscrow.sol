// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import {IEscrow} from "@reineira-os/shared/contracts/interfaces/core/IEscrow.sol";
import {IERC165} from "@openzeppelin/contracts/utils/introspection/IERC165.sol";

contract MockEscrow is IEscrow {
    struct ReleaseCall {
        uint256 escrowId;
        address recipient;
        bytes amount;
    }

    ReleaseCall[] public releaseCalls;

    function release(uint256 escrowId, address recipient, bytes calldata amount) external {
        releaseCalls.push(ReleaseCall(escrowId, recipient, amount));
    }

    function getReleaseCallCount() external view returns (uint256) {
        return releaseCalls.length;
    }

    function getReleaseCall(uint256 index) external view returns (ReleaseCall memory) {
        return releaseCalls[index];
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
