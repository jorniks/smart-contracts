// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import "@openzeppelin/contracts/utils/Pausable.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

contract FundRaiser is Pausable, Ownable, ReentrancyGuard {

  struct Proposal {
    uint256 id;
    string title;
    string description;
    string imageLink;
    uint256 goal;
    uint256 endDate;
    address creator;
    address preferredToken;
    uint256 totalRaised;
    bool isCancelled;
    bool isClaimed;
    mapping(address => uint256) contributions;
  }

  struct Contribution {
    address contributor;
    uint256 amount;
    uint256 timestamp;
  }

  struct ProposalWithContributions {
    uint256 id;
    string title;
    string description;
    string imageLink;
    uint256 goal;
    uint256 endDate;
    address creator;
    address preferredToken;
    uint256 totalRaised;
    bool isCancelled;
    bool isClaimed;
    Contribution[] contributions;
  }

  uint256 private proposalCounter;
  uint256 public platformFee; // in basis points (1% = 100)

  mapping(uint256 => Proposal) public proposals;
  mapping(uint256 => Contribution[]) public proposalContributions;
  mapping(address => uint256[]) public userProposals;

  event ProposalCreated(uint256 indexed proposalId, address indexed creator, uint256 goal);
  event ContributionMade(uint256 indexed proposalId, address indexed contributor, uint256 amount);
  event ProposalCancelled(uint256 indexed proposalId);
  event FundsClaimed(uint256 indexed proposalId, uint256 amount);
  event ContributionWithdrawn(uint256 indexed proposalId, address indexed contributor, uint256 amount);
  event PlatformFeeUpdated(uint256 newFee);

  modifier onlyProposalCreator(uint256 _proposalId) {
    require(proposals[_proposalId].creator == msg.sender, "Not proposal creator");
    _;
  }

  modifier onlyValidProposal(uint256 _proposalId) {
    require(_proposalId > 0 && _proposalId <= proposalCounter, "Proposal does not exist");
    require(!proposals[_proposalId].isCancelled, "Proposal is cancelled");
    _;
  }

  constructor(uint256 _initialPlatformFee) Ownable(msg.sender) {
    require(_initialPlatformFee <= 1000, "Fee too high"); // Max 10%
    platformFee = _initialPlatformFee;
  }

  /*
  * CREATE FUND RAISING PROPOSAL
  * @params
  * string memory title, string memory description, string memory imageLink, uint256 goal, uint256 endDate, address preferredToken
  */
  function createProposal(
    string memory title,
    string memory description,
    string memory imageLink,
    uint256 goal,
    uint256 endDate,
    address preferredToken
  ) external whenNotPaused returns (uint256) {
    require(endDate > block.timestamp, "End date must be in future");
    require(goal > 0, "Goal must be greater than 0");
    require(preferredToken != address(0), "Token address cannot be zero");

    // Verify the token address is a contract
    uint256 size;
    assembly {
      size := extcodesize(preferredToken)
    }
    require(size > 0, "Token address must be a contract");

    proposalCounter++;
    uint256 proposalId = proposalCounter;

    Proposal storage newProposal = proposals[proposalId];

    newProposal.id = proposalId;
    newProposal.title = title;
    newProposal.description = description;
    newProposal.imageLink = imageLink;
    newProposal.goal = goal;
    newProposal.endDate = endDate;
    newProposal.creator = msg.sender;
    newProposal.preferredToken = preferredToken;
    newProposal.totalRaised = 0;
    newProposal.isCancelled = false;
    newProposal.isClaimed = false;

    userProposals[msg.sender].push(proposalId);

    emit ProposalCreated(proposalId, msg.sender, goal);
    return proposalId;
  }

  /*
  * CANCEL PROPOSAL
  * @params
  * uint256 _proposalId
  */
  function cancelProposal(uint256 _proposalId) external onlyValidProposal(_proposalId) whenNotPaused {
    Proposal storage proposal = proposals[_proposalId];
    require(msg.sender == proposal.creator || msg.sender == owner(), "Not authorized");

    proposal.isCancelled = true;
    emit ProposalCancelled(_proposalId);
  }

  /*
  * CONTRIBUTE TO PROPOSAL
  * @params
  * uint256 _proposalId, uint256 amount
  */
  function contribute(uint256 _proposalId, uint256 amount) external onlyValidProposal(_proposalId) whenNotPaused {
    require(amount > 0, "Amount must be greater than 0");
    Proposal storage proposal = proposals[_proposalId];
    require(block.timestamp <= proposal.endDate, "Proposal has ended");

    IERC20 token = IERC20(proposal.preferredToken);
    require(token.transferFrom(msg.sender, address(this), amount), "Transfer failed");

    proposal.totalRaised += amount;
    proposal.contributions[msg.sender] += amount;

    proposalContributions[_proposalId].push(Contribution({
      contributor: msg.sender,
      amount: amount,
      timestamp: block.timestamp
    }));

    emit ContributionMade(_proposalId, msg.sender, amount);
  }

  /*
  * CLAIM FUNDS RAISED
  * @params
  * uint256 _proposalId
  */
  function claimFunds(uint256 _proposalId) external onlyValidProposal(_proposalId) onlyProposalCreator(_proposalId) whenNotPaused nonReentrant {
    Proposal storage proposal = proposals[_proposalId];
    require(!proposal.isClaimed, "Funds already claimed");
    require(block.timestamp > proposal.endDate, "Proposal still active");
    require(proposal.totalRaised >= proposal.goal, "Goal not reached");

    uint256 feeAmount = (proposal.totalRaised * platformFee) / 10000;
    uint256 creatorAmount = proposal.totalRaised - feeAmount;

    proposal.isClaimed = true;

    IERC20 token = IERC20(proposal.preferredToken);
    require(token.transfer(owner(), feeAmount), "Fee transfer failed");
    require(token.transfer(proposal.creator, creatorAmount), "Creator transfer failed");

    emit FundsClaimed(_proposalId, creatorAmount);
  }

  /*
  * WITHDRAW CONTRIBUTED FUND
  * @params
  * uint256 _proposalId
  */
  function withdrawContribution(uint256 _proposalId) external onlyValidProposal(_proposalId) whenNotPaused nonReentrant {
    Proposal storage proposal = proposals[_proposalId];
    uint256 contributedAmount = proposal.contributions[msg.sender];

    require(contributedAmount > 0, "No contribution found");
    require(
      proposal.isCancelled ||
      (block.timestamp > proposal.endDate && proposal.totalRaised < proposal.goal),
      "Cannot withdraw"
    );

    proposal.totalRaised -= contributedAmount;

    IERC20 token = IERC20(proposal.preferredToken);
    require(token.transfer(msg.sender, contributedAmount), "Transfer failed");

    emit ContributionWithdrawn(_proposalId, msg.sender, contributedAmount);
  }

  /*
  * GET PROPOSALS BY USER
  * @params address userAddress
  * returns all proposals by a user
  */
  function getProposalsByUser(address userAddress) external view returns (uint256[] memory) {
    return userProposals[userAddress];
  }

  /*
  * GET PROPOSAL DETAILS
  * @params uint256 _proposalId
  * returns details of a proposal with an array of objects containing all the contributions
  */
  function getProposalDetails(uint256 _proposalId) external view onlyValidProposal(_proposalId) returns (ProposalWithContributions memory) {
    Proposal storage proposal = proposals[_proposalId];
    Contribution[] memory contributions = proposalContributions[_proposalId];

    return ProposalWithContributions({
      id: proposal.id,
      title: proposal.title,
      description: proposal.description,
      imageLink: proposal.imageLink,
      goal: proposal.goal,
      endDate: proposal.endDate,
      creator: proposal.creator,
      preferredToken: proposal.preferredToken,
      totalRaised: proposal.totalRaised,
      isCancelled: proposal.isCancelled,
      isClaimed: proposal.isClaimed,
      contributions: contributions
    });
  }

  /*
  * GET ALL CREATED PROPOSALS
  * returns an array of all proposals
  */
  function getAllProposals() external view returns (ProposalWithContributions[] memory) {
    ProposalWithContributions[] memory allProposals = new ProposalWithContributions[](proposalCounter);

    for (uint256 i = 1; i <= proposalCounter; i++) {
      Proposal storage currentProposal = proposals[i];
      Contribution[] memory currentContributions = proposalContributions[i];

      allProposals[i - 1] = ProposalWithContributions({
        id: currentProposal.id,
        title: currentProposal.title,
        description: currentProposal.description,
        imageLink: currentProposal.imageLink,
        goal: currentProposal.goal,
        endDate: currentProposal.endDate,
        creator: currentProposal.creator,
        preferredToken: currentProposal.preferredToken,
        totalRaised: currentProposal.totalRaised,
        isCancelled: currentProposal.isCancelled,
        isClaimed: currentProposal.isClaimed,
        contributions: currentContributions
      });
    }

    return allProposals;
  }

  /* contract creator function
  * PAUSE CONTRACT
  */
  function pause() external onlyOwner {
    _pause();
  }

  /* contract creator function
  * UNPAUSE CONTRACT
  */
  function unpause() external onlyOwner {
    _unpause();
  }

  /* contract creator function
  * UPDATE PLATFORM FEE
  */
  function updatePlatformFee(uint256 _newFee) external onlyOwner {
    require(_newFee <= 1000, "Fee too high"); // Max 10%
    platformFee = _newFee;

    emit PlatformFeeUpdated(_newFee);
  }

  /*
  * GET TOTAL FUNDS RAISED
  * returns uint256
  */
  function getTotalFundsRaised() external view returns (uint256) {
    uint256 total = 0;
    for (uint256 i = 1; i <= proposalCounter; i++) {
      if (!proposals[i].isCancelled && proposals[i].totalRaised >= proposals[i].goal) {
        total += proposals[i].totalRaised;
      }
    }

    return total;
  }

  /*
  * GET NUMBER OF SUCCESSFUL PROPOSALS
  * returns uint256
  */
  function getSuccessfulProposalsCount() external view returns (uint256) {
    uint256 count = 0;
    for (uint256 i = 1; i <= proposalCounter; i++) {
      if (!proposals[i].isCancelled &&
        proposals[i].totalRaised >= proposals[i].goal &&
        block.timestamp > proposals[i].endDate) {
        count++;
      }
    }

    return count;
  }

  /*
  * GET NUMBER OF ACTIVE PROPOSALS
  * returns uint256
  */
  function getActiveProposalsCount() external view returns (uint256) {
    uint256 count = 0;
    for (uint256 i = 1; i <= proposalCounter; i++) {
      if (!proposals[i].isCancelled &&
        block.timestamp <= proposals[i].endDate) {
        count++;
      }
    }

    return count;
  }

  /*
  * GET TOTAL AMOUNT USER CONTRIBUTED TO A PROPOSAL
  * @params uint256 proposalId, address contributor
  */
  function getUserContribution(uint256 _proposalId, address contributor) external view onlyValidProposal(_proposalId) returns (uint256) {
    return proposals[_proposalId].contributions[contributor];
  }
}