// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import "@openzeppelin/contracts/utils/Pausable.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

contract FundRaiser is Pausable, Ownable, ReentrancyGuard {

  struct Campaign {
    uint256 id;
    string title;
    string description;
    string imageLink;
    uint256 goal;
    uint256 endDate;
    uint256 createdAt;
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

  struct CampaignWithContributions {
    uint256 id;
    string title;
    string description;
    string imageLink;
    uint256 goal;
    uint256 endDate;
    uint256 createdAt;
    address creator;
    address preferredToken;
    uint256 totalRaised;
    bool isCancelled;
    bool isClaimed;
    Contribution[] contributions;
  }

  uint256 private campaignCounter;
  uint256 public platformFee; // in basis points (1% = 100)

  mapping(uint256 => Campaign) public campaigns;
  mapping(uint256 => Contribution[]) public campaignContributions;
  mapping(address => uint256[]) public userCampaigns;

  event CampaignCreated(uint256 indexed campaignId, address indexed creator, uint256 goal);
  event ContributionMade(uint256 indexed campaignId, address indexed contributor, uint256 amount);
  event CampaignCancelled(uint256 indexed campaignId);
  event FundsClaimed(uint256 indexed campaignId, uint256 amount);
  event ContributionWithdrawn(uint256 indexed campaignId, address indexed contributor, uint256 amount);
  event PlatformFeeUpdated(uint256 newFee);

  modifier onlyCampaignCreator(uint256 _campaignId) {
    require(campaigns[_campaignId].creator == msg.sender, "Not campaign creator");
    _;
  }

  modifier onlyValidCampaign(uint256 _campaignId) {
    require(_campaignId > 0 && _campaignId <= campaignCounter, "Campaign does not exist");
    require(!campaigns[_campaignId].isCancelled, "Campaign is cancelled");
    _;
  }

  constructor(uint256 _initialPlatformFee) Ownable(msg.sender) {
    require(_initialPlatformFee <= 1000, "Fee too high"); // Max 10%
    platformFee = _initialPlatformFee;
  }

  /*
  * CREATE FUND RAISING CAMPAIGN
  * @params
  * string memory title, string memory description, string memory imageLink, uint256 goal, uint256 endDate, address preferredToken
  */
  function createCampaign(
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

    campaignCounter++;
    uint256 campaignId = campaignCounter;

    Campaign storage newCampaign = campaigns[campaignId];

    newCampaign.id = campaignId;
    newCampaign.title = title;
    newCampaign.description = description;
    newCampaign.imageLink = imageLink;
    newCampaign.goal = goal;
    newCampaign.endDate = endDate;
    newCampaign.createdAt = block.timestamp;
    newCampaign.creator = msg.sender;
    newCampaign.preferredToken = preferredToken;
    newCampaign.totalRaised = 0;
    newCampaign.isCancelled = false;
    newCampaign.isClaimed = false;

    userCampaigns[msg.sender].push(campaignId);

    emit CampaignCreated(campaignId, msg.sender, goal);
    return campaignId;
  }

  /*
  * CANCEL CAMPAIGN
  * @params
  * uint256 _campaignId
  */
  function cancelCampaign(uint256 _campaignId) external onlyValidCampaign(_campaignId) whenNotPaused {
    Campaign storage campaign = campaigns[_campaignId];
    require(msg.sender == campaign.creator || msg.sender == owner(), "Not authorized");

    campaign.isCancelled = true;
    emit CampaignCancelled(_campaignId);
  }

  /*
  * CONTRIBUTE TO CAMPAIGN
  * @params
  * uint256 _campaignId, uint256 amount
  */
  function contribute(uint256 _campaignId, uint256 amount) external onlyValidCampaign(_campaignId) whenNotPaused {
    require(amount > 0, "Amount must be greater than 0");
    Campaign storage campaign = campaigns[_campaignId];
    require(block.timestamp <= campaign.endDate, "Campaign has ended");

    IERC20 token = IERC20(campaign.preferredToken);
    require(token.transferFrom(msg.sender, address(this), amount), "Transfer failed");

    campaign.totalRaised += amount;
    campaign.contributions[msg.sender] += amount;

    campaignContributions[_campaignId].push(Contribution({
      contributor: msg.sender,
      amount: amount,
      timestamp: block.timestamp
    }));

    emit ContributionMade(_campaignId, msg.sender, amount);
  }

  /*
  * CLAIM FUNDS RAISED
  * @params
  * uint256 _campaignId
  */
  function claimFunds(uint256 _campaignId) external onlyValidCampaign(_campaignId) onlyCampaignCreator(_campaignId) whenNotPaused nonReentrant {
    Campaign storage campaign = campaigns[_campaignId];
    require(!campaign.isClaimed, "Funds already claimed");
    require(block.timestamp > campaign.endDate, "Campaign still active");
    require(campaign.totalRaised >= campaign.goal, "Goal not reached");

    uint256 feeAmount = (campaign.totalRaised * platformFee) / 10000;
    uint256 creatorAmount = campaign.totalRaised - feeAmount;

    campaign.isClaimed = true;

    IERC20 token = IERC20(campaign.preferredToken);
    require(token.transfer(owner(), feeAmount), "Fee transfer failed");
    require(token.transfer(campaign.creator, creatorAmount), "Creator transfer failed");

    emit FundsClaimed(_campaignId, creatorAmount);
  }

  /*
  * WITHDRAW CONTRIBUTED FUND
  * @params
  * uint256 _campaignId
  */
  function withdrawContribution(uint256 _campaignId) external whenNotPaused nonReentrant {
    Campaign storage campaign = campaigns[_campaignId];
    uint256 contributedAmount = campaign.contributions[msg.sender];

    require(contributedAmount > 0, "No contribution found");
    require(campaign.isCancelled, "Campaign must be cancelled to withdraw");

    campaign.contributions[msg.sender] = 0;
    campaign.totalRaised -= contributedAmount;

    IERC20 token = IERC20(campaign.preferredToken);
    require(token.transfer(msg.sender, contributedAmount), "Transfer failed");

    emit ContributionWithdrawn(_campaignId, msg.sender, contributedAmount);
  }

  /*
  * GET CAMPAIGNS BY USER
  * @params address userAddress
  * returns all campaigns by a user
  */
  function getCampaignsByUser(address userAddress) external view returns (CampaignWithContributions[] memory) {
    uint256[] memory userCampaignIds = userCampaigns[userAddress];
    CampaignWithContributions[] memory userCampaignsList = new CampaignWithContributions[](userCampaignIds.length);

    for (uint256 i = 0; i < userCampaignIds.length; i++) {
      Campaign storage currentCampaign = campaigns[userCampaignIds[i]];
      Contribution[] memory currentContributions = campaignContributions[userCampaignIds[i]];

      userCampaignsList[i] = CampaignWithContributions({
        id: currentCampaign.id,
        title: currentCampaign.title,
        description: currentCampaign.description,
        imageLink: currentCampaign.imageLink,
        goal: currentCampaign.goal,
        endDate: currentCampaign.endDate,
        createdAt: currentCampaign.createdAt,
        creator: currentCampaign.creator,
        preferredToken: currentCampaign.preferredToken,
        totalRaised: currentCampaign.totalRaised,
        isCancelled: currentCampaign.isCancelled,
        isClaimed: currentCampaign.isClaimed,
        contributions: currentContributions
      });
    }

    return userCampaignsList;
  }

  /*
  * GET CAMPAIGN DETAILS
  * @params uint256 _campaignId
  * returns details of a campaign with an array of objects containing all the contributions
  */
  function getCampaignDetails(uint256 _campaignId) external view returns (CampaignWithContributions memory) {
    Campaign storage campaign = campaigns[_campaignId];
    Contribution[] memory contributions = campaignContributions[_campaignId];

    return CampaignWithContributions({
      id: campaign.id,
      title: campaign.title,
      description: campaign.description,
      imageLink: campaign.imageLink,
      goal: campaign.goal,
      endDate: campaign.endDate,
      createdAt: campaign.createdAt,
      creator: campaign.creator,
      preferredToken: campaign.preferredToken,
      totalRaised: campaign.totalRaised,
      isCancelled: campaign.isCancelled,
      isClaimed: campaign.isClaimed,
      contributions: contributions
    });
  }

  /*
  * GET ALL CREATED CAMPAIGNS
  * returns an array of all campaigns
  */
  function getAllCampaigns() external view returns (CampaignWithContributions[] memory) {
    CampaignWithContributions[] memory allCampaigns = new CampaignWithContributions[](campaignCounter);

    for (uint256 i = 1; i <= campaignCounter; i++) {
      Campaign storage currentCampaign = campaigns[i];
      Contribution[] memory currentContributions = campaignContributions[i];

      allCampaigns[i - 1] = CampaignWithContributions({
        id: currentCampaign.id,
        title: currentCampaign.title,
        description: currentCampaign.description,
        imageLink: currentCampaign.imageLink,
        goal: currentCampaign.goal,
        endDate: currentCampaign.endDate,
        createdAt: currentCampaign.createdAt,
        creator: currentCampaign.creator,
        preferredToken: currentCampaign.preferredToken,
        totalRaised: currentCampaign.totalRaised,
        isCancelled: currentCampaign.isCancelled,
        isClaimed: currentCampaign.isClaimed,
        contributions: currentContributions
      });
    }

    return allCampaigns;
  }

  /*
  * GET ALL ACTIVE CAMPAIGNS
  * returns an array of all active campaigns
  */
  function getActiveCampaigns() external view returns (CampaignWithContributions[] memory) {
    uint256 activeCount = 0;

    // First, count active campaigns
    for (uint256 i = 1; i <= campaignCounter; i++) {
      if (!campaigns[i].isCancelled && block.timestamp <= campaigns[i].endDate) {
        activeCount++;
      }
    }

    CampaignWithContributions[] memory activeCampaigns = new CampaignWithContributions[](activeCount);
    uint256 currentIndex = 0;

    // Then populate the array
    for (uint256 i = 1; i <= campaignCounter && currentIndex < activeCount; i++) {
      if (!campaigns[i].isCancelled && block.timestamp <= campaigns[i].endDate) {
        Campaign storage currentCampaign = campaigns[i];
        Contribution[] memory currentContributions = campaignContributions[i];

        activeCampaigns[currentIndex] = CampaignWithContributions({
          id: currentCampaign.id,
          title: currentCampaign.title,
          description: currentCampaign.description,
          imageLink: currentCampaign.imageLink,
          goal: currentCampaign.goal,
          endDate: currentCampaign.endDate,
          createdAt: currentCampaign.createdAt,
          creator: currentCampaign.creator,
          preferredToken: currentCampaign.preferredToken,
          totalRaised: currentCampaign.totalRaised,
          isCancelled: currentCampaign.isCancelled,
          isClaimed: currentCampaign.isClaimed,
          contributions: currentContributions
        });
        currentIndex++;
      }
    }

    return activeCampaigns;
  }

  /*
  * GET ALL ENDED CAMPAIGNS
  * returns an array of all ended campaigns
  */
  function getEndedCampaigns() external view returns (CampaignWithContributions[] memory) {
    uint256 endedCount = 0;

    // First, count ended campaigns
    for (uint256 i = 1; i <= campaignCounter; i++) {
      if (!campaigns[i].isCancelled && block.timestamp > campaigns[i].endDate) {
        endedCount++;
      }
    }

    CampaignWithContributions[] memory endedCampaigns = new CampaignWithContributions[](endedCount);
    uint256 currentIndex = 0;

    // Then populate the array
    for (uint256 i = 1; i <= campaignCounter && currentIndex < endedCount; i++) {
      if (!campaigns[i].isCancelled && block.timestamp > campaigns[i].endDate) {
        Campaign storage currentCampaign = campaigns[i];
        Contribution[] memory currentContributions = campaignContributions[i];

        endedCampaigns[currentIndex] = CampaignWithContributions({
          id: currentCampaign.id,
          title: currentCampaign.title,
          description: currentCampaign.description,
          imageLink: currentCampaign.imageLink,
          goal: currentCampaign.goal,
          endDate: currentCampaign.endDate,
          createdAt: currentCampaign.createdAt,
          creator: currentCampaign.creator,
          preferredToken: currentCampaign.preferredToken,
          totalRaised: currentCampaign.totalRaised,
          isCancelled: currentCampaign.isCancelled,
          isClaimed: currentCampaign.isClaimed,
          contributions: currentContributions
        });
        currentIndex++;
      }
    }

    return endedCampaigns;
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
    for (uint256 i = 1; i <= campaignCounter; i++) {
      if (!campaigns[i].isCancelled && campaigns[i].totalRaised >= campaigns[i].goal) {
        total += campaigns[i].totalRaised;
      }
    }

    return total;
  }
}