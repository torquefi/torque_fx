import { HardhatUserConfig } from "hardhat/config";
import "@nomiclabs/hardhat-ethers";
import "@nomiclabs/hardhat-etherscan";
import "dotenv/config";

const config: HardhatUserConfig = {
  solidity: "0.8.19",
  networks: {
    ethereum: {
      url: process.env.ETHEREUM_RPC_URL || "",
      accounts: [process.env.PRIVATE_KEY || ""],
    },
    arbitrum: {
      url: process.env.ARBITRUM_RPC_URL || "",
      accounts: [process.env.PRIVATE_KEY || ""],
    },
    // optimism: {
    //   url: process.env.OPTIMISM_RPC_URL || "",
    //   accounts: [process.env.PRIVATE_KEY || ""],
    // },
    // polygon: {
    //   url: process.env.POLYGON_RPC_URL || "",
    //   accounts: [process.env.PRIVATE_KEY || ""],
    // },
    // sonic: {
    //   url: process.env.SONIC_RPC_URL || "",
    //   accounts: [process.env.PRIVATE_KEY || ""],
    // },
    // base: {
    //   url: process.env.BASE_RPC_URL || "",
    //   accounts: [process.env.PRIVATE_KEY || ""],
    // },
    // sepolia: {
    //   url: process.env.SEPOLIA_RPC_URL || "",
    //   accounts: [process.env.PRIVATE_KEY || ""],
    // },
    // arbitrumSepolia: {
    //   url: process.env.ARBITRUM_SEPOLIA_RPC_URL || "",
    //   accounts: [process.env.PRIVATE_KEY || ""],
    // },
    // optimismSepolia: {
    //   url: process.env.OPTIMISM_SEPOLIA_RPC_URL || "",
    //   accounts: [process.env.PRIVATE_KEY || ""],
    // },
    // polygonMumbai: {
    //   url: process.env.POLYGON_MUMBAI_RPC_URL || "",
    //   accounts: [process.env.PRIVATE_KEY || ""],
    // },
    // sonicTestnet: {
    //   url: process.env.SONIC_TESTNET_RPC_URL || "",
    //   accounts: [process.env.PRIVATE_KEY || ""],
    // },
    // baseGoerli: {
    //   url: process.env.BASE_GOERLI_RPC_URL || "",
    //   accounts: [process.env.PRIVATE_KEY || ""],
    },
  },
  etherscan: {
    apiKey: {
      ethereum: process.env.ETHERSCAN_API_KEY,
      arbitrum: process.env.ARBISCAN_API_KEY,
    }
  },
  layerzero: {
    ethereum: {
      endpoint: process.env.ETHEREUM_LZ_ENDPOINT || "",
    },
    arbitrum: {
      endpoint: process.env.ARBITRUM_LZ_ENDPOINT || "",
    },
    optimism: {
      endpoint: process.env.OPTIMISM_LZ_ENDPOINT || "",
    },
    polygon: {
      endpoint: process.env.POLYGON_LZ_ENDPOINT || "",
    },
    sonic: {
      endpoint: process.env.SONIC_LZ_ENDPOINT || "",
    },
    base: {
      endpoint: process.env.BASE_LZ_ENDPOINT || "",
    },
  },
};

export default config;
