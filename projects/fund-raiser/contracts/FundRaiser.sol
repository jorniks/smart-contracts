// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import "@openzeppelin/contracts/utils/Pausable.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";

contract FundRaiser is Pausable, Ownable, ReentrancyGuard {
  enum CampaignStatus { Active, Ended, Cancelled, Claimed }

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
    uint8 tokenDecimals;
    uint256 totalRaised;
    CampaignStatus status;
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
    uint8 tokenDecimals;
    uint256 totalRaised;
    CampaignStatus status;
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
    require(campaigns[_campaignId].status == CampaignStatus.Active, "Campaign not active");
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
    require(bytes(title).length > 0 && bytes(title).length <= 100, "Invalid title length");
    require(bytes(description).length <= 1000, "Description too long");
    require(endDate <= block.timestamp + 365 days, "Campaign duration too long");
    require(endDate > block.timestamp, "End date must be in future");
    require(goal > 0, "Goal must be greater than 0");
    require(preferredToken != address(0), "Token address cannot be zero");

    // Verify the token address is a contract
    uint256 size;
    assembly {
      size := extcodesize(preferredToken)
    }
    require(size > 0, "Token address must be a contract");

    uint8 decimals = getTokenDecimals(preferredToken);
    uint256 adjustedGoal = denormalizeAmount(goal, decimals);  // Convert to token's decimal places

    campaignCounter++;
    uint256 campaignId = campaignCounter;

    Campaign storage newCampaign = campaigns[campaignId];

    newCampaign.id = campaignId;
    newCampaign.title = title;
    newCampaign.description = description;
    newCampaign.imageLink = imageLink;
    newCampaign.goal = adjustedGoal;
    newCampaign.endDate = endDate;
    newCampaign.createdAt = block.timestamp;
    newCampaign.creator = msg.sender;
    newCampaign.preferredToken = preferredToken;
    newCampaign.tokenDecimals = decimals;
    newCampaign.totalRaised = 0;
    newCampaign.status = CampaignStatus.Active;

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
    require(campaign.status != CampaignStatus.Cancelled, "Campaign is already cancelled");

    // Transfer back all contributions
    IERC20 token = IERC20(campaign.preferredToken);
    Contribution[] memory contributions = campaignContributions[_campaignId];

    for(uint256 i = 0; i < contributions.length; i++) {
      address contributor = contributions[i].contributor;
      uint256 contributionAmount = campaign.contributions[contributor];

      if (contributionAmount > 0) {
        campaign.contributions[contributor] = 0;
        require(token.transfer(contributor, contributionAmount), "Transfer failed");
      }
    }

    campaign.status = CampaignStatus.Cancelled;

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

    // Check if goal is reached and update status
    if (campaign.totalRaised >= campaign.goal && campaign.status == CampaignStatus.Active) {
      campaign.status = CampaignStatus.Ended;
    }

    emit ContributionMade(_campaignId, msg.sender, amount);
  }

  /*
  * CLAIM FUNDS RAISED
  * @params
  * uint256 _campaignId
  */
  function claimFunds(uint256 _campaignId) external onlyValidCampaign(_campaignId) onlyCampaignCreator(_campaignId) whenNotPaused nonReentrant {
    Campaign storage campaign = campaigns[_campaignId];
    require(
      (campaign.totalRaised >= campaign.goal && block.timestamp <= campaign.endDate) ||
      block.timestamp > campaign.endDate,
      "Cannot claim funds yet"
    );
    require(campaign.status != CampaignStatus.Claimed, "Campaign already claimed");

    uint256 feeAmount = (campaign.totalRaised * platformFee) / 10000;
    uint256 creatorAmount = campaign.totalRaised - feeAmount;

    IERC20 token = IERC20(campaign.preferredToken);
    require(token.transfer(campaign.creator, creatorAmount), "Creator transfer failed");
    require(token.transfer(owner(), feeAmount), "Fee transfer failed");

    campaign.status = CampaignStatus.Claimed;

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
    require(campaign.status == CampaignStatus.Cancelled, "Campaign must be cancelled to withdraw");

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

      // Normalize amounts for UI
      uint256 normalizedGoal = normalizeAmount(currentCampaign.goal, currentCampaign.tokenDecimals);
      uint256 normalizedTotalRaised = normalizeAmount(currentCampaign.totalRaised, currentCampaign.tokenDecimals);

      Contribution[] memory normalizedContributions = new Contribution[](currentContributions.length);
      for(uint j = 0; j < currentContributions.length; j++) {
        normalizedContributions[j] = Contribution({
          contributor: currentContributions[j].contributor,
          amount: normalizeAmount(currentContributions[j].amount, currentCampaign.tokenDecimals),
          timestamp: currentContributions[j].timestamp
        });
      }

      userCampaignsList[i] = CampaignWithContributions({
        id: currentCampaign.id,
        title: currentCampaign.title,
        description: currentCampaign.description,
        imageLink: currentCampaign.imageLink,
        goal: normalizedGoal,
        endDate: currentCampaign.endDate,
        createdAt: currentCampaign.createdAt,
        creator: currentCampaign.creator,
        preferredToken: currentCampaign.preferredToken,
        tokenDecimals: currentCampaign.tokenDecimals,
        totalRaised: normalizedTotalRaised,
        status: currentCampaign.status,
        contributions: normalizedContributions
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

    // Normalize amounts for UI
    uint256 normalizedGoal = normalizeAmount(campaign.goal, campaign.tokenDecimals);
    uint256 normalizedTotalRaised = normalizeAmount(campaign.totalRaised, campaign.tokenDecimals);

    Contribution[] memory normalizedContributions = new Contribution[](contributions.length);
    for(uint i = 0; i < contributions.length; i++) {
      normalizedContributions[i] = Contribution({
        contributor: contributions[i].contributor,
        amount: normalizeAmount(contributions[i].amount, campaign.tokenDecimals),
        timestamp: contributions[i].timestamp
      });
    }

    return CampaignWithContributions({
      id: campaign.id,
      title: campaign.title,
      description: campaign.description,
      imageLink: campaign.imageLink,
      goal: normalizedGoal,
      endDate: campaign.endDate,
      createdAt: campaign.createdAt,
      creator: campaign.creator,
      preferredToken: campaign.preferredToken,
      tokenDecimals: campaign.tokenDecimals,
      totalRaised: normalizedTotalRaised,
      status: campaign.status,
      contributions: normalizedContributions
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

      // Normalize amounts for UI
      uint256 normalizedGoal = normalizeAmount(currentCampaign.goal, currentCampaign.tokenDecimals);
      uint256 normalizedTotalRaised = normalizeAmount(currentCampaign.totalRaised, currentCampaign.tokenDecimals);

      Contribution[] memory normalizedContributions = new Contribution[](currentContributions.length);
      for(uint j = 0; j < currentContributions.length; j++) {
        normalizedContributions[j] = Contribution({
          contributor: currentContributions[j].contributor,
          amount: normalizeAmount(currentContributions[j].amount, currentCampaign.tokenDecimals),
          timestamp: currentContributions[j].timestamp
        });
      }

      allCampaigns[i - 1] = CampaignWithContributions({
        id: currentCampaign.id,
        title: currentCampaign.title,
        description: currentCampaign.description,
        imageLink: currentCampaign.imageLink,
        goal: normalizedGoal,
        endDate: currentCampaign.endDate,
        createdAt: currentCampaign.createdAt,
        creator: currentCampaign.creator,
        preferredToken: currentCampaign.preferredToken,
        tokenDecimals: currentCampaign.tokenDecimals,
        totalRaised: normalizedTotalRaised,
        status: currentCampaign.status,
        contributions: normalizedContributions
      });
    }

    return allCampaigns;
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
  * GET PREFERRED TOKEN DECIMAL
  * returns token decimal
  */
  function getTokenDecimals(address tokenAddress) internal view returns (uint8) {
    return IERC20Metadata(tokenAddress).decimals();
  }

  /*
  * SETS AMOUNT BACK TO IT'S ORIGINAL DECIMAL
  * returns original amount
  */
  function normalizeAmount(uint256 amount, uint8 decimals) internal pure returns (uint256) {
    return amount / (10 ** decimals);
  }

  /*
  * SETS AMOUNT TO A UNIFIED DECIMAL FOR STORAGE ON CONTRACT IRRESPECTIVE OF TOKEN DECIMAL
  * returns decimalized amount
  */
  function denormalizeAmount(uint256 amount, uint8 decimals) internal pure returns (uint256) {
    return amount * (10 ** decimals);
  }
}