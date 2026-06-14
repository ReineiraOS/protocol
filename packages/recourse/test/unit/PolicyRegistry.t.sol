// SPDX-License-Identifier: FSL-1.1-ALv2
pragma solidity ^0.8.25;

import {Test} from "forge-std/Test.sol";
import {IPolicyRegistryEvents} from "@reineira-os/shared/contracts/interfaces/core/IPolicyRegistryEvents.sol";
import {PolicyRegistryLib} from "@reineira-os/shared/contracts/libraries/PolicyRegistryLib.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {PolicyRegistry} from "../../contracts/core/PolicyRegistry.sol";
import {MockUnderwriterPolicy} from "../../contracts/mocks/MockUnderwriterPolicy.sol";
import {MockUSDC} from "@reineira-os/shared/contracts/mocks/MockUSDC.sol";

contract PolicyRegistryTest is Test {
    PolicyRegistry public registry;
    MockUnderwriterPolicy public mockPolicy;
    MockUnderwriterPolicy public mockPolicy2;

    address public owner;
    address public user1;
    address public user2;

    function setUp() public {
        owner = makeAddr("owner");
        user1 = makeAddr("user1");
        user2 = makeAddr("user2");

        vm.startPrank(owner);
        PolicyRegistry impl = new PolicyRegistry(address(0));
        registry = PolicyRegistry(
            address(new ERC1967Proxy(address(impl), abi.encodeCall(PolicyRegistry.initialize, (owner))))
        );
        vm.stopPrank();

        mockPolicy = new MockUnderwriterPolicy();
        mockPolicy2 = new MockUnderwriterPolicy();
    }

    function test_deployment_setsCorrectOwner() public view {
        assertEq(registry.owner(), owner);
    }

    function test_deployment_startsWithZeroPolicies() public view {
        assertEq(registry.policyCount(), 0);
    }

    function test_registerPolicy_registersValidPolicy() public {
        vm.prank(owner);
        registry.registerPolicy(address(mockPolicy));

        assertEq(registry.policyCount(), 1);
        assertEq(registry.policy(0), address(mockPolicy));
        assertTrue(registry.isPolicy(address(mockPolicy)));
    }

    function test_registerPolicy_assignsSequentialIds() public {
        vm.prank(owner);
        registry.registerPolicy(address(mockPolicy));
        vm.prank(owner);
        registry.registerPolicy(address(mockPolicy2));

        assertEq(registry.policyCount(), 2);
        assertEq(registry.policy(0), address(mockPolicy));
        assertEq(registry.policy(1), address(mockPolicy2));
    }

    function test_registerPolicy_emitsPolicyRegisteredEvent() public {
        vm.prank(owner);
        vm.expectEmit(true, true, true, false);
        emit IPolicyRegistryEvents.PolicyRegistered(0, address(mockPolicy), owner);
        registry.registerPolicy(address(mockPolicy));
    }

    function test_registerPolicy_revertsOnZeroAddress() public {
        vm.prank(owner);
        vm.expectRevert();
        registry.registerPolicy(address(0));
    }

    function test_registerPolicy_revertsOnDuplicateRegistration() public {
        vm.prank(owner);
        registry.registerPolicy(address(mockPolicy));

        vm.prank(owner);
        vm.expectRevert(PolicyRegistryLib.PolicyAlreadyRegistered.selector);
        registry.registerPolicy(address(mockPolicy));
    }

    function test_registerPolicy_revertsOnContractWithoutIUnderwriterPolicyInterface() public {
        MockUSDC token = new MockUSDC();

        vm.prank(owner);
        vm.expectRevert(PolicyRegistryLib.InvalidPolicyInterface.selector);
        registry.registerPolicy(address(token));
    }

    function test_registerPolicy_revertsWhenCalledByNonOwner() public {
        vm.prank(user1);
        vm.expectRevert();
        registry.registerPolicy(address(mockPolicy));
    }

    function test_getters_revertsPolicyForNonexistentId() public {
        vm.expectRevert(PolicyRegistryLib.PolicyDoesNotExist.selector);
        registry.policy(0);

        vm.expectRevert(PolicyRegistryLib.PolicyDoesNotExist.selector);
        registry.policy(999);
    }

    function test_getters_returnsFalseForUnregisteredAddress() public view {
        assertFalse(registry.isPolicy(user1));
    }
}
