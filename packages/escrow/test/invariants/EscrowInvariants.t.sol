// SPDX-License-Identifier: FSL-1.1-ALv2
pragma solidity ^0.8.25;

import {Test} from "forge-std/Test.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {Escrow} from "../../contracts/core/Escrow.sol";
import {MockUSDC} from "@reineira-os/shared/contracts/mocks/MockUSDC.sol";

contract EscrowHandler is Test {
    Escrow public immutable escrow;
    MockUSDC public immutable usdc;
    address[] public users;

    uint256 public ghostCreated;
    uint256 public ghostFunded;
    uint256 public ghostRedeemed;

    constructor(Escrow _escrow, MockUSDC _usdc) {
        escrow = _escrow;
        usdc = _usdc;
        users.push(makeAddr("alice"));
        users.push(makeAddr("bob"));
        users.push(makeAddr("carol"));
        for (uint256 i = 0; i < users.length; i++) {
            usdc.mint(users[i], 10_000_000e6);
            vm.prank(users[i]);
            usdc.approve(address(escrow), type(uint256).max);
        }
    }

    function createEscrow(uint256 callerSeed, uint256 ownerSeed, uint256 amount) external {
        amount = bound(amount, 1, 1_000_000e6);
        address caller = users[callerSeed % users.length];
        address owner_ = users[ownerSeed % users.length];
        vm.prank(caller);
        escrow.create(owner_, amount, address(0), "");
        ghostCreated++;
    }

    function fundEscrow(uint256 idSeed, uint256 callerSeed, uint256 amount) external {
        if (escrow.total() == 0) return;
        uint256 id = idSeed % escrow.total();
        if (!escrow.exists(id)) return;
        amount = bound(amount, 1, 100_000e6);
        address caller = users[callerSeed % users.length];
        vm.prank(caller);
        try escrow.fund(id, amount) {
            ghostFunded++;
        } catch {}
    }

    function redeemEscrow(uint256 idSeed) external {
        if (escrow.total() == 0) return;
        uint256 id = idSeed % escrow.total();
        if (!escrow.exists(id)) return;
        if (escrow.getRedeemedStatus(id)) return;
        address owner_ = escrow.getOwner(id);
        vm.prank(owner_);
        try escrow.redeem(id) {
            ghostRedeemed++;
        } catch {}
    }
}

contract EscrowInvariantTest is Test {
    Escrow public escrow;
    MockUSDC public usdc;
    EscrowHandler public handler;
    address public owner;

    function setUp() public {
        owner = makeAddr("owner");
        vm.startPrank(owner);
        usdc = new MockUSDC();
        Escrow impl = new Escrow(address(0));
        escrow = Escrow(
            address(new ERC1967Proxy(address(impl), abi.encodeCall(Escrow.initialize, (owner, address(usdc)))))
        );
        vm.stopPrank();

        handler = new EscrowHandler(escrow, usdc);
        targetContract(address(handler));

        bytes4[] memory selectors = new bytes4[](3);
        selectors[0] = EscrowHandler.createEscrow.selector;
        selectors[1] = EscrowHandler.fundEscrow.selector;
        selectors[2] = EscrowHandler.redeemEscrow.selector;
        targetSelector(FuzzSelector({addr: address(handler), selectors: selectors}));
    }

    function invariant_redeemed_implies_fully_paid() public view {
        uint256 total = escrow.total();
        for (uint256 i = 0; i < total; i++) {
            if (escrow.exists(i) && escrow.getRedeemedStatus(i)) {
                assertGe(
                    escrow.getPaidAmount(i),
                    escrow.getAmount(i),
                    "redeemed escrow paid amount below required amount"
                );
            }
        }
    }

    function invariant_solvency_outstanding_funds_backed_by_balance() public view {
        uint256 outstanding;
        uint256 total = escrow.total();
        for (uint256 i = 0; i < total; i++) {
            if (escrow.exists(i) && !escrow.getRedeemedStatus(i)) {
                outstanding += escrow.getPaidAmount(i);
            }
        }
        assertGe(
            usdc.balanceOf(address(escrow)),
            outstanding,
            "escrow USDC balance below outstanding unredeemed paid amounts"
        );
    }

    function invariant_total_only_grows() public view {
        assertGe(escrow.total(), handler.ghostCreated());
    }

    function invariant_redeemed_count_lte_created() public view {
        assertLe(handler.ghostRedeemed(), handler.ghostCreated());
    }
}
