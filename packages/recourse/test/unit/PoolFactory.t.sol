// SPDX-License-Identifier: FSL-1.1-ALv2
pragma solidity ^0.8.25;

import {Test} from "forge-std/Test.sol";
import {IPoolFactoryEvents} from "@reineira-os/shared/contracts/interfaces/core/IPoolFactoryEvents.sol";
import {PoolFactoryLib} from "@reineira-os/shared/contracts/libraries/PoolFactoryLib.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {PolicyRegistry} from "../../contracts/core/PolicyRegistry.sol";
import {PoolFactory} from "../../contracts/core/PoolFactory.sol";
import {RecoursePool} from "../../contracts/core/RecoursePool.sol";
import {CoverageManager} from "../../contracts/core/CoverageManager.sol";
import {MockUSDC} from "@reineira-os/shared/contracts/mocks/MockUSDC.sol";

contract PoolFactoryTest is Test {
    PoolFactory public factory;
    MockUSDC public usdc;
    CoverageManager public coverageManager;

    address public owner;
    address public creator1;
    address public creator2;
    address public managerAddr;
    address public guardianAddr;
    address public user1;

    function setUp() public {
        owner = makeAddr("owner");
        creator1 = makeAddr("creator1");
        creator2 = makeAddr("creator2");
        managerAddr = makeAddr("managerAddr");
        guardianAddr = makeAddr("guardianAddr");
        user1 = makeAddr("user1");

        vm.startPrank(owner);

        usdc = new MockUSDC();

        PolicyRegistry policyRegistryImpl = new PolicyRegistry(address(0));
        PolicyRegistry policyRegistry = PolicyRegistry(
            address(new ERC1967Proxy(address(policyRegistryImpl), abi.encodeCall(PolicyRegistry.initialize, (owner))))
        );

        RecoursePool poolImpl = new RecoursePool(address(0));

        CoverageManager coverageManagerImpl = new CoverageManager(address(0));
        coverageManager = CoverageManager(
            address(
                new ERC1967Proxy(
                    address(coverageManagerImpl),
                    abi.encodeCall(CoverageManager.initialize, (owner, owner))
                )
            )
        );

        PoolFactory factoryImpl = new PoolFactory(address(0));
        factory = PoolFactory(
            address(
                new ERC1967Proxy(
                    address(factoryImpl),
                    abi.encodeCall(
                        PoolFactory.initialize,
                        (owner, address(poolImpl), address(coverageManager), address(policyRegistry))
                    )
                )
            )
        );

        coverageManager.setPoolFactory(address(factory));
        factory.addAllowedToken(address(usdc));

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
        factory.createPool(address(usdc), address(0), address(0), true);

        assertEq(factory.poolCount(), 1);

        address poolAddr = factory.pool(0);
        assertTrue(poolAddr != address(0));
        assertTrue(factory.isPool(poolAddr));
    }

    function test_createPool_setsCorrectCreator() public {
        vm.prank(creator1);
        factory.createPool(address(usdc), address(0), address(0), true);

        address poolAddr = factory.pool(0);
        RecoursePool pool = RecoursePool(poolAddr);

        assertEq(pool.creator(), creator1);
    }

    function test_createPool_managerDefaultsToCreator() public {
        vm.prank(creator1);
        factory.createPool(address(usdc), address(0), address(0), true);

        RecoursePool pool = RecoursePool(factory.pool(0));
        assertEq(pool.manager(), creator1);
    }

    function test_createPool_acceptsExplicitManager() public {
        vm.prank(creator1);
        factory.createPool(address(usdc), managerAddr, address(0), true);

        RecoursePool pool = RecoursePool(factory.pool(0));
        assertEq(pool.creator(), creator1);
        assertEq(pool.manager(), managerAddr);
    }

    function test_createPool_acceptsGuardian() public {
        vm.prank(creator1);
        factory.createPool(address(usdc), address(0), guardianAddr, true);

        RecoursePool pool = RecoursePool(factory.pool(0));
        assertEq(pool.guardian(), guardianAddr);
    }

    function test_createPool_guardianZeroAddressAllowed() public {
        vm.prank(creator1);
        factory.createPool(address(usdc), address(0), address(0), true);

        RecoursePool pool = RecoursePool(factory.pool(0));
        assertEq(pool.guardian(), address(0));
    }

    function test_createPool_acceptsClosedPool() public {
        vm.prank(creator1);
        factory.createPool(address(usdc), managerAddr, guardianAddr, false);

        RecoursePool pool = RecoursePool(factory.pool(0));
        assertFalse(pool.isOpen());
    }

    function test_createPool_acceptsOpenPool() public {
        vm.prank(creator1);
        factory.createPool(address(usdc), address(0), address(0), true);

        RecoursePool pool = RecoursePool(factory.pool(0));
        assertTrue(pool.isOpen());
    }

    function test_createPool_setsCorrectPaymentToken() public {
        vm.prank(creator1);
        factory.createPool(address(usdc), address(0), address(0), true);

        RecoursePool pool = RecoursePool(factory.pool(0));
        assertEq(address(pool.paymentToken()), address(usdc));
    }

    function test_createPool_allowsMultipleCreatorsToCreatePools() public {
        vm.prank(creator1);
        factory.createPool(address(usdc), address(0), address(0), true);
        vm.prank(creator2);
        factory.createPool(address(usdc), address(0), address(0), true);

        assertEq(factory.poolCount(), 2);

        address pool1Addr = factory.pool(0);
        address pool2Addr = factory.pool(1);
        assertTrue(pool1Addr != pool2Addr);

        assertEq(RecoursePool(pool1Addr).creator(), creator1);
        assertEq(RecoursePool(pool2Addr).creator(), creator2);
    }

    function test_createPool_revertsWithZeroAddressPaymentToken() public {
        vm.prank(creator1);
        vm.expectRevert();
        factory.createPool(address(0), address(0), address(0), true);
    }

    function test_createPool_emitsPoolCreatedEvent() public {
        vm.prank(creator1);
        vm.expectEmit(true, false, true, true);
        emit IPoolFactoryEvents.PoolCreated(0, address(0), creator1, managerAddr, guardianAddr, false);
        factory.createPool(address(usdc), managerAddr, guardianAddr, false);
    }

    function test_createPool_emitsPoolCreatedEventWithDefaults() public {
        vm.prank(creator1);
        vm.expectEmit(true, false, true, true);
        emit IPoolFactoryEvents.PoolCreated(0, address(0), creator1, creator1, address(0), true);
        factory.createPool(address(usdc), address(0), address(0), true);
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
        MockUSDC usdc2 = new MockUSDC();

        vm.prank(owner);
        factory.addAllowedToken(address(usdc2));

        assertTrue(factory.isAllowedToken(address(usdc2)));
    }

    function test_addAllowedToken_revertsWhenCalledByNonOwner() public {
        vm.prank(user1);
        vm.expectRevert();
        factory.addAllowedToken(address(usdc));
    }

    function test_addAllowedToken_revertsOnZeroAddress() public {
        vm.prank(owner);
        vm.expectRevert();
        factory.addAllowedToken(address(0));
    }

    function test_addAllowedToken_emitsTokenAllowedEvent() public {
        MockUSDC usdc2 = new MockUSDC();

        vm.prank(owner);
        vm.expectEmit(true, false, false, false);
        emit IPoolFactoryEvents.TokenAllowed(address(usdc2));
        factory.addAllowedToken(address(usdc2));
    }

    function test_removeAllowedToken_removesToken() public {
        vm.prank(owner);
        factory.removeAllowedToken(address(usdc));

        assertFalse(factory.isAllowedToken(address(usdc)));
    }

    function test_removeAllowedToken_revertsWhenCalledByNonOwner() public {
        vm.prank(user1);
        vm.expectRevert();
        factory.removeAllowedToken(address(usdc));
    }

    function test_removeAllowedToken_emitsTokenRemovedEvent() public {
        vm.prank(owner);
        vm.expectEmit(true, false, false, false);
        emit IPoolFactoryEvents.TokenRemoved(address(usdc));
        factory.removeAllowedToken(address(usdc));
    }

    function test_isAllowedToken_returnsState() public {
        assertTrue(factory.isAllowedToken(address(usdc)));

        MockUSDC other = new MockUSDC();
        assertFalse(factory.isAllowedToken(address(other)));
    }

    function test_createPool_revertsWithDisallowedToken() public {
        MockUSDC badToken = new MockUSDC();

        vm.prank(creator1);
        vm.expectRevert(PoolFactoryLib.TokenNotAllowed.selector);
        factory.createPool(address(badToken), address(0), address(0), true);
    }

    function test_createPool_revertsAfterTokenRemoved() public {
        vm.prank(owner);
        factory.removeAllowedToken(address(usdc));

        vm.prank(creator1);
        vm.expectRevert(PoolFactoryLib.TokenNotAllowed.selector);
        factory.createPool(address(usdc), address(0), address(0), true);
    }
}
