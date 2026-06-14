// SPDX-License-Identifier: FSL-1.1-ALv2
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {OperatorRegistry} from "../../contracts/core/OperatorRegistry.sol";
import {OperatorSlashingManager} from "../../contracts/core/OperatorSlashingManager.sol";
import {MockGovernanceToken} from "../../contracts/mocks/MockGovernanceToken.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {ISlashingManager} from "../../contracts/interfaces/core/ISlashingManager.sol";
import {Pausable} from "@openzeppelin/contracts/utils/Pausable.sol";

contract OperatorSlashingManagerTest is Test {
    uint256 constant MIN_STAKE = 5000e18;
    uint256 constant EXCLUSIVE_WINDOW = 60;
    uint256 constant PERMISSIONLESS_DELAY = 600;
    uint256 constant CHALLENGE_PERIOD = 3 days;
    uint256 constant VOTING_PERIOD = 4 days;
    uint256 constant EXPIRY_PERIOD = 14 days;
    uint256 constant PROPOSAL_BOND_BPS = 500;
    uint256 constant CHALLENGER_BOND_BPS = 500;
    uint256 constant SLASHER_REWARD_BPS = 1000;
    uint256 constant MINT_AMOUNT = 100_000e18;

    OperatorRegistry registry;
    OperatorSlashingManager slashingManager;
    MockGovernanceToken stakingToken;

    address owner = makeAddr("owner");
    address proposer = makeAddr("proposer");
    address operator1 = makeAddr("operator1");
    address operator2 = makeAddr("operator2");
    address operator3 = makeAddr("operator3");
    address challenger = makeAddr("challenger");
    address user = makeAddr("user");

    bytes32 evidence = keccak256("malicious activity");
    uint256 slashAmount = 1000e18;

    function setUp() public {
        vm.startPrank(owner);

        stakingToken = new MockGovernanceToken();

        OperatorRegistry registryImpl = new OperatorRegistry(address(0));
        bytes memory registryInit = abi.encodeCall(
            OperatorRegistry.initialize,
            (owner, address(stakingToken), MIN_STAKE, EXCLUSIVE_WINDOW, PERMISSIONLESS_DELAY)
        );
        registry = OperatorRegistry(address(new ERC1967Proxy(address(registryImpl), registryInit)));

        OperatorSlashingManager smImpl = new OperatorSlashingManager(address(0));
        bytes memory smInit = abi.encodeCall(
            OperatorSlashingManager.initialize,
            (owner, address(stakingToken), address(registry))
        );
        slashingManager = OperatorSlashingManager(address(new ERC1967Proxy(address(smImpl), smInit)));

        registry.setSlashingManager(address(slashingManager));

        stakingToken.mint(proposer, MINT_AMOUNT);
        stakingToken.mint(operator1, MINT_AMOUNT);
        stakingToken.mint(operator2, MINT_AMOUNT);
        stakingToken.mint(operator3, MINT_AMOUNT);
        stakingToken.mint(challenger, MINT_AMOUNT);

        vm.stopPrank();

        vm.prank(proposer);
        stakingToken.approve(address(slashingManager), MINT_AMOUNT);

        vm.prank(operator1);
        stakingToken.approve(address(registry), MINT_AMOUNT);

        vm.prank(operator2);
        stakingToken.approve(address(registry), MINT_AMOUNT);

        vm.prank(operator3);
        stakingToken.approve(address(registry), MINT_AMOUNT);

        vm.prank(challenger);
        stakingToken.approve(address(slashingManager), MINT_AMOUNT);

        vm.prank(operator1);
        registry.registerOperator(MIN_STAKE);

        vm.prank(operator2);
        registry.registerOperator(MIN_STAKE);

        vm.prank(operator3);
        registry.registerOperator(MIN_STAKE);
    }

    function _proposeSlash() internal returns (uint256) {
        vm.prank(proposer);
        return slashingManager.proposeSlash(operator1, slashAmount, evidence);
    }

    function _proposeAndChallenge() internal {
        _proposeSlash();
        vm.prank(challenger);
        slashingManager.challenge(1);
    }

    function test_deployment_initializesWithCorrectParams() public view {
        assertEq(address(slashingManager.stakingToken()), address(stakingToken));
        assertEq(address(slashingManager.registry()), address(registry));
        assertEq(slashingManager.proposalCount(), 0);
    }

    function test_deployment_rejectsZeroStakingToken() public {
        OperatorSlashingManager impl = new OperatorSlashingManager(address(0));
        bytes memory initData = abi.encodeCall(
            OperatorSlashingManager.initialize,
            (owner, address(0), address(registry))
        );
        vm.expectRevert(ISlashingManager.ZeroAddress.selector);
        new ERC1967Proxy(address(impl), initData);
    }

    function test_proposeSlash_createsProposalWithCorrectBond() public {
        uint256 expectedBond = (slashAmount * PROPOSAL_BOND_BPS) / 10000;
        uint256 balanceBefore = stakingToken.balanceOf(proposer);

        uint256 proposalId = _proposeSlash();

        uint256 balanceAfter = stakingToken.balanceOf(proposer);
        assertEq(balanceBefore - balanceAfter, expectedBond);
        assertEq(slashingManager.proposalCount(), 1);
        assertEq(proposalId, 1);

        ISlashingManager.SlashProposal memory proposal = slashingManager.getProposal(1);
        assertEq(proposal.proposer, proposer);
        assertEq(proposal.operator, operator1);
        assertEq(proposal.amount, slashAmount);
        assertEq(proposal.evidence, evidence);
        assertEq(proposal.proposerBond, expectedBond);
        assertEq(uint8(proposal.state), 0);
    }

    function test_proposeSlash_emitsSlashProposed() public {
        uint256 expectedBond = (slashAmount * PROPOSAL_BOND_BPS) / 10000;
        vm.expectEmit(true, true, true, true);
        emit ISlashingManager.SlashProposed(1, proposer, operator1, slashAmount, evidence);
        _proposeSlash();
    }

    function test_proposeSlash_rejectsZeroOperator() public {
        vm.prank(proposer);
        vm.expectRevert(ISlashingManager.ZeroAddress.selector);
        slashingManager.proposeSlash(address(0), slashAmount, evidence);
    }

    function test_proposeSlash_rejectsZeroAmount() public {
        vm.prank(proposer);
        vm.expectRevert(ISlashingManager.ZeroAmount.selector);
        slashingManager.proposeSlash(operator1, 0, evidence);
    }

    function test_proposeSlash_rejectsSlashingSelf() public {
        vm.prank(operator1);
        stakingToken.approve(address(slashingManager), MINT_AMOUNT);

        vm.prank(operator1);
        vm.expectRevert(ISlashingManager.CannotSlashSelf.selector);
        slashingManager.proposeSlash(operator1, slashAmount, evidence);
    }

    function test_proposeSlash_rejectsNonOperatorTarget() public {
        vm.prank(proposer);
        vm.expectRevert(ISlashingManager.NotOperator.selector);
        slashingManager.proposeSlash(user, slashAmount, evidence);
    }

    function test_challenge_challengesWithinPeriodWithBond() public {
        _proposeSlash();

        uint256 expectedChallengerBond = (slashAmount * CHALLENGER_BOND_BPS) / 10000;
        uint256 balanceBefore = stakingToken.balanceOf(challenger);

        vm.prank(challenger);
        slashingManager.challenge(1);

        uint256 balanceAfter = stakingToken.balanceOf(challenger);
        assertEq(balanceBefore - balanceAfter, expectedChallengerBond);

        ISlashingManager.SlashProposal memory proposal = slashingManager.getProposal(1);
        assertEq(proposal.challenger, challenger);
        assertEq(proposal.challengerBond, expectedChallengerBond);
        assertEq(uint8(proposal.state), 1);
    }

    function test_challenge_emitsSlashChallenged() public {
        _proposeSlash();

        vm.expectEmit(true, true, false, true);
        emit ISlashingManager.SlashChallenged(1, challenger);

        vm.prank(challenger);
        slashingManager.challenge(1);
    }

    function test_challenge_rejectsAfterPeriod() public {
        _proposeSlash();

        vm.warp(block.timestamp + CHALLENGE_PERIOD + 1);

        vm.prank(challenger);
        vm.expectRevert(ISlashingManager.InvalidProposalState.selector);
        slashingManager.challenge(1);
    }

    function test_challenge_rejectsNonExistent() public {
        vm.prank(challenger);
        vm.expectRevert(ISlashingManager.ProposalNotFound.selector);
        slashingManager.challenge(999);
    }

    function test_voting_operatorVotesFor() public {
        _proposeAndChallenge();

        vm.prank(operator2);
        slashingManager.vote(1, true);

        assertTrue(slashingManager.hasVoted(1, operator2));

        ISlashingManager.SlashProposal memory proposal = slashingManager.getProposal(1);
        assertEq(proposal.votesFor, MIN_STAKE);
    }

    function test_voting_emitsVoted() public {
        _proposeAndChallenge();

        vm.expectEmit(true, true, false, true);
        emit ISlashingManager.Voted(1, operator2, true, MIN_STAKE);

        vm.prank(operator2);
        slashingManager.vote(1, true);
    }

    function test_voting_votesAgainst() public {
        _proposeAndChallenge();

        vm.prank(operator2);
        slashingManager.vote(1, false);

        ISlashingManager.SlashProposal memory proposal = slashingManager.getProposal(1);
        assertEq(proposal.votesAgainst, MIN_STAKE);
    }

    function test_voting_rejectsDoubleVote() public {
        _proposeAndChallenge();

        vm.prank(operator2);
        slashingManager.vote(1, true);

        vm.prank(operator2);
        vm.expectRevert(ISlashingManager.AlreadyVoted.selector);
        slashingManager.vote(1, false);
    }

    function test_voting_rejectsOnUnchallenged() public {
        _proposeSlash();

        vm.prank(operator2);
        vm.expectRevert(ISlashingManager.VotingNotActive.selector);
        slashingManager.vote(1, true);
    }

    function test_voting_rejectsAfterVotingPeriod() public {
        _proposeAndChallenge();

        vm.warp(block.timestamp + VOTING_PERIOD + 1);

        vm.prank(operator2);
        vm.expectRevert(ISlashingManager.VotingNotActive.selector);
        slashingManager.vote(1, true);
    }

    function test_voting_rejectsNonOperator() public {
        _proposeAndChallenge();

        vm.prank(user);
        vm.expectRevert(ISlashingManager.NotOperator.selector);
        slashingManager.vote(1, true);
    }

    function test_executeUnchallenged_executesAfterChallengePeriod() public {
        _proposeSlash();

        vm.warp(block.timestamp + CHALLENGE_PERIOD + 1);

        uint256 proposerBalanceBefore = stakingToken.balanceOf(proposer);

        slashingManager.execute(1);

        ISlashingManager.SlashProposal memory proposal = slashingManager.getProposal(1);
        assertEq(uint8(proposal.state), 2);

        OperatorRegistry.OperatorInfo memory operatorInfo = registry.getOperatorInfo(operator1);
        assertEq(operatorInfo.stake, MIN_STAKE - slashAmount);
        assertTrue(operatorInfo.slashed);

        uint256 expectedBond = (slashAmount * PROPOSAL_BOND_BPS) / 10000;
        uint256 expectedReward = (slashAmount * SLASHER_REWARD_BPS) / 10000;
        uint256 proposerBalanceAfter = stakingToken.balanceOf(proposer);
        assertEq(proposerBalanceAfter - proposerBalanceBefore, expectedBond + expectedReward);
    }

    function test_executeUnchallenged_emitsSlashExecuted() public {
        _proposeSlash();

        vm.warp(block.timestamp + CHALLENGE_PERIOD + 1);

        vm.expectEmit(true, true, false, true);
        emit ISlashingManager.SlashExecuted(1, operator1, slashAmount);

        slashingManager.execute(1);
    }

    function test_executeUnchallenged_rejectsBeforeChallengePeriod() public {
        _proposeSlash();

        vm.expectRevert(ISlashingManager.ChallengePeriodNotEnded.selector);
        slashingManager.execute(1);
    }

    function test_executeChallenged_slashPassesWhenVotesForWin() public {
        _proposeAndChallenge();

        vm.prank(operator2);
        slashingManager.vote(1, true);

        vm.prank(operator3);
        slashingManager.vote(1, true);

        vm.warp(block.timestamp + VOTING_PERIOD + 1);

        uint256 proposerBalanceBefore = stakingToken.balanceOf(proposer);

        slashingManager.execute(1);

        ISlashingManager.SlashProposal memory proposal = slashingManager.getProposal(1);
        assertEq(uint8(proposal.state), 2);

        OperatorRegistry.OperatorInfo memory operatorInfo = registry.getOperatorInfo(operator1);
        assertTrue(operatorInfo.slashed);

        uint256 expectedBond = (slashAmount * PROPOSAL_BOND_BPS) / 10000;
        uint256 expectedChallengerBond = (slashAmount * CHALLENGER_BOND_BPS) / 10000;
        uint256 expectedReward = (slashAmount * SLASHER_REWARD_BPS) / 10000;
        uint256 proposerBalanceAfter = stakingToken.balanceOf(proposer);
        assertEq(proposerBalanceAfter - proposerBalanceBefore, expectedBond + expectedChallengerBond + expectedReward);
    }

    function test_executeChallenged_slashFailsWhenVotesAgainstWin() public {
        _proposeAndChallenge();

        vm.prank(operator2);
        slashingManager.vote(1, false);

        vm.prank(operator3);
        slashingManager.vote(1, false);

        vm.warp(block.timestamp + VOTING_PERIOD + 1);

        uint256 challengerBalanceBefore = stakingToken.balanceOf(challenger);

        slashingManager.execute(1);

        ISlashingManager.SlashProposal memory proposal = slashingManager.getProposal(1);
        assertEq(uint8(proposal.state), 3);

        uint256 expectedChallengerBond = (slashAmount * CHALLENGER_BOND_BPS) / 10000;
        uint256 expectedProposerBond = (slashAmount * PROPOSAL_BOND_BPS) / 10000;
        uint256 challengerBalanceAfter = stakingToken.balanceOf(challenger);
        assertEq(challengerBalanceAfter - challengerBalanceBefore, expectedChallengerBond + expectedProposerBond);
    }

    function test_executeChallenged_rejectsBeforeVotingEnds() public {
        _proposeAndChallenge();

        vm.prank(operator2);
        slashingManager.vote(1, true);

        vm.expectRevert(ISlashingManager.VotingPeriodNotEnded.selector);
        slashingManager.execute(1);
    }

    function test_expiry_expiresAfterExpiryPeriod() public {
        _proposeSlash();

        vm.warp(block.timestamp + EXPIRY_PERIOD + 1);

        uint256 proposerBalanceBefore = stakingToken.balanceOf(proposer);

        slashingManager.execute(1);

        ISlashingManager.SlashProposal memory proposal = slashingManager.getProposal(1);
        assertEq(uint8(proposal.state), 4);

        uint256 expectedBond = (slashAmount * PROPOSAL_BOND_BPS) / 10000;
        uint256 proposerBalanceAfter = stakingToken.balanceOf(proposer);
        assertEq(proposerBalanceAfter - proposerBalanceBefore, expectedBond);
    }

    function test_expiry_returnsBothBondsOnChallengedExpiry() public {
        _proposeAndChallenge();

        vm.warp(block.timestamp + EXPIRY_PERIOD + 1);

        uint256 proposerBalanceBefore = stakingToken.balanceOf(proposer);
        uint256 challengerBalanceBefore = stakingToken.balanceOf(challenger);

        slashingManager.execute(1);

        uint256 expectedProposerBond = (slashAmount * PROPOSAL_BOND_BPS) / 10000;
        uint256 expectedChallengerBond = (slashAmount * CHALLENGER_BOND_BPS) / 10000;

        uint256 proposerBalanceAfter = stakingToken.balanceOf(proposer);
        uint256 challengerBalanceAfter = stakingToken.balanceOf(challenger);

        assertEq(proposerBalanceAfter - proposerBalanceBefore, expectedProposerBond);
        assertEq(challengerBalanceAfter - challengerBalanceBefore, expectedChallengerBond);
    }

    function test_expiry_emitsProposalExpired() public {
        _proposeSlash();

        vm.warp(block.timestamp + EXPIRY_PERIOD + 1);

        vm.expectEmit(true, false, false, true);
        emit ISlashingManager.ProposalExpired(1);

        slashingManager.execute(1);
    }

    function test_viewFunctions_returnsProposalState() public {
        _proposeSlash();

        assertEq(uint8(slashingManager.getProposalState(1)), 0);
    }

    function test_viewFunctions_revertsOnNonExistentProposal() public {
        vm.expectRevert(ISlashingManager.ProposalNotFound.selector);
        slashingManager.getProposalState(999);
    }

    function test_admin_setsRegistry() public {
        address newRegistry = makeAddr("newRegistry");

        vm.prank(owner);
        slashingManager.setRegistry(newRegistry);

        assertEq(address(slashingManager.registry()), newRegistry);
    }

    function test_admin_rejectsZeroRegistryAddress() public {
        vm.prank(owner);
        vm.expectRevert(ISlashingManager.ZeroAddress.selector);
        slashingManager.setRegistry(address(0));
    }

    function test_pausable_pauseBlocksAndUnpauseAllows() public {
        vm.prank(owner);
        slashingManager.pause();

        vm.prank(proposer);
        vm.expectRevert(Pausable.EnforcedPause.selector);
        slashingManager.proposeSlash(operator1, slashAmount, evidence);

        vm.prank(owner);
        slashingManager.unpause();

        vm.prank(proposer);
        uint256 proposalId = slashingManager.proposeSlash(operator1, slashAmount, evidence);

        assertEq(slashingManager.proposalCount(), 1);
    }
}
