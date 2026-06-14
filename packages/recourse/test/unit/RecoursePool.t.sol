// SPDX-License-Identifier: FSL-1.1-ALv2
pragma solidity ^0.8.25;

import {Test} from "forge-std/Test.sol";
import {IRecoursePoolEvents} from "@reineira-os/shared/contracts/interfaces/core/IRecoursePoolEvents.sol";
import {RecoursePoolLib} from "@reineira-os/shared/contracts/libraries/RecoursePoolLib.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {PolicyRegistry} from "../../contracts/core/PolicyRegistry.sol";
import {PoolFactory} from "../../contracts/core/PoolFactory.sol";
import {RecoursePool} from "../../contracts/core/RecoursePool.sol";
import {CoverageManager} from "../../contracts/core/CoverageManager.sol";
import {ICore} from "@reineira-os/shared/contracts/interfaces/core/ICore.sol";
import {MockUnderwriterPolicy} from "../../contracts/mocks/MockUnderwriterPolicy.sol";
import {MockUSDC} from "@reineira-os/shared/contracts/mocks/MockUSDC.sol";

contract RecoursePoolTest is Test {
    PoolFactory public poolFactory;
    PolicyRegistry public policyRegistry;
    CoverageManager public coverageManager;
    MockUSDC public usdc;
    MockUnderwriterPolicy public mockPolicy;
    RecoursePool public pool;

    address public owner;
    address public creator;
    address public manager;
    address public guardian;
    address public lp1;
    address public lp2;
    address public poolAddress;
    address public mockPolicyAddress;

    uint256 constant STAKE_AMOUNT = 10_000e6;

    function setUp() public {
        owner = makeAddr("owner");
        creator = makeAddr("creator");
        manager = makeAddr("manager");
        guardian = makeAddr("guardian");
        lp1 = makeAddr("lp1");
        lp2 = makeAddr("lp2");

        vm.startPrank(owner);

        usdc = new MockUSDC();
        mockPolicy = new MockUnderwriterPolicy();
        mockPolicyAddress = address(mockPolicy);

        PolicyRegistry policyRegistryImpl = new PolicyRegistry(address(0));
        policyRegistry = PolicyRegistry(
            address(new ERC1967Proxy(address(policyRegistryImpl), abi.encodeCall(PolicyRegistry.initialize, (owner))))
        );
        policyRegistry.registerPolicy(mockPolicyAddress);

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
        poolFactory = PoolFactory(
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

        coverageManager.setPoolFactory(address(poolFactory));
        poolFactory.addAllowedToken(address(usdc));

        vm.stopPrank();

        vm.prank(creator);
        poolFactory.createPool(address(usdc), address(0), address(0), true);
        poolAddress = poolFactory.pool(0);
        pool = RecoursePool(poolAddress);

        vm.prank(creator);
        pool.addPolicy(mockPolicyAddress);
    }

    function _stakeAs(address staker, uint256 amount) internal {
        usdc.mint(staker, amount);
        vm.prank(staker);
        usdc.approve(poolAddress, amount);
        vm.prank(staker);
        pool.stake(amount);
    }

    function _splitManager() internal {
        vm.prank(creator);
        pool.transferManager(manager);
    }

    function test_policyManagement_addsPolicyAsCreator() public view {
        assertTrue(pool.isPolicy(mockPolicyAddress));
    }

    function test_policyManagement_revertsAddPolicyIfNotCreator() public {
        MockUnderwriterPolicy newPolicy = new MockUnderwriterPolicy();
        vm.prank(owner);
        policyRegistry.registerPolicy(address(newPolicy));

        vm.prank(lp1);
        vm.expectRevert(RecoursePoolLib.NotCreator.selector);
        pool.addPolicy(address(newPolicy));
    }

    function test_policyManagement_revertsAddPolicyForManagerAfterTransfer() public {
        _splitManager();

        MockUnderwriterPolicy newPolicy = new MockUnderwriterPolicy();
        vm.prank(owner);
        policyRegistry.registerPolicy(address(newPolicy));

        vm.prank(manager);
        vm.expectRevert(RecoursePoolLib.NotCreator.selector);
        pool.addPolicy(address(newPolicy));
    }

    function test_policyManagement_revertsAddPolicyForUnregisteredPolicy() public {
        MockUnderwriterPolicy unregisteredPolicy = new MockUnderwriterPolicy();

        vm.prank(creator);
        vm.expectRevert(RecoursePoolLib.InvalidPolicy.selector);
        pool.addPolicy(address(unregisteredPolicy));
    }

    function test_policyManagement_removesPolicyAsCreator() public {
        vm.prank(creator);
        pool.removePolicy(mockPolicyAddress);
        assertFalse(pool.isPolicy(mockPolicyAddress));
    }

    function test_policyManagement_emitsPolicyAddedEvent() public {
        MockUnderwriterPolicy newPolicy = new MockUnderwriterPolicy();
        vm.prank(owner);
        policyRegistry.registerPolicy(address(newPolicy));

        vm.prank(creator);
        (, address newPoolAddr) = poolFactory.createPool(address(usdc), address(0), address(0), true);
        RecoursePool newPool = RecoursePool(newPoolAddr);

        vm.prank(creator);
        vm.expectEmit(true, false, false, false);
        emit IRecoursePoolEvents.PolicyAdded(address(newPolicy));
        newPool.addPolicy(address(newPolicy));
    }

    function test_staking_acceptsStake() public {
        usdc.mint(lp1, STAKE_AMOUNT);
        vm.prank(lp1);
        usdc.approve(poolAddress, STAKE_AMOUNT);

        vm.prank(lp1);
        vm.expectEmit(true, false, false, false);
        emit IRecoursePoolEvents.Staked(0);
        pool.stake(STAKE_AMOUNT);

        assertEq(pool.stakedAmount(0), STAKE_AMOUNT);
        assertEq(pool.totalLiquidity(), STAKE_AMOUNT);
    }

    function test_staking_incrementsStakeId() public {
        usdc.mint(lp1, STAKE_AMOUNT);
        usdc.mint(lp2, STAKE_AMOUNT);

        vm.prank(lp1);
        usdc.approve(poolAddress, STAKE_AMOUNT);
        vm.prank(lp1);
        pool.stake(STAKE_AMOUNT);

        vm.prank(lp2);
        usdc.approve(poolAddress, STAKE_AMOUNT);

        vm.prank(lp2);
        vm.expectEmit(true, false, false, false);
        emit IRecoursePoolEvents.Staked(1);
        pool.stake(STAKE_AMOUNT);
    }

    function test_staking_emitsStakedEvent() public {
        usdc.mint(lp1, STAKE_AMOUNT);
        vm.prank(lp1);
        usdc.approve(poolAddress, STAKE_AMOUNT);

        vm.prank(lp1);
        vm.expectEmit(true, false, false, false);
        emit IRecoursePoolEvents.Staked(0);
        pool.stake(STAKE_AMOUNT);
    }

    function test_unstaking_allowsStakeOwnerToUnstake() public {
        _stakeAs(lp1, STAKE_AMOUNT);

        vm.prank(lp1);
        vm.expectEmit(true, false, false, false);
        emit IRecoursePoolEvents.Unstaked(0);
        pool.unstake(0);

        assertEq(usdc.balanceOf(lp1), STAKE_AMOUNT);
        assertEq(pool.totalLiquidity(), 0);
    }

    function test_unstaking_revertsIfNotStakeOwner() public {
        _stakeAs(lp1, STAKE_AMOUNT);

        vm.prank(lp2);
        vm.expectRevert(RecoursePoolLib.NotStakeOwner.selector);
        pool.unstake(0);
    }

    function test_unstaking_revertsForNonexistentStake() public {
        _stakeAs(lp1, STAKE_AMOUNT);

        vm.prank(lp1);
        vm.expectRevert(RecoursePoolLib.StakeDoesNotExist.selector);
        pool.unstake(999);
    }

    function test_accessControl_revertsPayClaimIfNotCoverageManager() public {
        _stakeAs(lp1, STAKE_AMOUNT);

        vm.prank(lp1);
        vm.expectRevert(RecoursePoolLib.NotCoverageManager.selector);
        pool.payClaim(0, 100);
    }

    function test_accessControl_revertsReceivePremiumIfNotCoverageManager() public {
        _stakeAs(lp1, STAKE_AMOUNT);

        vm.prank(lp1);
        vm.expectRevert(RecoursePoolLib.NotCoverageManager.selector);
        pool.receivePremium(0, 100);
    }

    function test_accessControl_revertsClaimPremiumsIfNotManager() public {
        _stakeAs(lp1, STAKE_AMOUNT);

        vm.prank(lp1);
        vm.expectRevert(RecoursePoolLib.NotManager.selector);
        pool.claimPremiums(100);
    }

    function test_accessControl_revertsClaimPremiumsForCreatorAfterTransfer() public {
        _splitManager();
        _stakeAs(lp1, STAKE_AMOUNT);

        vm.prank(creator);
        vm.expectRevert(RecoursePoolLib.NotManager.selector);
        pool.claimPremiums(100);
    }

    function test_claimRewards_emitsRewardsClaimedEvent() public {
        _stakeAs(lp1, STAKE_AMOUNT);

        vm.prank(lp1);
        vm.expectEmit(true, false, false, false);
        emit IRecoursePoolEvents.RewardsClaimed(0);
        pool.claimRewards(0);
    }

    function test_claimRewards_revertsIfNotStakeOwner() public {
        _stakeAs(lp1, STAKE_AMOUNT);

        vm.prank(lp2);
        vm.expectRevert(RecoursePoolLib.NotStakeOwner.selector);
        pool.claimRewards(0);
    }

    function test_viewFunctions_returnsStakedAmount() public {
        _stakeAs(lp1, STAKE_AMOUNT);
        assertEq(pool.stakedAmount(0), STAKE_AMOUNT);
    }

    function test_viewFunctions_returnsTotalLiquidity() public {
        _stakeAs(lp1, STAKE_AMOUNT);
        _stakeAs(lp2, STAKE_AMOUNT);
        assertEq(pool.totalLiquidity(), STAKE_AMOUNT * 2);
    }

    function test_viewFunctions_returnsPendingRewardsForExistingStake() public {
        _stakeAs(lp1, STAKE_AMOUNT);
        assertEq(pool.pendingRewards(0), 0);
    }

    function test_viewFunctions_revertsPendingRewardsForNonexistentStake() public {
        _stakeAs(lp1, STAKE_AMOUNT);

        vm.expectRevert(RecoursePoolLib.StakeDoesNotExist.selector);
        pool.pendingRewards(999);
    }

    function test_viewFunctions_revertsStakedAmountForNonexistentStake() public {
        _stakeAs(lp1, STAKE_AMOUNT);

        vm.expectRevert(RecoursePoolLib.StakeDoesNotExist.selector);
        pool.stakedAmount(999);
    }

    function test_claimPremiumsCap_doesNotUnderflowWhenClaimingMoreThanAvailable() public {
        _stakeAs(lp1, STAKE_AMOUNT);

        vm.prank(address(coverageManager));
        pool.receivePremium(0, 100);

        uint256 beforeBal = usdc.balanceOf(creator);
        vm.prank(creator);
        pool.claimPremiums(99_999e6);

        assertEq(usdc.balanceOf(creator) - beforeBal, 100, "claim must cap to available premiums, no underflow");
    }

    function test_viewFunctions_returnsPaymentToken() public view {
        assertEq(address(pool.paymentToken()), address(usdc));
    }

    function test_viewFunctions_returnsCreator() public view {
        assertEq(pool.creator(), creator);
    }

    function test_viewFunctions_returnsManagerDefaultsToCreator() public view {
        assertEq(pool.manager(), creator);
    }

    function test_viewFunctions_returnsGuardianDefaultsToZero() public view {
        assertEq(pool.guardian(), address(0));
    }

    function test_viewFunctions_returnsIsOpenForOpenPool() public view {
        assertTrue(pool.isOpen());
    }

    function test_viewFunctions_returnsNonZeroDomainSeparator() public view {
        bytes32 ds = pool.domainSeparator();
        assertTrue(ds != bytes32(0));
    }

    function test_viewFunctions_domainSeparatorIsPoolBound() public {
        bytes32 dsA = pool.domainSeparator();

        vm.prank(creator);
        (, address otherPoolAddr) = poolFactory.createPool(address(usdc), address(0), address(0), true);
        bytes32 dsB = RecoursePool(otherPoolAddr).domainSeparator();

        assertTrue(dsA != dsB);
    }

    function test_viewFunctions_returnsCoverageManager() public view {
        assertEq(pool.coverageManager(), address(coverageManager));
    }

    function test_createPool_acceptsExplicitManagerAndGuardian() public {
        vm.prank(creator);
        (, address customPoolAddr) = poolFactory.createPool(address(usdc), manager, guardian, false);
        RecoursePool customPool = RecoursePool(customPoolAddr);

        assertEq(customPool.creator(), creator);
        assertEq(customPool.manager(), manager);
        assertEq(customPool.guardian(), guardian);
        assertFalse(customPool.isOpen());
    }

    function test_transferManager_changesManager() public {
        vm.prank(creator);
        vm.expectEmit(true, true, false, false);
        emit IRecoursePoolEvents.ManagerTransferred(creator, manager);
        pool.transferManager(manager);

        assertEq(pool.manager(), manager);
    }

    function test_transferManager_revertsForNonManager() public {
        vm.prank(lp1);
        vm.expectRevert(RecoursePoolLib.NotManager.selector);
        pool.transferManager(manager);
    }

    function test_transferManager_revertsOnZeroAddress() public {
        vm.prank(creator);
        vm.expectRevert(ICore.ZeroAddress.selector);
        pool.transferManager(address(0));
    }

    function test_transferManager_revertsOnSameAddress() public {
        vm.prank(creator);
        vm.expectRevert(RecoursePoolLib.SameAddress.selector);
        pool.transferManager(creator);
    }

    function test_transferManager_preservesCreator() public {
        _splitManager();
        assertEq(pool.creator(), creator);
        assertEq(pool.manager(), manager);
    }
}
