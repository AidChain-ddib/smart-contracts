require("@nomicfoundation/hardhat-toolbox");
require("dotenv").config();

const {
  HEDERA_TESTNET_ACCOUNT_ID,
  HEDERA_TESTNET_PRIVATE_KEY,
} = process.env;

module.exports = {
  solidity: {
    version: "0.8.19",
    settings: {
      optimizer: {
        enabled: true,
        runs: 200,
      },
    },
  },
  networks: {
    hedera_testnet: {
      url: "https://testnet.hashio.io/api",
      accounts: HEDERA_TESTNET_PRIVATE_KEY ? [HEDERA_TESTNET_PRIVATE_KEY] : [],
      chainId: 296,
      gasPrice: 10000000000,
      gas: 3000000,
    },
  },
  etherscan: {
    apiKey: {
      hedera_testnet: "test",
      hedera_mainnet: "test",
    },
    customChains: [
      {
        network: "hedera_testnet",
        chainId: 296,
        urls: {
          apiURL: "https://server-verify.hashscan.io",
          browserURL: "https://hashscan.io/testnet",
        },
      },
    ],
  },
};
