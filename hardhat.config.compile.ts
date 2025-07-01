import { HardhatUserConfig } from "hardhat/config";
import "@nomicfoundation/hardhat-toolbox";
import "@nomicfoundation/hardhat-ethers";
import "@nomicfoundation/hardhat-verify";
import "hardhat-deploy";
import "hardhat-deploy-ethers";
import "dotenv/config";

const config: HardhatUserConfig = {
  solidity: {
    compilers: [
      { version: "0.8.20" },
      { version: "0.8.28" }
    ]
  },
  namedAccounts: {
    deployer: {
      default: 0,
    },
  },
  networks: {
    hardhat: {
      chainId: 31337,
    },
  },
};

export default config; 