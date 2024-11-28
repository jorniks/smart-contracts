const { ethers } = require("hardhat");

const main = async () => {
  console.log("Starting contract deployment process");
  const usdcContract = await ethers.getContractFactory("USDC");
  const usdtContract = await ethers.getContractFactory("USDT");
  console.log("Retrieved contract files...");
  console.log("_______________________________________________________________________________________");
  console.log("Deploying contracts...");
  const deployedUSDCContract = await (await usdcContract.deploy()).getAddress();
  const deployedUSDTContract = await (await usdtContract.deploy()).getAddress();
  console.log(`USDC Contract deployed to address ${deployedUSDCContract}`);
  console.log(`USDT Contract deployed to address ${deployedUSDTContract}`);
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.log(error);
    process.exit(1);
  })