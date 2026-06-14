// SPDX-License-Identifier: FSL-1.1-ALv2
// Copyright (c) 2026 Reineira Labs Limited All rights reserved.
pragma solidity ^0.8.24;

/// @title ISlashingManager
/// @notice Interface for decentralized operator slashing via optimistic dispute resolution
/// @dev Implements a propose → challenge → vote → execute flow for slashing misbehaving operators
interface ISlashingManager {
    /// @notice The lifecycle state of a slash proposal
    enum ProposalState {
        Pending,
        Challenged,
        Executed,
        Rejected,
        Expired
    }

    /// @notice Full on-chain state for a slash proposal
    /// @param proposer The operator who proposed the slash
    /// @param operator The operator being slashed
    /// @param amount The amount of stake to slash
    /// @param evidence The evidence hash justifying the slash
    /// @param proposerBond The bond deposited by the proposer
    /// @param challengerBond The bond deposited by the challenger (0 if unchallenged)
    /// @param challenger The address that challenged the proposal (zero if unchallenged)
    /// @param createdAt The timestamp when the proposal was created
    /// @param challengedAt The timestamp when the proposal was challenged (0 if unchallenged)
    /// @param votesFor The weighted votes in favor of slashing
    /// @param votesAgainst The weighted votes against slashing
    /// @param state The current lifecycle state of the proposal
    struct SlashProposal {
        address proposer;
        address operator;
        uint256 amount;
        bytes32 evidence;
        uint256 proposerBond;
        uint256 challengerBond;
        address challenger;
        uint256 createdAt;
        uint256 challengedAt;
        uint256 votesFor;
        uint256 votesAgainst;
        ProposalState state;
    }

    /// @notice Emitted when a new slash proposal is created
    /// @param proposalId The unique ID of the proposal
    /// @param proposer The operator proposing the slash
    /// @param operator The operator targeted for slashing
    /// @param amount The amount of stake proposed to slash
    /// @param evidence The evidence hash supporting the proposal
    event SlashProposed(
        uint256 indexed proposalId,
        address indexed proposer,
        address indexed operator,
        uint256 amount,
        bytes32 evidence
    );

    /// @notice Emitted when a proposal is challenged
    /// @param proposalId The ID of the challenged proposal
    /// @param challenger The address challenging the proposal
    event SlashChallenged(uint256 indexed proposalId, address indexed challenger);

    /// @notice Emitted when an operator votes on a challenged proposal
    /// @param proposalId The ID of the proposal being voted on
    /// @param voter The operator casting the vote
    /// @param support True if voting in favor of slashing, false if against
    /// @param weight The stake-weighted vote power
    event Voted(uint256 indexed proposalId, address indexed voter, bool support, uint256 weight);

    /// @notice Emitted when a slash is executed against the target operator
    /// @param proposalId The ID of the executed proposal
    /// @param operator The operator whose stake was slashed
    /// @param amount The amount of stake slashed
    event SlashExecuted(uint256 indexed proposalId, address indexed operator, uint256 amount);

    /// @notice Emitted when a slash proposal is rejected (votes against >= votes for)
    /// @param proposalId The ID of the rejected proposal
    /// @param operator The operator who was defended
    event SlashRejected(uint256 indexed proposalId, address indexed operator);

    /// @notice Emitted when a proposal expires without execution
    /// @param proposalId The ID of the expired proposal
    event ProposalExpired(uint256 indexed proposalId);

    /// @notice Emitted when a bond is returned to its depositor
    /// @param proposalId The ID of the associated proposal
    /// @param recipient The address receiving the returned bond
    /// @param amount The bond amount returned
    event BondReturned(uint256 indexed proposalId, address indexed recipient, uint256 amount);

    /// @notice Emitted when a bond is forfeited and transferred to the winning party
    /// @param proposalId The ID of the associated proposal
    /// @param from The address whose bond was forfeited
    /// @param to The address receiving the forfeited bond
    /// @param amount The bond amount transferred
    event BondSlashed(uint256 indexed proposalId, address indexed from, address indexed to, uint256 amount);

    /// @notice Thrown when the provided bond is insufficient
    error InsufficientBond();

    /// @notice Thrown when referencing a non-existent proposal
    error ProposalNotFound();

    /// @notice Thrown when the proposal is not in the required state for the action
    error InvalidProposalState();

    /// @notice Thrown when an operator tries to vote twice on the same proposal
    error AlreadyVoted();

    /// @notice Thrown when voting is not active for the proposal
    error VotingNotActive();

    /// @notice Thrown when trying to execute before the challenge period ends
    error ChallengePeriodNotEnded();

    /// @notice Thrown when trying to execute before the voting period ends
    error VotingPeriodNotEnded();

    /// @notice Thrown when a non-operator tries to perform an operator-only action
    error NotOperator();

    /// @notice Thrown when an operator tries to propose slashing themselves
    error CannotSlashSelf();

    /// @notice Thrown when a zero amount is provided
    error ZeroAmount();

    /// @notice Thrown when a zero address is provided
    error ZeroAddress();

    /// @notice Proposes slashing an operator, requiring a bond deposit
    /// @param operator The operator to slash
    /// @param amount The amount of stake to slash
    /// @param evidence The evidence hash supporting the proposal
    /// @return proposalId The unique ID of the created proposal
    function proposeSlash(address operator, uint256 amount, bytes32 evidence) external returns (uint256 proposalId);

    /// @notice Challenges a pending slash proposal, requiring a bond deposit
    /// @param proposalId The ID of the proposal to challenge
    function challenge(uint256 proposalId) external;

    /// @notice Casts a stake-weighted vote on a challenged proposal
    /// @param proposalId The ID of the proposal to vote on
    /// @param support True to vote in favor of slashing, false to vote against
    function vote(uint256 proposalId, bool support) external;

    /// @notice Executes a proposal after the challenge or voting period ends
    /// @param proposalId The ID of the proposal to execute
    function execute(uint256 proposalId) external;

    /// @notice Returns the full proposal data for a given proposal ID
    /// @param proposalId The ID of the proposal to query
    /// @return The SlashProposal struct
    function getProposal(uint256 proposalId) external view returns (SlashProposal memory);

    /// @notice Returns the current state of a proposal
    /// @param proposalId The ID of the proposal to query
    /// @return The current ProposalState
    function getProposalState(uint256 proposalId) external view returns (ProposalState);

    /// @notice Checks whether a voter has already voted on a proposal
    /// @param proposalId The ID of the proposal to check
    /// @param voter The address to check
    /// @return True if the voter has already voted
    function hasVoted(uint256 proposalId, address voter) external view returns (bool);

    /// @notice Returns the total number of proposals created
    /// @return The proposal count
    function proposalCount() external view returns (uint256);
}
