// SPDX-License-Identifier: FSL-1.1-ALv2
pragma solidity ^0.8.25;

import {Test} from "forge-std/Test.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {PolicyRegistry} from "../../contracts/core/PolicyRegistry.sol";
import {PoolFactory} from "../../contracts/core/PoolFactory.sol";
import {RecoursePool} from "../../contracts/core/RecoursePool.sol";
import {CoverageManager} from "../../contracts/core/CoverageManager.sol";
import {ICoverageManager} from "../../contracts/interfaces/core/ICoverageManager.sol";
import {MockUSDC} from "@reineira-os/shared/contracts/mocks/MockUSDC.sol";
import {MockEscrow} from "../../contracts/mocks/MockEscrow.sol";
import {VerdictUnderwriterPolicy} from "../../contracts/plugins/VerdictUnderwriterPolicy.sol";

contract VerdictRecourseFlowTest is Test {
    PoolFactory poolFactory;
    PolicyRegistry policyRegistry;
    CoverageManager coverageManager;
    MockUSDC usdc;
    MockEscrow mockEscrow;
    VerdictUnderwriterPolicy policy;

    address owner = makeAddr("owner");
    address operator = makeAddr("operator");
    address client = makeAddr("client");

    uint256 signerPk = 0xA11CE;
    address signer;

    uint256 constant STAKE = 50_000e6;
    uint256 constant ESCROW_AMOUNT = 20_000e6;
    uint256 constant COVERAGE = 10_000e6;
    uint256 constant ESCROW_ID = 42;

    function setUp() public {
        vm.warp(1_000_000);
        signer = vm.addr(signerPk);

        vm.startPrank(owner);
        usdc = new MockUSDC();
        mockEscrow = new MockEscrow();
        policy = new VerdictUnderwriterPolicy(signer, 1 days);

        PolicyRegistry registryImpl = new PolicyRegistry(address(0));
        policyRegistry = PolicyRegistry(
            address(new ERC1967Proxy(address(registryImpl), abi.encodeCall(PolicyRegistry.initialize, (owner))))
        );
        policyRegistry.registerPolicy(address(policy));

        RecoursePool poolImpl = new RecoursePool(address(0));
        CoverageManager cmImpl = new CoverageManager(address(0));
        coverageManager = CoverageManager(
            address(new ERC1967Proxy(address(cmImpl), abi.encodeCall(CoverageManager.initialize, (owner, owner))))
        );
        coverageManager.setEscrow(address(mockEscrow));

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
    }

    function _setupActiveCoverage() internal returns (RecoursePool pool, uint256 covId) {
        vm.prank(operator);
        poolFactory.createPool(address(usdc), address(0), address(0), true);
        pool = RecoursePool(poolFactory.pool(0));

        vm.prank(operator);
        pool.addPolicy(address(policy));

        usdc.mint(operator, STAKE);
        vm.startPrank(operator);
        usdc.approve(address(pool), STAKE);
        pool.stake(STAKE);
        vm.stopPrank();

        mockEscrow.setExists(ESCROW_ID, true);
        mockEscrow.setAmount(ESCROW_ID, ESCROW_AMOUNT);

        vm.prank(operator);
        covId = coverageManager.purchaseCoverage(
            client, address(pool), address(policy), ESCROW_ID, COVERAGE, block.timestamp + 1 days, "", ""
        );
    }

    function _signedVerdict(uint256 covId, uint256 nonce, uint256 pk) internal view returns (bytes memory) {
        VerdictUnderwriterPolicy.Verdict memory v = VerdictUnderwriterPolicy.Verdict({
            coverageId: covId,
            breach: true,
            amount: COVERAGE,
            nonce: nonce,
            issuedAt: block.timestamp,
            termsHash: keccak256("skill-terms"),
            triggerSpecHash: keccak256("deadline-missed")
        });
        (uint8 yv, bytes32 r, bytes32 s) = vm.sign(pk, policy.hashVerdict(v));
        return abi.encode(v, abi.encodePacked(r, s, yv));
    }

    function test_signedVerdict_drivesRealPayoutToClient() public {
        (RecoursePool pool, uint256 covId) = _setupActiveCoverage();
        assertEq(usdc.balanceOf(client), 0);

        bytes memory verdict = _signedVerdict(covId, 1, signerPk);
        vm.prank(client);
        coverageManager.dispute(covId, verdict);

        assertEq(usdc.balanceOf(client), COVERAGE, "client receives payout from signed verdict");
        assertEq(uint256(coverageManager.coverageStatus(covId)), uint256(ICoverageManager.CoverageStatus.Claimed));
        assertTrue(policy.usedNonce(1));
        pool;
    }

    function test_forgedVerdict_wrongSigner_revertsDispute() public {
        (, uint256 covId) = _setupActiveCoverage();

        bytes memory forged = _signedVerdict(covId, 1, 0xBADBAD);
        vm.prank(client);
        vm.expectRevert(VerdictUnderwriterPolicy.InvalidSigner.selector);
        coverageManager.dispute(covId, forged);

        assertEq(usdc.balanceOf(client), 0, "no payout on forged verdict");
    }
}
