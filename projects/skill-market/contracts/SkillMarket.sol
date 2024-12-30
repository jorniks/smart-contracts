// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

contract SkillMarket {
  struct Skill {
    uint256 id;
    address creator;
    string title;
    string description;
    string image;
    uint256 price;
    string profileURL;
    bool exists;
  }

  struct Profile {
    string profileURL;
    bool isSet;
  }


  mapping(uint256 => Skill) private skills;
  mapping(address => Profile) private profiles;
  mapping(address => uint256[]) private userSkills;
  uint256 private nextSkillId;


  event SkillCreated(uint256 indexed skillId, address indexed creator, string title, uint256 price);
  event SkillPurchased(uint256 indexed skillId, address indexed buyer, address indexed seller, uint256 price);
  event ProfileSet(address indexed user, string profileURL);


  error SkillNotFound();
  error InvalidPrice();
  error ProfileNotSet();
  error InsufficientPayment();

  function createSkill(string memory title, string memory description, string memory image, uint256 price) external returns (uint256) {
    if (!profiles[msg.sender].isSet) revert ProfileNotSet();
    if (price == 0) revert InvalidPrice();

    uint256 skillId = nextSkillId++;

    skills[skillId] = Skill({
      id: skillId,
      creator: msg.sender,
      title: title,
      description: description,
      image: image,
      price: price,
      profileURL: profiles[msg.sender].profileURL,
      exists: true
    });

    userSkills[msg.sender].push(skillId);

    emit SkillCreated(skillId, msg.sender, title, price);
    return skillId;
  }

  function listSkills() external view returns (uint256[] memory) {
    uint256[] memory allSkills = new uint256[](nextSkillId);
    uint256 validSkillCount = 0;

    for (uint256 i = 0; i < nextSkillId; i++) {
      if (skills[i].exists) {
        allSkills[validSkillCount] = i;
        validSkillCount++;
      }
    }


    uint256[] memory result = new uint256[](validSkillCount);
    for (uint256 i = 0; i < validSkillCount; i++) {
      result[i] = allSkills[i];
    }

    return result;
  }

  function purchaseSkill(uint256 skillId) external payable {
    Skill storage skill = skills[skillId];
    if (!skill.exists) revert SkillNotFound();
    if (msg.value < skill.price) revert InsufficientPayment();


    (bool sent, ) = skill.creator.call{value: msg.value}("");
    require(sent, "Failed to send payment");

    userSkills[msg.sender].push(skillId);

    emit SkillPurchased(skillId, msg.sender, skill.creator, msg.value);
  }

  function setProfile(string memory profileURL) external {
    profiles[msg.sender] = Profile({
      profileURL: profileURL,
      isSet: true
    });

    emit ProfileSet(msg.sender, profileURL);
  }

  function getSkillInfo(uint256 skillId) external view returns (
    address creator,
    string memory title,
    string memory description,
    string memory image,
    uint256 price,
    string memory profileURL
  ) {
    Skill storage skill = skills[skillId];
    if (!skill.exists) revert SkillNotFound();

    return (
      skill.creator,
      skill.title,
      skill.description,
      skill.image,
      skill.price,
      skill.profileURL
    );
  }

  function listSkillsByUser(address user) external view returns (uint256[] memory) {
    return userSkills[user];
  }

  function isProfileSet(address user) external view returns (bool) {
    return profiles[user].isSet;
  }


  function getProfileURL(address user) external view returns (string memory) {
    if (!profiles[user].isSet) revert ProfileNotSet();
    return profiles[user].profileURL;
  }
}
