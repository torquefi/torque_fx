import { HardhatUserConfig } from "hardhat/config";
import "@nomicfoundation/hardhat-toolbox";
import "@nomicfoundation/hardhat-ethers";
import "@nomicfoundation/hardhat-verify";
import "dotenv/config";
import { EndpointId } from '@layerzerolabs/lz-definitions';

const config: HardhatUserConfig = {
  solidity: "0.8.19",
  networks: {
    ethereum: {
      url: process.env.ETHEREUM_RPC_URL || "",
      accounts: [process.env.PRIVATE_KEY || ""],
      chainId: 1,
    },
    arbitrum: {
      url: process.env.ARBITRUM_RPC_URL || "",
      accounts: [process.env.PRIVATE_KEY || ""],
      chainId: 42161,
    },
    optimism: {
      url: process.env.OPTIMISM_RPC_URL || "",
      accounts: [process.env.PRIVATE_KEY || ""],
      chainId: 10,
    },
    polygon: {
      url: process.env.POLYGON_RPC_URL || "",
      accounts: [process.env.PRIVATE_KEY || ""],
      chainId: 137,
    },
    base: {
      url: process.env.BASE_RPC_URL || "",
      accounts: [process.env.PRIVATE_KEY || ""],
      chainId: 8453,
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
    },
    hyperevm: {
      url: process.env.HYPEREVM_RPC_URL || "",
      accounts: [process.env.PRIVATE_KEY || ""],
      chainId: 999,
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
    },
    // Testnets
    sepolia: {
      url: process.env.SEPOLIA_RPC_URL || "",
      accounts: [process.env.PRIVATE_KEY || ""],
      chainId: 11155111,
    },
    arbitrumSepolia: {
      url: process.env.ARBITRUM_SEPOLIA_RPC_URL || "",
      accounts: [process.env.PRIVATE_KEY || ""],
      chainId: 421614,
    },
    optimismSepolia: {
      url: process.env.OPTIMISM_SEPOLIA_RPC_URL || "",
      accounts: [process.env.PRIVATE_KEY || ""],
      chainId: 11155420,
    },
    polygonMumbai: {
      url: process.env.POLYGON_MUMBAI_RPC_URL || "",
      accounts: [process.env.PRIVATE_KEY || ""],
      chainId: 80001,
    },
    baseGoerli: {
      url: process.env.BASE_GOERLI_RPC_URL || "",
      accounts: [process.env.PRIVATE_KEY || ""],
      chainId: 84531,
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
  hyperevm: EndpointId.HYPEREVM_MAINNET,
  fraxtal: EndpointId.FRAXTAL_MAINNET,
};

// LayerZero endpoint IDs for testnet chains
export const layerzeroTestnetEndpointIds = {
  sepolia: EndpointId.ETHEREUM_TESTNET,
  arbitrumSepolia: EndpointId.ARBITRUM_TESTNET,
  optimismSepolia: EndpointId.OPTIMISM_TESTNET,
  polygonMumbai: EndpointId.POLYGON_TESTNET,
  baseGoerli: EndpointId.BASE_TESTNET,
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
  hyperevm: "0x3A73033C0b1407574C76BdBAc67f126f6b4a9AA9",
  fraxtal: "0x1a44076050125825900e736c501f859c50fE728c",
  avalanche: "0x1a44076050125825900e736c501f859c50fE728c",
};

// LayerZero endpoints for testnet chains
export const layerzeroTestnetEndpoints = {
  sepolia: "0x6EDCE65403992e310A62460808c4b910D972f10f",
  arbitrumSepolia: "0x6EDCE65403992e310A62460808c4b910D972f10f",
  optimismSepolia: "0x6EDCE65403992e310A62460808c4b910D972f10f",
  polygonMumbai: "0x6EDCE65403992e310A62460808c4b910D972f10f",
  baseGoerli: "0x6EDCE65403992e310A62460808c4b910D972f10f",
  bscTestnet: "0x6EDCE65403992e310A62460808c4b910D972f10f",
  avalancheFuji: "0x6EDCE65403992e310A62460808c4b910D972f10f",
};

export default config;
