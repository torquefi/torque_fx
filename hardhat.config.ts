import { HardhatUserConfig } from "hardhat/config";
import "@nomicfoundation/hardhat-toolbox";
import "@nomicfoundation/hardhat-ethers";
import "@nomicfoundation/hardhat-verify";
import "hardhat-deploy";
import "hardhat-deploy-ethers";
import "dotenv/config";
import { EndpointId } from '@layerzerolabs/lz-definitions';

const config: HardhatUserConfig = {
  solidity: {
    version: "0.8.30",
    settings: {
      viaIR: true,
      optimizer: {
        enabled: true,
        runs: 200
      }
    }
  },
  namedAccounts: {
    deployer: {
      default: 0,
    },
  },
  networks: {
    ethereum: {
      url: process.env.ETHEREUM_RPC_URL || "",
      accounts: [process.env.PRIVATE_KEY || ""],
      chainId: 1,
      verify: {
        etherscan: {
          apiUrl: "https://api.etherscan.io",
        },
      },
    },
    arbitrum: {
      url: process.env.ARBITRUM_RPC_URL || "",
      accounts: [process.env.PRIVATE_KEY || ""],
      chainId: 42161,
      verify: {
        etherscan: {
          apiUrl: "https://api.arbiscan.io",
        },
      },
    },
    optimism: {
      url: process.env.OPTIMISM_RPC_URL || "",
      accounts: [process.env.PRIVATE_KEY || ""],
      chainId: 10,
      verify: {
        etherscan: {
          apiUrl: "https://api-optimistic.etherscan.io",
        },
      },
    },
    polygon: {
      url: process.env.POLYGON_RPC_URL || "",
      accounts: [process.env.PRIVATE_KEY || ""],
      chainId: 137,
      verify: {
        etherscan: {
          apiUrl: "https://api.polygonscan.com",
        },
      },
    },
    base: {
      url: process.env.BASE_RPC_URL || "",
      accounts: [process.env.PRIVATE_KEY || ""],
      chainId: 8453,
      verify: {
        etherscan: {
          apiUrl: "https://api.basescan.org",
        },
      },
    },
    sonic: {
      url: process.env.SONIC_RPC_URL || "",
      accounts: [process.env.PRIVATE_KEY || ""],
      chainId: 146,
    },
    abstract: {
      url: process.env.ABSTRACT_RPC_URL || "",
      accounts: [process.env.PRIVATE_KEY || ""],
      chainId: 2741,
    },
    bsc: {
      url: process.env.BSC_RPC_URL || "",
      accounts: [process.env.PRIVATE_KEY || ""],
      chainId: 56,
      verify: {
        etherscan: {
          apiUrl: "https://api.bscscan.com",
        },
      },
    },

    fraxtal: {
      url: process.env.FRAXTAL_RPC_URL || "",
      accounts: [process.env.PRIVATE_KEY || ""],
      chainId: 252,
    },
    avalanche: {
      url: process.env.AVALANCHE_RPC_URL || "",
      accounts: [process.env.PRIVATE_KEY || ""],
      chainId: 43114,
      verify: {
        etherscan: {
          apiUrl: "https://api.snowtrace.io",
        },
      },
    },
    // Testnets
    sepolia: {
      url: process.env.SEPOLIA_RPC_URL || "",
      accounts: [process.env.PRIVATE_KEY || ""],
      chainId: 11155111,
      verify: {
        etherscan: {
          apiUrl: "https://api-sepolia.etherscan.io",
        },
      },
    },
    arbitrumSepolia: {
      url: process.env.ARBITRUM_SEPOLIA_RPC_URL || "",
      accounts: [process.env.PRIVATE_KEY || ""],
      chainId: 421614,
      verify: {
        etherscan: {
          apiUrl: "https://api-sepolia.arbiscan.io",
        },
      },
    },

    baseSepolia: {
      url: process.env.BASE_SEPOLIA_RPC_URL || "",
      accounts: [process.env.PRIVATE_KEY || ""],
      chainId: 84532,
      verify: {
        etherscan: {
          apiUrl: "https://api-sepolia.basescan.org",
        },
      },
    },
  },
  etherscan: {
    apiKey: {
      mainnet: process.env.ETHERSCAN_API_KEY || "",
      sepolia: process.env.SEPOLIA_ETHERSCAN_API_KEY || process.env.ETHERSCAN_API_KEY || "",
      arbitrumOne: process.env.ARBISCAN_API_KEY || "",
      arbitrumSepolia: process.env.ARBITRUM_SEPOLIA_ARBISCAN_API_KEY || process.env.ARBISCAN_API_KEY || "",
      optimisticEthereum: process.env.OPTIMISM_API_KEY || "",
      polygon: process.env.POLYGONSCAN_API_KEY || "",
      base: process.env.BASESCAN_API_KEY || "",
      baseSepolia: process.env.BASE_SEPOLIA_BASESCAN_API_KEY || process.env.BASESCAN_API_KEY || "",
      bsc: process.env.BSCSCAN_API_KEY || "",
      avalanche: process.env.SNOWTRACE_API_KEY || "",
    },
  },
};

// LayerZero endpoint IDs for mainnet chains
export const layerzeroMainnetEndpointIds = {
  ethereum: EndpointId.ETHEREUM_MAINNET,
  arbitrum: EndpointId.ARBITRUM_MAINNET,
  optimism: EndpointId.OPTIMISM_MAINNET,
  polygon: EndpointId.POLYGON_MAINNET,
  base: EndpointId.BASE_MAINNET,
  bsc: EndpointId.BSC_MAINNET,
  avalanche: EndpointId.AVALANCHE_MAINNET,
  sonic: EndpointId.SONIC_MAINNET,
  abstract: EndpointId.ABSTRACT_MAINNET,
  fraxtal: EndpointId.FRAXTAL_MAINNET,
};

// LayerZero endpoint IDs for testnet chains
export const layerzeroTestnetEndpointIds = {
  sepolia: EndpointId.ETHEREUM_TESTNET,
  arbitrumSepolia: EndpointId.ARBITRUM_TESTNET,
  baseSepolia: EndpointId.BASE_TESTNET,
};

// LayerZero endpoints for mainnet chains
export const layerzeroMainnetEndpoints = {
  ethereum: "0x1a44076050125825900e736c501f859c50fE728c",
  arbitrum: "0x1a44076050125825900e736c501f859c50fE728c",
  optimism: "0x1a44076050125825900e736c501f859c50fE728c",
  polygon: "0x1a44076050125825900e736c501f859c50fE728c",
  base: "0x1a44076050125825900e736c501f859c50fE728c",
  bsc: "0x1a44076050125825900e736c501f859c50fE728c",
  sonic: "0x6F475642a6e85809B1c36Fa62763669b1b48DD5B",
  abstract: "0x5c6cfF4b7C49805F8295Ff73C204ac83f3bC4AE7",
  fraxtal: "0x1a44076050125825900e736c501f859c50fE728c",
  avalanche: "0x1a44076050125825900e736c501f859c50fE728c",
};

// LayerZero endpoints for testnet chains
export const layerzeroTestnetEndpoints = {
  sepolia: "0x6EDCE65403992e310A62460808c4b910D972f10f",
  arbitrumSepolia: "0x6EDCE65403992e310A62460808c4b910D972f10f",
  baseSepolia: "0x6EDCE65403992e310A62460808c4b910D972f10f",
};

export default config;
