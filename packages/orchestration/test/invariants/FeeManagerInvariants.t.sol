// SPDX-License-Identifier: FSL-1.1-ALv2
pragma solidity ^0.8.25;

import {Test} from "forge-std/Test.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {FeeManager} from "../../contracts/core/FeeManager.sol";
import {MockUSDC} from "@reineira-os/shared/contracts/mocks/MockUSDC.sol";

contract FeeManagerHandler is Test {
    FeeManager public immutable manager;
    MockUSDC public immutable token;
    address public immutable owner;
    address public immutable collector;
    uint256 public immutable initialBalance;

    constructor(FeeManager _manager, MockUSDC _token, address _owner, address _collector) {
        manager = _manager;
        token = _token;
        owner = _owner;
        collector = _collector;
        initialBalance = 100_000_000e6;
        token.mint(address(manager), initialBalance);
    }

    function setFees(uint256 operatorBps) external {
        operatorBps = bound(operatorBps, 0, 10_000);
        vm.prank(owner);
        try manager.setFeeConfig(operatorBps) {} catch {}
    }

    function collectFee(bytes32 taskHash, address operator, uint256 amount) external {
        amount = bound(amount, 0, 10_000_000e6);
        if (operator == address(0)) operator = makeAddr("op-fallback");
        vm.prank(collector);
        try manager.collectFee(taskHash, operator, amount) {} catch {}
    }
}

contract FeeManagerInvariantTest is Test {
    FeeManager public manager;
    MockUSDC public token;
    FeeManagerHandler public handler;
    address public owner;
    address public collector;

    function setUp() public {
        owner = makeAddr("owner");
        collector = makeAddr("collector");

        vm.startPrank(owner);
        token = new MockUSDC();
        FeeManager impl = new FeeManager(address(0));
        manager = FeeManager(
            address(
                new ERC1967Proxy(
                    address(impl),
                    abi.encodeCall(FeeManager.initialize, (owner, address(token), collector, 250))
                )
            )
        );
        vm.stopPrank();

        handler = new FeeManagerHandler(manager, token, owner, collector);
        targetContract(address(handler));

        bytes4[] memory selectors = new bytes4[](2);
        selectors[0] = FeeManagerHandler.setFees.selector;
        selectors[1] = FeeManagerHandler.collectFee.selector;
        targetSelector(FuzzSelector({addr: address(handler), selectors: selectors}));
    }

    function invariant_operatorFeeBps_within_bounds() public view {
        assertLe(manager.operatorFeeBps(), 10_000);
    }

    function invariant_balance_never_exceeds_initial() public view {
        assertLe(
            token.balanceOf(address(manager)),
            handler.initialBalance(),
            "fee manager balance grew beyond the initial funding"
        );
    }
}
