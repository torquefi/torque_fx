import { HardhatUserConfig } from "hardhat/config";
import "@nomiclabs/hardhat-ethers";
import "@nomiclabs/hardhat-etherscan";
import "dotenv/config";
import "@layerzerolabs/lz-evm-oapp-v2/contracts/oft/OFT.sol";
import "@layerzerolabs/lz-evm-oapp-v2/contracts/oapp/OApp.sol";

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
    // },
  },
  etherscan: {
    apiKey: process.env.ETHERSCAN_API_KEY,
  },
};

export const layerzeroEndpoints = {
  ethereum: "0x1a44076050125825900e736c501f859c50fE728c",
  arbitrum: "0x1a44076050125825900e736c501f859c50fE728c",
  // optimism: "0x1a44076050125825900e736c501f859c50fE728c",
  // polygon: "0x1a44076050125825900e736c501f859c50fE728c",
  // sonic: "0x6F475642a6e85809B1c36Fa62763669b1b48DD5B",
  // base: "0x1a44076050125825900e736c501f859c50fE728c",
  // sepolia: "0x6EDCE65403992e310A62460808c4b910D972f10f",
  // arbitrumSepolia: "0x6EDCE65403992e310A62460808c4b910D972f10f",
  // optimismSepolia: "0x6EDCE65403992e310A62460808c4b910D972f10f",
  // polygonAmoy: "0x6EDCE65403992e310A62460808c4b910D972f10f",
  // sonicTestnet: "#",
  // baseSepolia: "0x6EDCE65403992e310A62460808c4b910D972f10f",
};

export default config;