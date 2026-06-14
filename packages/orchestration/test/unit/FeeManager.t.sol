// SPDX-License-Identifier: FSL-1.1-ALv2
pragma solidity ^0.8.25;

import {Test} from "forge-std/Test.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {FeeManager} from "../../contracts/core/FeeManager.sol";
import {MockGovernanceToken} from "../../contracts/mocks/MockGovernanceToken.sol";
import {IFeeManager} from "../../contracts/interfaces/core/IFeeManager.sol";

contract FeeManagerTest is Test {
    FeeManager public feeManager;
    MockGovernanceToken public feeToken;

    address public owner;
    address public feeCollector;
    address public operator;
    address public user;

    uint256 public constant OPERATOR_FEE_BPS = 50;
    uint256 public constant BPS_DENOMINATOR = 10000;

    function setUp() public {
        owner = makeAddr("owner");
        feeCollector = makeAddr("feeCollector");
        operator = makeAddr("operator");
        user = makeAddr("user");

        vm.startPrank(owner);

        feeToken = new MockGovernanceToken();

        FeeManager impl = new FeeManager(address(0));
        bytes memory initData = abi.encodeCall(
            FeeManager.initialize,
            (owner, address(feeToken), feeCollector, OPERATOR_FEE_BPS)
        );
        ERC1967Proxy proxy = new ERC1967Proxy(address(impl), initData);
        feeManager = FeeManager(address(proxy));

        feeToken.mint(address(feeManager), 1_000_000 ether);

        vm.stopPrank();
    }

    // ──────────────────────────────────────────────
    // Deployment
    // ──────────────────────────────────────────────

    function test_deployment_setsCorrectParameters() public view {
        assertEq(address(feeManager.feeToken()), address(feeToken));
        assertEq(feeManager.feeCollector(), feeCollector);
        assertEq(feeManager.operatorFeeBps(), OPERATOR_FEE_BPS);
    }

    function test_deployment_setsCorrectOwner() public view {
        assertEq(feeManager.owner(), owner);
    }

    function test_deployment_revertsWithZeroFeeToken() public {
        vm.startPrank(owner);
        FeeManager impl = new FeeManager(address(0));
        bytes memory initData = abi.encodeCall(
            FeeManager.initialize,
            (owner, address(0), feeCollector, OPERATOR_FEE_BPS)
        );
        vm.expectRevert(IFeeManager.ZeroAddress.selector);
        new ERC1967Proxy(address(impl), initData);
        vm.stopPrank();
    }

    function test_deployment_revertsWithInvalidFeeConfig() public {
        vm.startPrank(owner);
        FeeManager impl = new FeeManager(address(0));
        bytes memory initData = abi.encodeCall(FeeManager.initialize, (owner, address(feeToken), feeCollector, 10001));
        vm.expectRevert(IFeeManager.InvalidFeeConfig.selector);
        new ERC1967Proxy(address(impl), initData);
        vm.stopPrank();
    }

    // ──────────────────────────────────────────────
    // Fee Calculation
    // ──────────────────────────────────────────────

    function test_calculateFee_returnsCorrectValue() public view {
        uint256 amount = 10_000 ether;
        uint256 operatorFee = feeManager.calculateFee(amount);
        assertEq(operatorFee, (amount * OPERATOR_FEE_BPS) / BPS_DENOMINATOR);
    }

    function test_calculateFee_returnsZeroForZeroAmount() public view {
        assertEq(feeManager.calculateFee(0), 0);
    }

    function test_calculateFee_respectsBps() public view {
        uint256 amount = 100_000 ether;
        uint256 operatorFee = feeManager.calculateFee(amount);
        assertEq((operatorFee * BPS_DENOMINATOR) / amount, OPERATOR_FEE_BPS);
    }

    // ──────────────────────────────────────────────
    // Fee Collection
    // ──────────────────────────────────────────────

    function test_collectFee_transfersOperatorFee() public {
        bytes32 taskHash = keccak256("test task");
        uint256 amount = 10_000 ether;

        uint256 expectedOperatorFee = feeManager.calculateFee(amount);
        uint256 operatorBalanceBefore = feeToken.balanceOf(operator);

        vm.prank(feeCollector);
        feeManager.collectFee(taskHash, operator, amount);

        assertEq(feeToken.balanceOf(operator) - operatorBalanceBefore, expectedOperatorFee);
    }

    function test_collectFee_emitsFeeCollectedEvent() public {
        bytes32 taskHash = keccak256("test task");
        uint256 amount = 10_000 ether;

        uint256 expectedOperatorFee = feeManager.calculateFee(amount);

        vm.expectEmit(true, true, false, true);
        emit IFeeManager.FeeCollected(taskHash, operator, expectedOperatorFee);

        vm.prank(feeCollector);
        feeManager.collectFee(taskHash, operator, amount);
    }

    function test_collectFee_allowsOwnerToCollect() public {
        bytes32 taskHash = keccak256("test task");
        uint256 amount = 10_000 ether;

        uint256 expectedOperatorFee = feeManager.calculateFee(amount);
        uint256 operatorBalanceBefore = feeToken.balanceOf(operator);

        vm.prank(owner);
        feeManager.collectFee(taskHash, operator, amount);

        assertEq(feeToken.balanceOf(operator) - operatorBalanceBefore, expectedOperatorFee);
    }

    function test_collectFee_revertsWhenNotAuthorized() public {
        bytes32 taskHash = keccak256("test task");
        uint256 amount = 10_000 ether;

        vm.prank(user);
        vm.expectRevert(FeeManager.NotAuthorized.selector);
        feeManager.collectFee(taskHash, operator, amount);
    }

    function test_collectFee_revertsWithZeroOperatorAddress() public {
        bytes32 taskHash = keccak256("test task");
        uint256 amount = 10_000 ether;

        vm.prank(feeCollector);
        vm.expectRevert(IFeeManager.ZeroAddress.selector);
        feeManager.collectFee(taskHash, address(0), amount);
    }

    function test_collectFee_revertsWithInsufficientBalance() public {
        vm.startPrank(owner);
        FeeManager emptyImpl = new FeeManager(address(0));
        bytes memory initData = abi.encodeCall(
            FeeManager.initialize,
            (feeCollector, address(feeToken), feeCollector, 1000)
        );
        ERC1967Proxy emptyProxy = new ERC1967Proxy(address(emptyImpl), initData);
        FeeManager emptyFeeManager = FeeManager(address(emptyProxy));
        vm.stopPrank();

        bytes32 taskHash = keccak256("test task");
        uint256 amount = 10_000 ether;

        vm.prank(feeCollector);
        vm.expectRevert(FeeManager.InsufficientBalance.selector);
        emptyFeeManager.collectFee(taskHash, operator, amount);
    }

    // ──────────────────────────────────────────────
    // Config Updates
    // ──────────────────────────────────────────────

    function test_setFeeConfig_updatesBps() public {
        uint256 newOperatorBps = 100;

        vm.prank(owner);
        feeManager.setFeeConfig(newOperatorBps);

        assertEq(feeManager.operatorFeeBps(), newOperatorBps);
    }

    function test_setFeeConfig_emitsFeeConfigUpdatedEvent() public {
        uint256 newOperatorBps = 100;

        vm.expectEmit(false, false, false, true);
        emit IFeeManager.FeeConfigUpdated(newOperatorBps);

        vm.prank(owner);
        feeManager.setFeeConfig(newOperatorBps);
    }

    function test_setFeeConfig_revertsWithInvalidFeeConfig() public {
        vm.prank(owner);
        vm.expectRevert(IFeeManager.InvalidFeeConfig.selector);
        feeManager.setFeeConfig(10001);
    }

    function test_setFeeCollector_updatesCollector() public {
        vm.prank(owner);
        feeManager.setFeeCollector(user);

        assertEq(feeManager.feeCollector(), user);
    }

    function test_setFeeToken_updatesToken() public {
        vm.startPrank(owner);
        MockGovernanceToken newFeeToken = new MockGovernanceToken();
        feeManager.setFeeToken(address(newFeeToken));
        vm.stopPrank();

        assertEq(address(feeManager.feeToken()), address(newFeeToken));
    }
}
