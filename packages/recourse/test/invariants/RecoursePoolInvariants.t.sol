// SPDX-License-Identifier: FSL-1.1-ALv2
pragma solidity ^0.8.25;

import {Test} from "forge-std/Test.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {RecoursePool} from "../../contracts/core/RecoursePool.sol";
import {IERC20} from "@openzeppelin/contracts/interfaces/IERC20.sol";
import {MockUSDC} from "@reineira-os/shared/contracts/mocks/MockUSDC.sol";

interface IRegistry {
    function isPolicy(address) external view returns (bool);
}

contract MockRegistry is IRegistry {
    function isPolicy(address) external pure returns (bool) {
        return true;
    }
}

contract RecoursePoolHandler is Test {
    RecoursePool public immutable pool;
    MockUSDC public immutable usdc;
    address public immutable creator;
    address public immutable coverageManager;
    address[] public stakers;
    address[] public managerCandidates;

    uint256 public ghostStaked;
    uint256 public ghostUnstaked;
    uint256 public ghostClaims;
    uint256 public ghostPremiumsReceived;
    uint256 public ghostManagerTransfers;
    address public lastManager;

    constructor(RecoursePool _pool, MockUSDC _usdc, address _creator, address _coverageManager) {
        pool = _pool;
        usdc = _usdc;
        creator = _creator;
        coverageManager = _coverageManager;
        lastManager = _creator;
        stakers.push(makeAddr("staker1"));
        stakers.push(makeAddr("staker2"));
        stakers.push(makeAddr("staker3"));
        managerCandidates.push(makeAddr("mgrA"));
        managerCandidates.push(makeAddr("mgrB"));
        managerCandidates.push(makeAddr("mgrC"));
        for (uint256 i = 0; i < stakers.length; i++) {
            usdc.mint(stakers[i], 10_000_000e6);
            vm.prank(stakers[i]);
            usdc.approve(address(pool), type(uint256).max);
        }
        usdc.mint(coverageManager, 10_000_000e6);
        vm.prank(coverageManager);
        usdc.approve(address(pool), type(uint256).max);
    }

    function stakeAction(uint256 stakerSeed, uint256 amount) external {
        amount = bound(amount, 1, 100_000e6);
        address staker = stakers[stakerSeed % stakers.length];
        vm.prank(staker);
        try pool.stake(amount) returns (uint256) {
            ghostStaked++;
        } catch {}
    }

    function unstakeAction(uint256 stakeIdSeed) external {
        uint256 id = stakeIdSeed % 100;
        vm.prank(stakers[stakeIdSeed % stakers.length]);
        try pool.unstake(id) {
            ghostUnstaked++;
        } catch {}
    }

    function payClaimAction(uint256 amount) external {
        amount = bound(amount, 1, 100_000e6);
        vm.prank(coverageManager);
        try pool.payClaim(0, amount) returns (uint256) {
            ghostClaims++;
        } catch {}
    }

    function receivePremiumAction(uint256 amount) external {
        amount = bound(amount, 1, 10_000e6);
        vm.prank(coverageManager);
        try pool.receivePremium(0, amount) {
            ghostPremiumsReceived++;
        } catch {}
    }

    function transferManagerAction(uint256 candidateSeed) external {
        address candidate = managerCandidates[candidateSeed % managerCandidates.length];
        if (candidate == lastManager) return;
        vm.prank(lastManager);
        try pool.transferManager(candidate) {
            lastManager = candidate;
            ghostManagerTransfers++;
        } catch {}
    }
}

contract RecoursePoolInvariantTest is Test {
    RecoursePool public pool;
    MockUSDC public usdc;
    RecoursePoolHandler public handler;
    address public creator;
    address public coverageManager;
    MockRegistry public registry;

    function setUp() public {
        creator = makeAddr("creator");
        coverageManager = makeAddr("coverageManager");
        registry = new MockRegistry();

        vm.startPrank(creator);
        usdc = new MockUSDC();
        RecoursePool impl = new RecoursePool(address(0));
        pool = RecoursePool(
            address(
                new ERC1967Proxy(
                    address(impl),
                    abi.encodeCall(
                        RecoursePool.initialize,
                        (creator, creator, address(0), true, IERC20(address(usdc)), coverageManager, address(registry))
                    )
                )
            )
        );
        vm.stopPrank();

        handler = new RecoursePoolHandler(pool, usdc, creator, coverageManager);
        targetContract(address(handler));

        bytes4[] memory selectors = new bytes4[](5);
        selectors[0] = RecoursePoolHandler.stakeAction.selector;
        selectors[1] = RecoursePoolHandler.unstakeAction.selector;
        selectors[2] = RecoursePoolHandler.payClaimAction.selector;
        selectors[3] = RecoursePoolHandler.receivePremiumAction.selector;
        selectors[4] = RecoursePoolHandler.transferManagerAction.selector;
        targetSelector(FuzzSelector({addr: address(handler), selectors: selectors}));
    }

    function invariant_totalLiquidity_lte_balance() public view {
        assertLe(
            pool.totalLiquidity(),
            usdc.balanceOf(address(pool)),
            "totalLiquidity exceeds USDC balance: pool is insolvent"
        );
    }

    function invariant_unstaked_count_lte_staked() public view {
        assertLe(handler.ghostUnstaked(), handler.ghostStaked());
    }

    function invariant_balance_equals_liquidity() public view {
        assertEq(
            usdc.balanceOf(address(pool)),
            pool.totalLiquidity(),
            "pool USDC balance must stay in lockstep with tracked liquidity"
        );
    }

    function invariant_creator_never_changes() public view {
        assertEq(pool.creator(), creator, "Creator address must be immutable after init");
    }

    function invariant_manager_matches_lastTransfer() public view {
        assertEq(pool.manager(), handler.lastManager(), "Pool manager must match last successful transfer");
    }
}
