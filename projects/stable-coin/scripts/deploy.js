const { ethers } = require("hardhat");

const main = async () => {
  console.log("Starting contract deployment process");
  const contract = await ethers.getContractFactory("StableCoin");
  console.log("Retrieved contract file...");
  console.log("_______________________________________________________________________________________");
  console.log("Deploying contract...");
  const deployedContract = await (await contract.deploy()).getAddress();
  console.log(`Contract deployed to address ${deployedContract}`);

}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.log(error);
    process.exit(1);
  })