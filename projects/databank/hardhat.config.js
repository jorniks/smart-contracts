/** @type import('hardhat/config').HardhatUserConfig */
require("dotenv").config();
require("@nomicfoundation/hardhat-ethers");
require("@nomicfoundation/hardhat-verify");

const {
  DEPLOYING_WALLET_PRIVATE_KEY,
  NETWORKSCAN_API_KEY,
  RPC_URL,
  NETWORK_EXPLORER_URL,
  NETWORK_API_URL,
  CHAIN_ID,
  NETWORK_NAME,
} = process.env;

module.exports = {
  solidity: "0.8.28",
  defaultNetwork: NETWORK_NAME,
  sourcify: {
    enabled: true,
  },
  networks: {
    hardhat: {},
    [NETWORK_NAME]: {
      url: RPC_URL,
      chainId: Number(CHAIN_ID),
      accounts: [DEPLOYING_WALLET_PRIVATE_KEY],
    },
  },
  etherscan: {
    apiKey: NETWORKSCAN_API_KEY,
    customChains: [
      {
        network: NETWORK_NAME,
        chainId: Number(CHAIN_ID),
        urls: {
          apiURL: NETWORK_API_URL,
          browserURL: NETWORK_EXPLORER_URL,
        },
      },
    ],
  },
};
