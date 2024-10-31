// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

interface IERC20 {
    function transfer(address recipient, uint256 amount) external returns (bool);
    function balanceOf(address account) external view returns (uint256);
}

contract FamilyDao {
    IERC20 public baseToken;

    struct Family {
        string name;
        address creator;
        string creatorName;
        address familyAddress;
        address[] members;
        mapping(address => bool) isParent;
        mapping(address => string) memberNames;
        uint256 creationDate;
        uint256 proposalCount;
        bool exists;
    }

    struct FamilyDetails {
        string name;
        address creator;
        string creatorName;
        address familyAddress;
        uint256 memberCount;
        uint256 proposalCount;
        uint256 creationDate;
    }

    struct Proposal {
        address proposer;
        string description;
        uint256 amount;
        address recipient;
        uint256 votesFor;
        uint256 votesAgainst;
        mapping(address => bool) hasVoted;
        bool executed;
    }

    struct SimplifiedProposal {
        address proposer;
        string description;
        uint256 amount;
        address recipient;
        uint256 votesFor;
        uint256 votesAgainst;
        bool executed;
    }

    mapping(uint256 => Family) public families;
    mapping(uint256 => Proposal[]) public familyProposals;
    mapping(address => uint256) public familyAddressToId;
    uint256 public familyCount;
    mapping(address => uint256[]) public userFamilies;

    event FamilyCreated(uint256 familyId, string name, address creator, string creatorName, address familyAddress);
    event MemberAdded(uint256 familyId, address member, string name);
    event MemberRemoved(uint256 familyId, address member);
    event ParentStatusChanged(uint256 familyId, address member, bool isParent);
    event ProposalCreated(uint256 familyId, uint256 proposalId, address proposer, string description, uint256 amount);
    event Voted(uint256 familyId, uint256 proposalId, address voter, bool inFavor);
    event ProposalExecuted(uint256 familyId, uint256 proposalId);
    event FamilyDeleted(uint256 familyId);

    /**
    * Network: AIAChain
    * Default Token Address: 0x5900343DD73367fEBC0dB13C6108D54f3d85832d
    **/
    constructor() {
        baseToken = IERC20(0x5900343DD73367fEBC0dB13C6108D54f3d85832d);
    }

    function createFamily(string memory _familyName, string memory _creatorName) external returns (address) {
        uint256 familyId = familyCount++;
        Family storage newFamily = families[familyId];
        newFamily.name = _familyName;
        newFamily.creator = msg.sender;
        newFamily.creatorName = _creatorName;
        newFamily.familyAddress = address(new FamilyWallet());
        newFamily.members.push(msg.sender);
        newFamily.isParent[msg.sender] = true;
        newFamily.memberNames[msg.sender] = _creatorName;
        newFamily.creationDate = block.timestamp;
        newFamily.exists = true;

        userFamilies[msg.sender].push(familyId);
        familyAddressToId[newFamily.familyAddress] = familyId;

        emit FamilyCreated(familyId, _familyName, msg.sender, _creatorName, newFamily.familyAddress);
        return newFamily.familyAddress;
    }

    function addMember(uint256 _familyId, address _member, string memory _name) external {
        Family storage family = families[_familyId];
        require(family.exists, "Family does not exist");
        require(family.isParent[msg.sender], "Only parents can add members");
        require(!isMember(_familyId, _member), "Already a member");

        family.members.push(_member);
        family.memberNames[_member] = _name;
        userFamilies[_member].push(_familyId);
        emit MemberAdded(_familyId, _member, _name);
    }

    function removeMember(uint256 _familyId, address _member) external {
        Family storage family = families[_familyId];
        require(family.exists, "Family does not exist");
        require(family.isParent[msg.sender], "Only parents can remove members");
        require(_member != family.creator, "Cannot remove the creator");

        for (uint i = 0; i < family.members.length; i++) {
            if (family.members[i] == _member) {
                family.members[i] = family.members[family.members.length - 1];
                family.members.pop();
                break;
            }
        }

        delete family.isParent[_member];
        delete family.memberNames[_member];

        for (uint i = 0; i < userFamilies[_member].length; i++) {
            if (userFamilies[_member][i] == _familyId) {
                userFamilies[_member][i] = userFamilies[_member][userFamilies[_member].length - 1];
                userFamilies[_member].pop();
                break;
            }
        }

        emit MemberRemoved(_familyId, _member);
    }

    function setParentStatus(uint256 _familyId, address _member, bool _isParent) external {
        Family storage family = families[_familyId];
        require(family.exists, "Family does not exist");
        require(family.isParent[msg.sender], "Only parents can change parent status");
        require(isMember(_familyId, _member), "Not a family member");

        family.isParent[_member] = _isParent;
        emit ParentStatusChanged(_familyId, _member, _isParent);
    }

    function createProposal(uint256 _familyId, string memory _description, uint256 _amount, address _recipient) external {
        require(isMember(_familyId, msg.sender), "Only members can create proposals");

        Family storage family = families[_familyId];
        Proposal storage newProposal = familyProposals[_familyId].push();
        newProposal.proposer = msg.sender;
        newProposal.description = _description;
        newProposal.amount = _amount;
        newProposal.recipient = _recipient;

        uint256 proposalId = familyProposals[_familyId].length - 1;
        family.proposalCount++;

        emit ProposalCreated(_familyId, proposalId, msg.sender, _description, _amount);
    }

    function vote(uint256 _familyId, uint256 _proposalId, bool _inFavor) external {
        require(isMember(_familyId, msg.sender), "Only members can vote");
        Proposal storage proposal = familyProposals[_familyId][_proposalId];
        require(!proposal.hasVoted[msg.sender], "Already voted");

        proposal.hasVoted[msg.sender] = true;
        if (_inFavor) {
            proposal.votesFor++;
        } else {
            proposal.votesAgainst++;
        }

        emit Voted(_familyId, _proposalId, msg.sender, _inFavor);
    }

    function vetoProposal(uint256 _familyId, uint256 _proposalId) external {
        Family storage family = families[_familyId];
        Proposal storage proposal = familyProposals[_familyId][_proposalId];
        require(family.isParent[msg.sender], "Only parents can veto proposals");
        require(!proposal.executed, "Proposal already executed");

        proposal.executed = true;
        emit ProposalExecuted(_familyId, _proposalId);
    }

    function deleteFamily(uint256 _familyId) external {
        Family storage family = families[_familyId];
        require(family.exists, "Family does not exist");
        require(isMember(_familyId, msg.sender), "Only members can delete family");

        for (uint i = 0; i < family.members.length; i++) {
            address member = family.members[i];
            for (uint j = 0; j < userFamilies[member].length; j++) {
                if (userFamilies[member][j] == _familyId) {
                    userFamilies[member][j] = userFamilies[member][userFamilies[member].length - 1];
                    userFamilies[member].pop();
                    break;
                }
            }
        }

        delete families[_familyId];
        emit FamilyDeleted(_familyId);
    }

    function isMember(uint256 _familyId, address _member) public view returns (bool) {
        Family storage family = families[_familyId];
        for (uint i = 0; i < family.members.length; i++) {
            if (family.members[i] == _member) {
                return true;
            }
        }
        return false;
    }

    function getUserFamilies() external view returns (FamilyDetails[] memory) {
        uint256[] memory familyIds = userFamilies[msg.sender];
        FamilyDetails[] memory familyDetailsList = new FamilyDetails[](familyIds.length);

        for (uint i = 0; i < familyIds.length; i++) {
            Family storage family = families[familyIds[i]];
            familyDetailsList[i] = FamilyDetails({
                name: family.name,
                creator: family.creator,
                creatorName: family.creatorName,
                familyAddress: family.familyAddress,
                memberCount: family.members.length,
                proposalCount: family.proposalCount,
                creationDate: family.creationDate
            });
        }

        return familyDetailsList;
    }

    function getFamilyProposals(uint256 _familyId) external view returns (SimplifiedProposal[] memory) {
        // Check if the sender is a family member
        require(isMember(_familyId, msg.sender), "Not a family member");

        // Get the proposals for the family
        Proposal[] storage proposals = familyProposals[_familyId];

        // Create an array to hold the simplified proposals
        SimplifiedProposal[] memory simplifiedProposals = new SimplifiedProposal[](proposals.length);

        // Populate the simplified proposals array
        for (uint i = 0; i < proposals.length; i++) {
            Proposal storage proposal = proposals[i];
            simplifiedProposals[i] = SimplifiedProposal({
                proposer: proposal.proposer,
                description: proposal.description,
                amount: proposal.amount,
                recipient: proposal.recipient,
                votesFor: proposal.votesFor,
                votesAgainst: proposal.votesAgainst,
                executed: proposal.executed
            });
        }

        // Return the array of simplified proposals
        return simplifiedProposals;
    }

    function getFamilyMembers(uint256 _familyId) external view returns (address[] memory, string[] memory) {
        Family storage family = families[_familyId];
        require(family.exists, "Family does not exist");
        
        string[] memory names = new string[](family.members.length);
        for (uint i = 0; i < family.members.length; i++) {
            names[i] = family.memberNames[family.members[i]];
        }
        
        return (family.members, names);
    }
}

contract FamilyWallet {
    function execute(address _to, uint256 _value, bytes memory _data) external returns (bytes memory) {
        (bool success, bytes memory result) = _to.call{value: _value}(_data);
        require(success, "Transaction execution failed");
        return result;
    }

    receive() external payable {}
}