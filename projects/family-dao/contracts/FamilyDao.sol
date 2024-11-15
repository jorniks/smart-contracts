// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

interface IERC20 {
    function transfer(address recipient, uint256 amount) external returns (bool);
    function balanceOf(address account) external view returns (uint256);
}

contract FamilyDao {
    IERC20 public baseToken;

    struct Member {
        string name;
        address addr;
        bool isParent;
    }

    struct Family {
        string name;
        address creator;
        string creatorName;
        address familyAddress;
        address[] memberAddresses;
        mapping(address => Member) members;
    }

    struct Proposal {
        address proposer;
        string title;
        string description;
        uint256 amount;
        address recipient;
        uint256 votesFor;
        uint256 votesAgainst;
        uint256 endDate;
        string status;
        mapping(address => bool) hasVoted;
    }

    struct FamilyView {
        uint256 familyId;
        string name;
        address creator;
        string creatorName;
        address familyAddress;
        uint256 walletBalance;
        Member[] memberList;
        ProposalView[] proposals;
    }

    struct ProposalView {
        address proposer;
        string title;
        string description;
        uint256 amount;
        address recipient;
        uint256 votesFor;
        uint256 votesAgainst;
        uint256 endDate;
        string status;
    }

    mapping(uint256 => Family) public families;
    mapping(uint256 => Proposal[]) public familyProposals;
    uint256 public familyCount;

    event FundsTransferred(
        uint256 indexed familyId,
        address indexed from,
        address indexed to,
        uint256 amount,
        string reason
    );
    event FamilyCreated(uint256 indexed familyId, string name, address creator);
    event MemberModified(uint256 indexed familyId, address member, bool isParent, bool added);
    event ProposalCreated(uint256 indexed familyId, uint256 proposalId);
    event ProposalVoted(
        uint256 indexed familyId,
        uint256 indexed proposalId,
        address indexed voter,
        bool inFavor,
        string action // "vote" or "veto"
    );
    event ProposalExecuted(uint256 indexed familyId, uint256 indexed proposalId);

    modifier onlyParent(uint256 _familyId) {
        require(families[_familyId].familyAddress != address(0), "Family does not exist");
        require(families[_familyId].members[msg.sender].isParent, "Only parents are allowed!");
        _;
    }

    modifier onlyMembers(uint256 _familyId) {
        require(families[_familyId].familyAddress != address(0), "Family does not exist");
        require(families[_familyId].members[msg.sender].addr != address(0), "Only family members are allowed");
        _;
    }

    modifier familyExists(uint256 _familyId) {
        require(families[_familyId].familyAddress != address(0), "Family does not exist");
        _;
    }

    constructor(address _tokenAddress) {
        require(_tokenAddress != address(0), "Invalid token address");
        baseToken = IERC20(_tokenAddress);
    }

    function createFamily(string memory _familyName, string memory _creatorName) external returns (address) {
        uint256 familyId = familyCount++;
        Family storage newFamily = families[familyId];
        newFamily.name = _familyName;
        newFamily.creator = msg.sender;
        newFamily.creatorName = _creatorName;
        newFamily.familyAddress = address(new FamilyWallet());

        // Add creator as parent
        newFamily.members[msg.sender] = Member({
            name: _creatorName,
            addr: msg.sender,
            isParent: true
        });
        newFamily.memberAddresses.push(msg.sender);

        emit FamilyCreated(familyId, _familyName, msg.sender);
        return newFamily.familyAddress;
    }

    function addMember(uint256 _familyId, string memory _name, address _member, bool _isParent) external onlyMembers(_familyId) {
        Family storage family = families[_familyId];
        require(family.members[_member].addr == address(0), "Already a member");
        require(_member != address(0), "Invalid member address");

        family.members[_member] = Member({
            name: _name,
            addr: _member,
            isParent: _isParent
        });
        family.memberAddresses.push(_member);

        emit MemberModified(_familyId, _member, _isParent, true);
    }

    function getUserFamilies() external view returns (FamilyView[] memory) {
        uint256 userFamilyCount = 0;
        for (uint256 i = 0; i < familyCount; i++) {
            if (families[i].members[msg.sender].addr != address(0)) {
                userFamilyCount++;
            }
        }

        FamilyView[] memory userFamilies = new FamilyView[](userFamilyCount);

        uint256 currentIndex = 0;
        for (uint256 i = 0; i < familyCount; i++) {
            if (families[i].members[msg.sender].addr != address(0)) {
                userFamilies[currentIndex] = getFamilyView(i);
                currentIndex++;
            }
        }

        return userFamilies;
    }

    function getFamilyView(uint256 _familyId) internal view returns (FamilyView memory) {
        Family storage family = families[_familyId];

        Member[] memory memberList = getFamilyMembers(_familyId);
        ProposalView[] memory proposalList = getFamilyProposals(_familyId);

        return FamilyView({
            familyId: _familyId,
            name: family.name,
            creator: family.creator,
            creatorName: family.creatorName,
            familyAddress: family.familyAddress,
            walletBalance: baseToken.balanceOf(family.familyAddress),
            memberList: memberList,
            proposals: proposalList
        });
    }

    function getFamilyMembers(uint256 _familyId) internal view returns (Member[] memory) {
        Family storage family = families[_familyId];
        Member[] memory memberList = new Member[](family.memberAddresses.length);

        for (uint256 i = 0; i < family.memberAddresses.length; i++) {
            address memberAddr = family.memberAddresses[i];
            memberList[i] = family.members[memberAddr];
        }

        return memberList;
    }

    function getFamilyProposals(uint256 _familyId) internal view returns (ProposalView[] memory) {
        Proposal[] storage proposals = familyProposals[_familyId];
        ProposalView[] memory proposalViews = new ProposalView[](proposals.length);

        for (uint256 i = 0; i < proposals.length; i++) {
            Proposal storage proposal = proposals[i];
            proposalViews[i] = ProposalView({
                proposer: proposal.proposer,
                title: proposal.title,
                description: proposal.description,
                amount: proposal.amount,
                recipient: proposal.recipient,
                votesFor: proposal.votesFor,
                votesAgainst: proposal.votesAgainst,
                endDate: proposal.endDate,
                status: proposal.status
            });
        }

        return proposalViews;
    }

    function getRequiredApprovalPercentage(uint256 _amount) public pure returns (uint256) {
        if (_amount <= 500) return 51;
        if (_amount <= 1500) return 75;
        return 100;
    }

    function createProposal(
        uint256 _familyId,
        string calldata _title,
        string calldata _description,
        uint256 _amount,
        address _recipient,
        uint256 _duration
    ) external familyExists(_familyId) onlyMembers(_familyId) {
        Proposal storage newProposal = familyProposals[_familyId].push();
        newProposal.proposer = msg.sender;
        newProposal.title = _title;
        newProposal.description = _description;
        newProposal.amount = _amount;
        newProposal.recipient = _recipient;
        newProposal.endDate = block.timestamp + _duration;
        newProposal.status = "pending";

        emit ProposalCreated(_familyId, familyProposals[_familyId].length - 1);
    }

    function vote(uint256 _familyId, uint256 _proposalId, bool _inFavor) external familyExists(_familyId) onlyMembers(_familyId) {
        Proposal storage proposal = familyProposals[_familyId][_proposalId];
        require(!proposal.hasVoted[msg.sender], "You have already voted on this proposal");
        require(block.timestamp < proposal.endDate, "Voting period has ended");
        require(bytes(proposal.status).length == 0 || keccak256(bytes(proposal.status)) == keccak256(bytes("pending")), "Proposal is not in pending status");

        proposal.hasVoted[msg.sender] = true;
        if (_inFavor) {
            proposal.votesFor++;
        } else {
            proposal.votesAgainst++;
        }

        emit ProposalVoted(_familyId, _proposalId, msg.sender, _inFavor, "vote");
    }

    function vetoProposal(uint256 _familyId, uint256 _proposalId, string memory _status) external onlyParent(_familyId) {
        Family storage family = families[_familyId];
        require(_proposalId < familyProposals[_familyId].length, "Proposal does not exist");

        Proposal storage proposal = familyProposals[_familyId][_proposalId];
        require(bytes(proposal.status).length == 0 || keccak256(bytes(proposal.status)) == keccak256(bytes("pending")), "Proposal is not in pending status");
        require(block.timestamp < proposal.endDate, "Proposal period has ended");
        require(!(proposal.proposer == msg.sender && family.memberAddresses.length > 1), "Cannot veto your own proposal when there are other family members");

        proposal.status = _status;
        proposal.endDate = block.timestamp;

        emit ProposalVoted(_familyId, _proposalId, msg.sender, false, "veto");
    }

    function claimFunds(uint256 _familyId, uint256 _proposalId) external onlyMembers(_familyId) {
        Family storage family = families[_familyId];
        Proposal storage proposal = familyProposals[_familyId][_proposalId];

        require(bytes(proposal.status).length == 0 || keccak256(bytes(proposal.status)) != keccak256(bytes("withdrawn")), "Funds already withdrawn!");

        bool canClaim = (block.timestamp >= proposal.endDate &&
            bytes(proposal.status).length > 0 && keccak256(bytes(proposal.status)) == keccak256(bytes("pending"))) ||
            (bytes(proposal.status).length > 0 && keccak256(bytes(proposal.status)) == keccak256(bytes("approved")));

        require(canClaim, "Cannot withdraw funds yet");

        if (bytes(proposal.status).length > 0 && keccak256(bytes(proposal.status)) == keccak256(bytes("pending"))) {
            uint256 totalMembers = family.memberAddresses.length;
            uint256 approvalPercentage = (proposal.votesFor * 100) / totalMembers;
            uint256 requiredPercentage = getRequiredApprovalPercentage(proposal.amount);
            require(approvalPercentage >= requiredPercentage, "Insufficient votes");
            proposal.status = "approved";
        }

        uint256 balance = baseToken.balanceOf(family.familyAddress);
        require(balance >= proposal.amount, "Insufficient funds in family wallet!");

        proposal.status = "withdrawn";

        FamilyWallet(payable(family.familyAddress)).execute(
            address(baseToken),
            0,
            abi.encodeWithSignature(
                "transfer(address,uint256)",
                proposal.recipient,
                proposal.amount
            )
        );

        emit ProposalExecuted(_familyId, _proposalId);
        emit FundsTransferred(
            _familyId,
            family.familyAddress,
            proposal.recipient,
            proposal.amount,
            "Proposal execution"
        );
    }

    function removeMember(uint256 _familyId, address _member) external onlyParent(_familyId) familyExists(_familyId) {
      Family storage family = families[_familyId];
      require(family.members[_member].addr != address(0), "Member does not exist");
      require(_member != msg.sender, "You cannot remove yourself");

      // Remove member from mapping
      delete family.members[_member];

      // Find and remove member from the memberAddresses array
      uint256 length = family.memberAddresses.length;
      for (uint256 i = 0; i < length; i++) {
          if (family.memberAddresses[i] == _member) {
              family.memberAddresses[i] = family.memberAddresses[length - 1]; // Move last member to the current index
              family.memberAddresses.pop(); // Remove the last element
              break;
          }
      }

      emit MemberModified(_familyId, _member, false, false); // Emit event with added=false
  }
}

contract FamilyWallet {
    function execute(
        address _to,
        uint256 _value,
        bytes memory _data
    ) external returns (bytes memory) {
        (bool success, bytes memory result) = _to.call{value: _value}(_data);
        require(success, "Transaction execution failed");
        return result;
    }

    receive() external payable {}
}