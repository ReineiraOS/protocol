// SPDX-License-Identifier: FSL-1.1-ALv2
pragma solidity ^0.8.25;

import {FHETestBase} from "@reineira-os/shared/test/FHETestBase.sol";
import {IPoolFactoryEvents} from "@reineira-os/shared/contracts/interfaces/core/IPoolFactoryEvents.sol";
import {PoolFactoryLib} from "@reineira-os/shared/contracts/libraries/PoolFactoryLib.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {IFHERC20} from "fhenix-confidential-contracts/contracts/interfaces/IFHERC20.sol";
import {ConfidentialPolicyRegistry} from "../../contracts/core/ConfidentialPolicyRegistry.sol";
import {ConfidentialPoolFactory} from "../../contracts/core/ConfidentialPoolFactory.sol";
import {ConfidentialRecoursePool} from "../../contracts/core/ConfidentialRecoursePool.sol";
import {ConfidentialCoverageManager} from "../../contracts/core/ConfidentialCoverageManager.sol";
import {MockConfidentialToken} from "../../contracts/mocks/MockConfidentialToken.sol";

contract ConfidentialPoolFactoryTest is FHETestBase {
    ConfidentialPoolFactory public factory;
    MockConfidentialToken public token;
    ConfidentialCoverageManager public coverageManager;

    address public owner;
    address public creator1;
    address public creator2;
    address public managerAddr;
    address public guardianAddr;
    address public user1;

    function setUp() public {
        _initFHE();
        owner = makeAddr("owner");
        creator1 = makeAddr("creator1");
        creator2 = makeAddr("creator2");
        managerAddr = makeAddr("managerAddr");
        guardianAddr = makeAddr("guardianAddr");
        user1 = makeAddr("user1");

        vm.startPrank(owner);

        token = new MockConfidentialToken();

        ConfidentialPolicyRegistry policyRegistryImpl = new ConfidentialPolicyRegistry(address(0));
        ConfidentialPolicyRegistry policyRegistry = ConfidentialPolicyRegistry(
            address(
                new ERC1967Proxy(
                    address(policyRegistryImpl),
                    abi.encodeCall(ConfidentialPolicyRegistry.initialize, (owner))
                )
            )
        );

        ConfidentialRecoursePool poolImpl = new ConfidentialRecoursePool(address(0));

        ConfidentialCoverageManager coverageManagerImpl = new ConfidentialCoverageManager(address(0));
        coverageManager = ConfidentialCoverageManager(
            address(
                new ERC1967Proxy(
                    address(coverageManagerImpl),
                    abi.encodeCall(ConfidentialCoverageManager.initialize, (owner, owner))
                )
            )
        );

        ConfidentialPoolFactory factoryImpl = new ConfidentialPoolFactory(address(0));
        factory = ConfidentialPoolFactory(
            address(
                new ERC1967Proxy(
                    address(factoryImpl),
                    abi.encodeCall(
                        ConfidentialPoolFactory.initialize,
                        (owner, address(poolImpl), address(coverageManager), address(policyRegistry))
                    )
                )
            )
        );

        coverageManager.setPoolFactory(address(factory));
        factory.addAllowedToken(address(token));

        vm.stopPrank();
    }

    function test_deployment_setsCorrectOwner() public view {
        assertEq(factory.owner(), owner);
    }

    function test_deployment_startsWithZeroPools() public view {
        assertEq(factory.poolCount(), 0);
    }

    function test_createPool_createsPoolAndReturnsPoolIdAndAddress() public {
        vm.prank(creator1);
        factory.createPool(IFHERC20(address(token)), address(0), address(0), true);

        assertEq(factory.poolCount(), 1);

        address poolAddr = factory.pool(0);
        assertTrue(poolAddr != address(0));
        assertTrue(factory.isPool(poolAddr));
    }

    function test_createPool_setsCorrectCreator() public {
        vm.prank(creator1);
        factory.createPool(IFHERC20(address(token)), address(0), address(0), true);

        ConfidentialRecoursePool pool = ConfidentialRecoursePool(factory.pool(0));
        assertEq(pool.creator(), creator1);
    }

    function test_createPool_managerDefaultsToCreator() public {
        vm.prank(creator1);
        factory.createPool(IFHERC20(address(token)), address(0), address(0), true);

        ConfidentialRecoursePool pool = ConfidentialRecoursePool(factory.pool(0));
        assertEq(pool.manager(), creator1);
    }

    function test_createPool_acceptsExplicitManager() public {
        vm.prank(creator1);
        factory.createPool(IFHERC20(address(token)), managerAddr, address(0), true);

        ConfidentialRecoursePool pool = ConfidentialRecoursePool(factory.pool(0));
        assertEq(pool.manager(), managerAddr);
    }

    function test_createPool_acceptsGuardian() public {
        vm.prank(creator1);
        factory.createPool(IFHERC20(address(token)), address(0), guardianAddr, true);

        ConfidentialRecoursePool pool = ConfidentialRecoursePool(factory.pool(0));
        assertEq(pool.guardian(), guardianAddr);
    }

    function test_createPool_acceptsClosedPool() public {
        vm.prank(creator1);
        factory.createPool(IFHERC20(address(token)), managerAddr, guardianAddr, false);

        ConfidentialRecoursePool pool = ConfidentialRecoursePool(factory.pool(0));
        assertFalse(pool.isOpen());
    }

    function test_createPool_acceptsOpenPool() public {
        vm.prank(creator1);
        factory.createPool(IFHERC20(address(token)), address(0), address(0), true);

        ConfidentialRecoursePool pool = ConfidentialRecoursePool(factory.pool(0));
        assertTrue(pool.isOpen());
    }

    function test_createPool_setsCorrectPaymentToken() public {
        vm.prank(creator1);
        factory.createPool(IFHERC20(address(token)), address(0), address(0), true);

        ConfidentialRecoursePool pool = ConfidentialRecoursePool(factory.pool(0));
        assertEq(address(pool.paymentToken()), address(token));
    }

    function test_createPool_allowsMultipleCreatorsToCreatePools() public {
        vm.prank(creator1);
        factory.createPool(IFHERC20(address(token)), address(0), address(0), true);
        vm.prank(creator2);
        factory.createPool(IFHERC20(address(token)), address(0), address(0), true);

        assertEq(factory.poolCount(), 2);

        address pool1Addr = factory.pool(0);
        address pool2Addr = factory.pool(1);
        assertTrue(pool1Addr != pool2Addr);

        assertEq(ConfidentialRecoursePool(pool1Addr).creator(), creator1);
        assertEq(ConfidentialRecoursePool(pool2Addr).creator(), creator2);
    }

    function test_createPool_revertsWithZeroAddressPaymentToken() public {
        vm.prank(creator1);
        vm.expectRevert();
        factory.createPool(IFHERC20(address(0)), address(0), address(0), true);
    }

    function test_createPool_emitsPoolCreatedEvent() public {
        vm.prank(creator1);
        vm.expectEmit(true, false, true, true);
        emit IPoolFactoryEvents.PoolCreated(0, address(0), creator1, managerAddr, guardianAddr, false);
        factory.createPool(IFHERC20(address(token)), managerAddr, guardianAddr, false);
    }

    function test_createPool_emitsPoolCreatedEventWithDefaults() public {
        vm.prank(creator1);
        vm.expectEmit(true, false, true, true);
        emit IPoolFactoryEvents.PoolCreated(0, address(0), creator1, creator1, address(0), true);
        factory.createPool(IFHERC20(address(token)), address(0), address(0), true);
    }

    function test_getters_revertsPoolForNonexistentId() public {
        vm.expectRevert(PoolFactoryLib.PoolDoesNotExist.selector);
        factory.pool(0);

        vm.expectRevert(PoolFactoryLib.PoolDoesNotExist.selector);
        factory.pool(999);
    }

    function test_getters_returnsFalseForNonPoolAddress() public view {
        assertFalse(factory.isPool(user1));
    }

    function test_addAllowedToken_addsToken() public {
        MockConfidentialToken token2 = new MockConfidentialToken();

        vm.prank(owner);
        factory.addAllowedToken(address(token2));

        assertTrue(factory.isAllowedToken(address(token2)));
    }

    function test_addAllowedToken_revertsWhenCalledByNonOwner() public {
        vm.prank(user1);
        vm.expectRevert();
        factory.addAllowedToken(address(token));
    }

    function test_addAllowedToken_revertsOnZeroAddress() public {
        vm.prank(owner);
        vm.expectRevert();
        factory.addAllowedToken(address(0));
    }

    function test_removeAllowedToken_removesToken() public {
        vm.prank(owner);
        factory.removeAllowedToken(address(token));

        assertFalse(factory.isAllowedToken(address(token)));
    }

    function test_removeAllowedToken_revertsWhenCalledByNonOwner() public {
        vm.prank(user1);
        vm.expectRevert();
        factory.removeAllowedToken(address(token));
    }

    function test_createPool_revertsWithDisallowedToken() public {
        MockConfidentialToken badToken = new MockConfidentialToken();

        vm.prank(creator1);
        vm.expectRevert(PoolFactoryLib.TokenNotAllowed.selector);
        factory.createPool(IFHERC20(address(badToken)), address(0), address(0), true);
    }

    function test_createPool_revertsAfterTokenRemoved() public {
        vm.prank(owner);
        factory.removeAllowedToken(address(token));

        vm.prank(creator1);
        vm.expectRevert(PoolFactoryLib.TokenNotAllowed.selector);
        factory.createPool(IFHERC20(address(token)), address(0), address(0), true);
    }

    function test_addAllowedToken_emitsTokenAllowedEvent() public {
        MockConfidentialToken token2 = new MockConfidentialToken();

        vm.prank(owner);
        vm.expectEmit(true, false, false, false);
        emit IPoolFactoryEvents.TokenAllowed(address(token2));
        factory.addAllowedToken(address(token2));
    }

    function test_removeAllowedToken_emitsTokenRemovedEvent() public {
        vm.prank(owner);
        vm.expectEmit(true, false, false, false);
        emit IPoolFactoryEvents.TokenRemoved(address(token));
        factory.removeAllowedToken(address(token));
    }
}
