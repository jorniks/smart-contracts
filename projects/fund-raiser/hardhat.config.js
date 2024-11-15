/** @type import('hardhat/config').HardhatUserConfig */
require('dotenv').config();
require('@nomicfoundation/hardhat-ethers');
require("@nomicfoundation/hardhat-verify");

const { DEPLOYING_WALLET_PRIVATE_KEY, LINEASCAN_API_KEY } = process.env;

module.exports = {
  solidity: "0.8.27",
  defaultNetwork: "lineaSepolia",
  sourcify: {
    enabled: true,
  },
  networks: {
    hardhat: {},
    lineaSepolia: {
      url: "https://rpc.sepolia.linea.build",
      chainId: 59141,
      accounts: [DEPLOYING_WALLET_PRIVATE_KEY],
    },
  },
  etherscan: {
    apiKey: LINEASCAN_API_KEY,
    customChains: [
      {
        network: "linea_sepolia",
        chainId: 59141,
        urls: {
          apiURL: "https://api-sepolia.lineascan.build/api",
          browserURL: "https://sepolia.lineascan.build",
        },
      },
    ],
  },
};
