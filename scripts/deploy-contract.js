const { ethers } = require("hardhat");

async function main() {
  const DaoContract = await ethers.getContractFactory("FamilyDao");
  const myContract = await (await DaoContract.deploy()).getAddress()
  console.log(`Contract deployed to address: ${myContract}`);
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  })