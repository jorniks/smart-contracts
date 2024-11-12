/** @type import('hardhat/config').HardhatUserConfig */
require("dotenv").config();
require("@nomicfoundation/hardhat-ethers");

const { DEPLOYING_WALLET_PRIVATE_KEY, NETWORK_RPC_URL } = process.env;

module.exports = {
  solidity: "0.8.27",
  defaultNetwork: "aiachain",
  networks: {
    hardhat: {},
    aiachain: {
      url: NETWORK_RPC_URL,
      chainId: 1320,
      accounts: [DEPLOYING_WALLET_PRIVATE_KEY],
    },
  },
};
