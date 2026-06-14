// SPDX-License-Identifier: FSL-1.1-ALv2
// Copyright (c) 2026 Reineira Labs Limited All rights reserved.
pragma solidity ^0.8.24;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {TestnetPausableBase} from "@reineira-os/shared/contracts/common/TestnetPausableBase.sol";
import {ISlashingManager} from "../interfaces/core/ISlashingManager.sol";
import {IOperatorRegistry} from "../interfaces/core/IOperatorRegistry.sol";

contract OperatorSlashingManager is ISlashingManager, TestnetPausableBase {
    using SafeERC20 for IERC20;

    uint256 public constant CHALLENGE_PERIOD = 3 days;
    uint256 public constant VOTING_PERIOD = 4 days;
    uint256 public constant EXPIRY_PERIOD = 14 days;
    uint256 public constant QUORUM_BPS = 1000;
    uint256 public constant PROPOSAL_BOND_BPS = 500;
    uint256 public constant CHALLENGER_BOND_BPS = 500;
    uint256 public constant SLASHER_REWARD_BPS = 1000;

    IERC20 public stakingToken;
    IOperatorRegistry public registry;

    uint256 private _proposalCount;
    mapping(uint256 => SlashProposal) private _proposals;
    mapping(uint256 => mapping(address => bool)) private _hasVoted;
    mapping(uint256 => mapping(address => uint256)) private _voteWeight;

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor(address trustedForwarder_) TestnetPausableBase(trustedForwarder_) {
        _disableInitializers();
    }

    function initialize(address owner_, address stakingToken_, address registry_) external initializer {
        if (stakingToken_ == address(0)) revert ZeroAddress();
        if (registry_ == address(0)) revert ZeroAddress();

        __TestnetPausableBase_init(owner_);

        stakingToken = IERC20(stakingToken_);
        registry = IOperatorRegistry(registry_);
    }

    function proposeSlash(
        address operator,
        uint256 amount,
        bytes32 evidence
    ) external nonReentrant whenNotPaused returns (uint256 proposalId) {
        if (operator == address(0)) revert ZeroAddress();
        if (amount == 0) revert ZeroAmount();
        if (operator == msg.sender) revert CannotSlashSelf();

        IOperatorRegistry.OperatorInfo memory operatorInfo = registry.getOperatorInfo(operator);
        if (operatorInfo.stake == 0) revert NotOperator();

        uint256 bondAmount = (amount * PROPOSAL_BOND_BPS) / 10000;
        if (bondAmount == 0) bondAmount = 1;

        stakingToken.safeTransferFrom(msg.sender, address(this), bondAmount);

        proposalId = ++_proposalCount;

        _proposals[proposalId] = SlashProposal({
            proposer: msg.sender,
            operator: operator,
            amount: amount,
            evidence: evidence,
            proposerBond: bondAmount,
            challengerBond: 0,
            challenger: address(0),
            createdAt: block.timestamp,
            challengedAt: 0,
            votesFor: 0,
            votesAgainst: 0,
            state: ProposalState.Pending
        });

        emit SlashProposed(proposalId, msg.sender, operator, amount, evidence);
    }

    function challenge(uint256 proposalId) external nonReentrant whenNotPaused {
        SlashProposal storage proposal = _proposals[proposalId];
        if (proposal.proposer == address(0)) revert ProposalNotFound();
        if (proposal.state != ProposalState.Pending) revert InvalidProposalState();
        if (block.timestamp > proposal.createdAt + CHALLENGE_PERIOD) revert InvalidProposalState();

        uint256 bondAmount = (proposal.amount * CHALLENGER_BOND_BPS) / 10000;
        if (bondAmount == 0) bondAmount = 1;

        stakingToken.safeTransferFrom(msg.sender, address(this), bondAmount);

        proposal.challenger = msg.sender;
        proposal.challengerBond = bondAmount;
        proposal.challengedAt = block.timestamp;
        proposal.state = ProposalState.Challenged;

        emit SlashChallenged(proposalId, msg.sender);
    }

    function vote(uint256 proposalId, bool support) external nonReentrant whenNotPaused {
        SlashProposal storage proposal = _proposals[proposalId];
        if (proposal.proposer == address(0)) revert ProposalNotFound();
        if (proposal.state != ProposalState.Challenged) revert VotingNotActive();
        if (_hasVoted[proposalId][msg.sender]) revert AlreadyVoted();

        if (block.timestamp > proposal.challengedAt + VOTING_PERIOD) revert VotingNotActive();

        IOperatorRegistry.OperatorInfo memory voterInfo = registry.getOperatorInfo(msg.sender);
        uint256 weight = voterInfo.stake;
        if (weight == 0) revert NotOperator();

        _hasVoted[proposalId][msg.sender] = true;
        _voteWeight[proposalId][msg.sender] = weight;

        if (support) {
            proposal.votesFor += weight;
        } else {
            proposal.votesAgainst += weight;
        }

        emit Voted(proposalId, msg.sender, support, weight);
    }

    function execute(uint256 proposalId) external nonReentrant {
        SlashProposal storage proposal = _proposals[proposalId];
        if (proposal.proposer == address(0)) revert ProposalNotFound();

        ProposalState currentState = _calculateState(proposal);

        if (currentState == ProposalState.Pending) {
            if (block.timestamp <= proposal.createdAt + CHALLENGE_PERIOD) {
                revert ChallengePeriodNotEnded();
            }
            _executeSlash(proposalId, proposal);
        } else if (currentState == ProposalState.Challenged) {
            if (block.timestamp <= proposal.challengedAt + VOTING_PERIOD) {
                revert VotingPeriodNotEnded();
            }
            _resolveVoting(proposalId, proposal);
        } else if (currentState == ProposalState.Expired) {
            _expireProposal(proposalId, proposal);
        } else {
            revert InvalidProposalState();
        }
    }

    function getProposal(uint256 proposalId) external view returns (SlashProposal memory) {
        return _proposals[proposalId];
    }

    function getProposalState(uint256 proposalId) external view returns (ProposalState) {
        SlashProposal storage proposal = _proposals[proposalId];
        if (proposal.proposer == address(0)) revert ProposalNotFound();
        return _calculateState(proposal);
    }

    function hasVoted(uint256 proposalId, address voter) external view returns (bool) {
        return _hasVoted[proposalId][voter];
    }

    function proposalCount() external view returns (uint256) {
        return _proposalCount;
    }

    function setRegistry(address registry_) external onlyOwner {
        if (registry_ == address(0)) revert ZeroAddress();
        registry = IOperatorRegistry(registry_);
    }

    function _calculateState(SlashProposal storage proposal) private view returns (ProposalState) {
        if (
            proposal.state == ProposalState.Executed ||
            proposal.state == ProposalState.Rejected ||
            proposal.state == ProposalState.Expired
        ) {
            return proposal.state;
        }

        if (block.timestamp > proposal.createdAt + EXPIRY_PERIOD) {
            return ProposalState.Expired;
        }

        return proposal.state;
    }

    function _executeSlash(uint256 proposalId, SlashProposal storage proposal) private {
        proposal.state = ProposalState.Executed;

        IOperatorRegistry.OperatorInfo memory operatorInfo = registry.getOperatorInfo(proposal.operator);
        uint256 actualSlashAmount = proposal.amount > operatorInfo.stake ? operatorInfo.stake : proposal.amount;

        registry.slash(proposal.operator, actualSlashAmount, proposal.evidence);

        uint256 reward = (actualSlashAmount * SLASHER_REWARD_BPS) / 10000;
        if (reward > 0) {
            stakingToken.safeTransfer(proposal.proposer, reward);
        }

        stakingToken.safeTransfer(proposal.proposer, proposal.proposerBond);
        emit BondReturned(proposalId, proposal.proposer, proposal.proposerBond);

        emit SlashExecuted(proposalId, proposal.operator, actualSlashAmount);
    }

    function _resolveVoting(uint256 proposalId, SlashProposal storage proposal) private {
        uint256 totalVotes = proposal.votesFor + proposal.votesAgainst;

        uint256 totalStaked = _getTotalStaked();
        uint256 quorum = (totalStaked * QUORUM_BPS) / 10000;

        bool quorumReached = totalVotes >= quorum;
        bool slashApproved = quorumReached && proposal.votesFor > proposal.votesAgainst;

        if (slashApproved) {
            proposal.state = ProposalState.Executed;

            IOperatorRegistry.OperatorInfo memory operatorInfo = registry.getOperatorInfo(proposal.operator);
            uint256 actualSlashAmount = proposal.amount > operatorInfo.stake ? operatorInfo.stake : proposal.amount;

            registry.slash(proposal.operator, actualSlashAmount, proposal.evidence);

            uint256 reward = (actualSlashAmount * SLASHER_REWARD_BPS) / 10000;
            if (reward > 0) {
                stakingToken.safeTransfer(proposal.proposer, reward);
            }

            stakingToken.safeTransfer(proposal.proposer, proposal.proposerBond);
            emit BondReturned(proposalId, proposal.proposer, proposal.proposerBond);

            stakingToken.safeTransfer(proposal.proposer, proposal.challengerBond);
            emit BondSlashed(proposalId, proposal.challenger, proposal.proposer, proposal.challengerBond);

            emit SlashExecuted(proposalId, proposal.operator, actualSlashAmount);
        } else {
            proposal.state = ProposalState.Rejected;

            stakingToken.safeTransfer(proposal.challenger, proposal.challengerBond);
            emit BondReturned(proposalId, proposal.challenger, proposal.challengerBond);

            stakingToken.safeTransfer(proposal.challenger, proposal.proposerBond);
            emit BondSlashed(proposalId, proposal.proposer, proposal.challenger, proposal.proposerBond);

            emit SlashRejected(proposalId, proposal.operator);
        }
    }

    function _expireProposal(uint256 proposalId, SlashProposal storage proposal) private {
        proposal.state = ProposalState.Expired;

        stakingToken.safeTransfer(proposal.proposer, proposal.proposerBond);
        emit BondReturned(proposalId, proposal.proposer, proposal.proposerBond);

        if (proposal.challengerBond > 0) {
            stakingToken.safeTransfer(proposal.challenger, proposal.challengerBond);
            emit BondReturned(proposalId, proposal.challenger, proposal.challengerBond);
        }

        emit ProposalExpired(proposalId);
    }

    function _getTotalStaked() private view returns (uint256 total) {
        address[] memory operators = registry.getActiveOperators();
        for (uint256 i = 0; i < operators.length; i++) {
            IOperatorRegistry.OperatorInfo memory info = registry.getOperatorInfo(operators[i]);
            total += info.stake;
        }
    }
}
