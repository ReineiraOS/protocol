// SPDX-License-Identifier: FSL-1.1-ALv2
pragma solidity ^0.8.25;

import {FHETestBase} from "@reineira-os/shared/test/FHETestBase.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {ConfidentialEscrow} from "../../contracts/core/ConfidentialEscrow.sol";
import {MockConfidentialToken} from "../../contracts/mocks/MockConfidentialToken.sol";
import {MockConditionResolver} from "../../contracts/mocks/MockConditionResolver.sol";
import {IEscrowEvents} from "@reineira-os/shared/contracts/interfaces/core/IEscrowEvents.sol";

contract ConfidentialEscrowTest is FHETestBase {
    ConfidentialEscrow public escrow;
    MockConfidentialToken public token;

    address public owner;
    address public user1;
    address public user2;

    function setUp() public {
        _initFHE();
        owner = makeAddr("owner");
        user1 = makeAddr("user1");
        user2 = makeAddr("user2");

        vm.startPrank(owner);
        token = new MockConfidentialToken();
        ConfidentialEscrow impl = new ConfidentialEscrow(address(0));
        escrow = ConfidentialEscrow(
            address(
                new ERC1967Proxy(address(impl), abi.encodeCall(ConfidentialEscrow.initialize, (owner, address(token))))
            )
        );
        vm.stopPrank();
    }

    function test_deployment_setsCorrectPaymentToken() public view {
        assertEq(address(escrow.paymentToken()), address(token));
    }

    function test_deployment_startsWithZeroEscrows() public view {
        assertEq(escrow.total(), 0);
    }

    function test_deployment_revertsOnZeroAddressPaymentToken() public {
        ConfidentialEscrow impl = new ConfidentialEscrow(address(0));
        vm.expectRevert();
        new ERC1967Proxy(address(impl), abi.encodeCall(ConfidentialEscrow.initialize, (owner, address(0))));
    }

    function test_existence_returnsFalseForNonExistent() public view {
        assertFalse(escrow.exists(0));
        assertFalse(escrow.exists(999));
    }

    function test_view_revertsGetOwnerForNonExistent() public {
        vm.expectRevert();
        escrow.getOwner(0);
    }

    function test_view_revertsGetAmountForNonExistent() public {
        vm.expectRevert();
        escrow.getAmount(0);
    }

    function test_view_revertsGetPaidAmountForNonExistent() public {
        vm.expectRevert();
        escrow.getPaidAmount(0);
    }

    function test_view_revertsGetRedeemedStatusForNonExistent() public {
        vm.expectRevert();
        escrow.getRedeemedStatus(0);
    }

    function test_view_revertsGetCallerForNonExistent() public {
        vm.expectRevert();
        escrow.getCaller(0);
    }

    function test_error_revertsRedeemMultipleForEmptyArray() public {
        uint256[] memory empty = new uint256[](0);
        vm.prank(user1);
        vm.expectRevert();
        escrow.redeemMultiple(empty);
    }

    function test_condition_returnsZeroAddressForNoCondition() public view {
        assertEq(escrow.getConditionResolver(0), address(0));
    }

    function test_condition_deploysMockConditionResolver() public {
        MockConditionResolver resolver = new MockConditionResolver();
        assertTrue(address(resolver) != address(0));
    }

    function test_condition_allowsSettingCondition() public {
        MockConditionResolver resolver = new MockConditionResolver();
        resolver.setCondition(0, true);
        assertTrue(resolver.isConditionMet(0));
    }

    function test_condition_returnsFalseByDefault() public {
        MockConditionResolver resolver = new MockConditionResolver();
        assertFalse(resolver.isConditionMet(0));
    }

    function test_coverageManager_setsAsOwner() public {
        vm.prank(owner);
        escrow.setCoverageManager(user1);
    }

    function test_coverageManager_emitsEvent() public {
        vm.prank(owner);
        vm.expectEmit(true, false, false, false);
        emit IEscrowEvents.CoverageManagerSet(user1);
        escrow.setCoverageManager(user1);
    }

    function test_coverageManager_revertsForNonOwner() public {
        vm.prank(user1);
        vm.expectRevert();
        escrow.setCoverageManager(user2);
    }

    function test_coverageManager_revertsForZeroAddress() public {
        vm.prank(owner);
        vm.expectRevert();
        escrow.setCoverageManager(address(0));
    }
}
