// SPDX-License-Identifier: FSL-1.1-ALv2
pragma solidity ^0.8.25;

import {FHETestBase} from "@reineira-os/shared/test/FHETestBase.sol";
import {IRecoursePoolEvents} from "@reineira-os/shared/contracts/interfaces/core/IRecoursePoolEvents.sol";
import {RecoursePoolLib} from "@reineira-os/shared/contracts/libraries/RecoursePoolLib.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {IFHERC20} from "fhenix-confidential-contracts/contracts/interfaces/IFHERC20.sol";
import {euint64, InEuint64} from "@fhenixprotocol/cofhe-contracts/FHE.sol";
import {ConfidentialPolicyRegistry} from "../../contracts/core/ConfidentialPolicyRegistry.sol";
import {ConfidentialPoolFactory} from "../../contracts/core/ConfidentialPoolFactory.sol";
import {ConfidentialRecoursePool} from "../../contracts/core/ConfidentialRecoursePool.sol";
import {ConfidentialCoverageManager} from "../../contracts/core/ConfidentialCoverageManager.sol";
import {ICore} from "@reineira-os/shared/contracts/interfaces/core/ICore.sol";
import {MockConfidentialToken} from "../../contracts/mocks/MockConfidentialToken.sol";
import {MockConfidentialUnderwriterPolicy} from "../../contracts/mocks/MockConfidentialUnderwriterPolicy.sol";

contract ConfidentialRecoursePoolTest is FHETestBase {
    ConfidentialPoolFactory public poolFactory;
    ConfidentialPolicyRegistry public policyRegistry;
    ConfidentialCoverageManager public coverageManager;
    MockConfidentialToken public token;
    MockConfidentialUnderwriterPolicy public mockPolicy;
    ConfidentialRecoursePool public pool;

    address public owner;
    address public creator;
    address public managerAddr;
    address public guardianAddr;
    address public lp1;
    address public lp2;
    address public poolAddress;
    address public mockPolicyAddress;

    uint64 constant STAKE_AMOUNT = 10000;

    function setUp() public {
        _initFHE();
        owner = makeAddr("owner");
        creator = _makeAccount("creator");
        managerAddr = _makeAccount("manager");
        guardianAddr = makeAddr("guardian");
        lp1 = _makeAccount("lp1");
        lp2 = _makeAccount("lp2");

        vm.startPrank(owner);

        token = new MockConfidentialToken();
        mockPolicy = new MockConfidentialUnderwriterPolicy();
        mockPolicyAddress = address(mockPolicy);

        ConfidentialPolicyRegistry policyRegistryImpl = new ConfidentialPolicyRegistry(address(0));
        policyRegistry = ConfidentialPolicyRegistry(
            address(
                new ERC1967Proxy(
                    address(policyRegistryImpl),
                    abi.encodeCall(ConfidentialPolicyRegistry.initialize, (owner))
                )
            )
        );
        policyRegistry.registerPolicy(mockPolicyAddress);

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
        poolFactory = ConfidentialPoolFactory(
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

        coverageManager.setPoolFactory(address(poolFactory));
        poolFactory.addAllowedToken(address(token));

        vm.stopPrank();

        vm.prank(creator);
        poolFactory.createPool(IFHERC20(address(token)), address(0), address(0), true);
        poolAddress = poolFactory.pool(0);
        pool = ConfidentialRecoursePool(poolAddress);

        vm.prank(creator);
        pool.addPolicy(mockPolicyAddress);
    }

    function _stakeAs(address staker, uint64 amount) internal {
        vm.prank(owner);
        token.mintPlain(staker, amount);
        vm.prank(staker);
        token.setOperator(poolAddress, uint48(block.timestamp + 86400));

        InEuint64 memory encAmount = createInEuint64(amount, staker);
        vm.prank(staker);
        pool.stake(encAmount);
    }

    function _splitManager() internal {
        vm.prank(creator);
        pool.transferManager(managerAddr);
    }

    function test_policyManagement_addsPolicyAsCreator() public view {
        assertTrue(pool.isPolicy(mockPolicyAddress));
    }

    function test_policyManagement_removesPolicyAsCreator() public {
        vm.prank(creator);
        pool.removePolicy(mockPolicyAddress);
        assertFalse(pool.isPolicy(mockPolicyAddress));
    }

    function test_policyManagement_revertsAddPolicyIfNotCreator() public {
        MockConfidentialUnderwriterPolicy newPolicy = new MockConfidentialUnderwriterPolicy();
        vm.prank(owner);
        policyRegistry.registerPolicy(address(newPolicy));

        vm.prank(lp1);
        vm.expectRevert(RecoursePoolLib.NotCreator.selector);
        pool.addPolicy(address(newPolicy));
    }

    function test_policyManagement_revertsAddPolicyForManagerAfterTransfer() public {
        _splitManager();

        MockConfidentialUnderwriterPolicy newPolicy = new MockConfidentialUnderwriterPolicy();
        vm.prank(owner);
        policyRegistry.registerPolicy(address(newPolicy));

        vm.prank(managerAddr);
        vm.expectRevert(RecoursePoolLib.NotCreator.selector);
        pool.addPolicy(address(newPolicy));
    }

    function test_policyManagement_revertsAddPolicyForUnregisteredPolicy() public {
        MockConfidentialUnderwriterPolicy unregisteredPolicy = new MockConfidentialUnderwriterPolicy();

        vm.prank(creator);
        vm.expectRevert(RecoursePoolLib.InvalidPolicy.selector);
        pool.addPolicy(address(unregisteredPolicy));
    }

    function test_policyManagement_emitsPolicyAddedEvent() public {
        MockConfidentialUnderwriterPolicy newPolicy = new MockConfidentialUnderwriterPolicy();
        vm.prank(owner);
        policyRegistry.registerPolicy(address(newPolicy));

        vm.prank(creator);
        (, address newPoolAddr) = poolFactory.createPool(IFHERC20(address(token)), address(0), address(0), true);
        ConfidentialRecoursePool newPool = ConfidentialRecoursePool(newPoolAddr);

        vm.prank(creator);
        vm.expectEmit(true, false, false, false);
        emit IRecoursePoolEvents.PolicyAdded(address(newPolicy));
        newPool.addPolicy(address(newPolicy));
    }

    function test_staking_acceptsEncryptedStake() public {
        vm.prank(owner);
        token.mintPlain(lp1, STAKE_AMOUNT);
        vm.prank(lp1);
        token.setOperator(poolAddress, uint48(block.timestamp + 86400));

        InEuint64 memory encStake = createInEuint64(STAKE_AMOUNT, lp1);

        vm.prank(lp1);
        vm.expectEmit(true, false, false, false);
        emit IRecoursePoolEvents.Staked(0);
        pool.stake(encStake);
    }

    function test_staking_incrementsStakeId() public {
        vm.prank(owner);
        token.mintPlain(lp1, STAKE_AMOUNT);
        vm.prank(owner);
        token.mintPlain(lp2, STAKE_AMOUNT);
        vm.prank(lp1);
        token.setOperator(poolAddress, uint48(block.timestamp + 86400));
        vm.prank(lp2);
        token.setOperator(poolAddress, uint48(block.timestamp + 86400));

        InEuint64 memory encStake1 = createInEuint64(STAKE_AMOUNT, lp1);
        vm.prank(lp1);
        pool.stake(encStake1);

        InEuint64 memory encStake2 = createInEuint64(STAKE_AMOUNT, lp2);

        vm.prank(lp2);
        vm.expectEmit(true, false, false, false);
        emit IRecoursePoolEvents.Staked(1);
        pool.stake(encStake2);
    }

    function test_unstaking_allowsStakeOwnerToUnstake() public {
        _stakeAs(lp1, STAKE_AMOUNT);

        vm.prank(lp1);
        vm.expectEmit(true, false, false, false);
        emit IRecoursePoolEvents.Unstaked(0);
        pool.unstake(0);
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
        pool.payClaim(0, euint64.wrap(bytes32(0)));
    }

    function test_accessControl_revertsReceivePremiumIfNotCoverageManager() public {
        _stakeAs(lp1, STAKE_AMOUNT);

        vm.prank(lp1);
        vm.expectRevert(RecoursePoolLib.NotCoverageManager.selector);
        pool.receivePremium(0, euint64.wrap(bytes32(0)));
    }

    function test_accessControl_revertsClaimPremiumsIfNotManager() public {
        _stakeAs(lp1, STAKE_AMOUNT);

        InEuint64 memory encAmount = createInEuint64(100, lp1);
        vm.prank(lp1);
        vm.expectRevert(RecoursePoolLib.NotManager.selector);
        pool.claimPremiums(encAmount);
    }

    function test_accessControl_revertsClaimPremiumsForCreatorAfterTransfer() public {
        _splitManager();
        _stakeAs(lp1, STAKE_AMOUNT);

        InEuint64 memory encAmount = createInEuint64(100, creator);
        vm.prank(creator);
        vm.expectRevert(RecoursePoolLib.NotManager.selector);
        pool.claimPremiums(encAmount);
    }

    function test_viewFunctions_returnsEncryptedTotalLiquidity() public {
        _stakeAs(lp1, STAKE_AMOUNT);

        expectPlaintext(pool.totalLiquidity(), STAKE_AMOUNT);
    }

    function test_viewFunctions_returnsEncryptedStakedAmount() public {
        _stakeAs(lp1, STAKE_AMOUNT);

        expectPlaintext(pool.stakedAmount(0), STAKE_AMOUNT);
    }

    function test_viewFunctions_revertsStakedAmountForNonexistentStake() public {
        _stakeAs(lp1, STAKE_AMOUNT);

        vm.expectRevert(RecoursePoolLib.StakeDoesNotExist.selector);
        pool.stakedAmount(999);
    }

    function test_viewFunctions_returnsPendingRewardsForExistingStake() public {
        _stakeAs(lp1, STAKE_AMOUNT);

        expectPlaintext(pool.pendingRewards(0), uint64(0));
    }

    function test_viewFunctions_revertsPendingRewardsForNonexistentStake() public {
        _stakeAs(lp1, STAKE_AMOUNT);

        vm.expectRevert(RecoursePoolLib.StakeDoesNotExist.selector);
        pool.pendingRewards(999);
    }

    function test_claimPremiumsCap_doesNotUnderflowWhenClaimingMoreThanAvailable() public {
        _stakeAs(lp1, STAKE_AMOUNT);

        InEuint64 memory encAmount = createInEuint64(99999, creator);
        vm.prank(creator);
        pool.claimPremiums(encAmount);

        expectPlaintext(pool.totalLiquidity(), STAKE_AMOUNT);
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
        (, address otherPoolAddr) = poolFactory.createPool(IFHERC20(address(token)), address(0), address(0), true);
        bytes32 dsB = ConfidentialRecoursePool(otherPoolAddr).domainSeparator();

        assertTrue(dsA != dsB);
    }

    function test_createPool_acceptsExplicitManagerAndGuardian() public {
        vm.prank(creator);
        (, address customPoolAddr) = poolFactory.createPool(IFHERC20(address(token)), managerAddr, guardianAddr, false);
        ConfidentialRecoursePool customPool = ConfidentialRecoursePool(customPoolAddr);

        assertEq(customPool.creator(), creator);
        assertEq(customPool.manager(), managerAddr);
        assertEq(customPool.guardian(), guardianAddr);
        assertFalse(customPool.isOpen());
    }

    function test_transferManager_changesManager() public {
        vm.prank(creator);
        vm.expectEmit(true, true, false, false);
        emit IRecoursePoolEvents.ManagerTransferred(creator, managerAddr);
        pool.transferManager(managerAddr);

        assertEq(pool.manager(), managerAddr);
    }

    function test_transferManager_revertsForNonManager() public {
        vm.prank(lp1);
        vm.expectRevert(RecoursePoolLib.NotManager.selector);
        pool.transferManager(managerAddr);
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
        assertEq(pool.manager(), managerAddr);
    }
}
