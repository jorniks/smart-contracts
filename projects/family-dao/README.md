# Family DAO

The family contract allows the deployment of a smart contract that allows the creation and management of a decentralized account for family funds. The contract allows users to add other family members with roles mapped to each member as either a parent or a child.

### PROCESS FLOW
1. Connect wallet
2. Create a family. Params = family name and creator's name
3. Fund family wallet
4. Add family members
5. Create expenditure proposals for other family members to vote
6. Parents can veto a proposal before the proposal duration to either approve or decline
7. If a proposal meets voting criteria, funds can be claimed to spend the wallet specified when creating the proposal.

## DEPLOYMENT USING HARDHAT
Clone the repository
```
  git clone https://github.com/jorniks/smart-contracts.git
```

Navigate to the family-dao folder
```
  cd smart-contracts/family-dao
```

Install dependencies using 
```
  npm install
```

Compile the project
```hardhat
  npx hardhat compile
```

Deploy
```
  npx hardhat run scripts/deploy-contract.js --network aiachain
```

**NOTE**: The default network for the deployment of this contract is the AIA Test Chain. To change this modify the `chainId` value specified in the `hardhat.config.js` file
