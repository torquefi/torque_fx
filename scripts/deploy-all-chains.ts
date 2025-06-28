import { ethers } from "hardhat";
import { layerzeroMainnetEndpoints } from "../hardhat.config";
import { HardhatRuntimeEnvironment } from "hardhat/types";

declare const hre: HardhatRuntimeEnvironment;

const CHAINS = [
  { name: "ethereum", chainId: 1 },
  { name: "arbitrum", chainId: 42161 },
  { name: "optimism", chainId: 10 },
  { name: "polygon", chainId: 137 },
  { name: "base", chainId: 8453 },
  { name: "sonic", chainId: 146 },
  { name: "abstract", chainId: 2741 },
  { name: "bsc", chainId: 56 },
  { name: "hyperevm", chainId: 999 },
  { name: "fraxtal", chainId: 252 },
  { name: "avalanche", chainId: 43114 },
];

async function main() {
  console.log("=== TORQUE FX MULTI-CHAIN DEPLOYMENT ===");
  
  const deploymentResults: { [chainName: string]: any } = {};

  for (const chain of CHAINS) {
    console.log(`\n🚀 Deploying to ${chain.name.toUpperCase()} (Chain ID: ${chain.chainId})`);
    
    try {
      // Deploy contracts for this chain
      const result = await deployToChain(chain.name, chain.chainId);
      deploymentResults[chain.name] = result;
      
      console.log(`✅ Successfully deployed to ${chain.name}`);
      console.log(`   - Currencies: ${Object.keys(result.currencies).length}`);
      console.log(`   - Engines: ${Object.keys(result.engines).length}`);
      console.log(`   - Batch Minter: ${result.batchMinter}`);
      
    } catch (error: any) {
      console.error(`❌ Failed to deploy to ${chain.name}:`, error);
      deploymentResults[chain.name] = { error: error.message };
    }
  }

  // Print final summary
  console.log("\n" + "=".repeat(50));
  console.log("DEPLOYMENT SUMMARY");
  console.log("=".repeat(50));
  
  for (const [chainName, result] of Object.entries(deploymentResults)) {
    if (result.error) {
      console.log(`❌ ${chainName}: FAILED - ${result.error}`);
    } else {
      console.log(`✅ ${chainName}: SUCCESS`);
      console.log(`   Batch Minter: ${result.batchMinter}`);
    }
  }

  // Save deployment results to file
  const fs = require('fs');
  fs.writeFileSync(
    'deployment-results.json', 
    JSON.stringify(deploymentResults, null, 2)
  );
  console.log("\n📄 Deployment results saved to deployment-results.json");
}

async function deployToChain(chainName: string, chainId: number) {
  const [deployer] = await ethers.getSigners();
  console.log(`   Deployer: ${deployer.address}`);

  const lzEndpoint = layerzeroMainnetEndpoints[chainName as keyof typeof layerzeroMainnetEndpoints];
  if (!lzEndpoint) {
    throw new Error(`No LayerZero endpoint found for ${chainName}`);
  }
  console.log(`   LayerZero Endpoint: ${lzEndpoint}`);

  // Deploy mock USDC for testing
  const MockUSDC = await ethers.getContractFactory("MockERC20");
  const usdc = await MockUSDC.deploy("USD Coin", "USDC", 6);
  await usdc.waitForDeployment();
  const usdcAddress = await usdc.getAddress();
  console.log(`   MockUSDC: ${usdcAddress}`);

  // Deploy mock price feed
  const MockPriceFeed = await ethers.getContractFactory("MockPriceFeed");
  const priceFeed = await MockPriceFeed.deploy(8, "USD/ETH", 18);
  await priceFeed.waitForDeployment();
  const priceFeedAddress = await priceFeed.getAddress();
  console.log(`   MockPriceFeed: ${priceFeedAddress}`);

  // Deploy all currencies
  const currencies = await deployCurrencies(lzEndpoint, deployer.address);
  console.log(`   Deployed ${Object.keys(currencies).length} currencies`);

  // Deploy all engines
  const engines = await deployEngines(currencies, usdcAddress, priceFeedAddress, lzEndpoint);
  console.log(`   Deployed ${Object.keys(engines).length} engines`);

  // Deploy batch minter
  const TorqueBatchMinter = await ethers.getContractFactory("TorqueBatchMinter");
  const batchMinter = await TorqueBatchMinter.deploy(lzEndpoint, deployer.address);
  await batchMinter.waitForDeployment();
  const batchMinterAddress = await batchMinter.getAddress();
  console.log(`   TorqueBatchMinter: ${batchMinterAddress}`);

  // Configure batch minter
  await configureBatchMinter(batchMinter, currencies, engines, chainId);
  console.log(`   Batch minter configured`);

  // Deploy main Torque token
  const Torque = await ethers.getContractFactory("Torque");
  const torque = await Torque.deploy("Torque", "TORQ", lzEndpoint, deployer.address);
  await torque.waitForDeployment();
  const torqueAddress = await torque.getAddress();
  console.log(`   Torque: ${torqueAddress}`);

  return {
    chainId,
    deployer: deployer.address,
    lzEndpoint,
    usdc: usdcAddress,
    priceFeed: priceFeedAddress,
    currencies,
    engines,
    batchMinter: batchMinterAddress,
    torque: torqueAddress,
  };
}

async function deployCurrencies(lzEndpoint: string, owner: string) {
  const currencyNames = ["USD", "EUR", "GBP", "JPY", "AUD", "CAD", "CHF", "NZD", "XAU", "XAG"];
  const currencies: { [key: string]: string } = {};

  for (const name of currencyNames) {
    const TorqueCurrency = await ethers.getContractFactory(`Torque${name}`);
    const currency = await TorqueCurrency.deploy(
      `Torque ${name}`,
      `Torque${name}`,
      lzEndpoint
    );
    await currency.waitForDeployment();
    const currencyAddress = await currency.getAddress();
    currencies[name] = currencyAddress;
  }

  return currencies;
}

async function deployEngines(
  currencies: { [key: string]: string },
  usdcAddress: string,
  priceFeedAddress: string,
  lzEndpoint: string
) {
  const currencyNames = ["USD", "EUR", "GBP", "JPY", "AUD", "CAD", "CHF", "NZD", "XAU", "XAG"];
  const engines: { [key: string]: string } = {};

  for (const name of currencyNames) {
    const TorqueEngine = await ethers.getContractFactory(`Torque${name}Engine`);
    const engine = await TorqueEngine.deploy(
      usdcAddress,
      priceFeedAddress,
      currencies[name],
      lzEndpoint
    );
    await engine.waitForDeployment();
    const engineAddress = await engine.getAddress();
    engines[name] = engineAddress;
  }

  return engines;
}

async function configureBatchMinter(
  batchMinter: any,
  currencies: { [key: string]: string },
  engines: { [key: string]: string },
  chainId: number
) {
  const currencyNames = ["USD", "EUR", "GBP", "JPY", "AUD", "CAD", "CHF", "NZD", "XAU", "XAG"];

  // Add supported currencies
  for (const name of currencyNames) {
    await batchMinter.addSupportedCurrency(currencies[name]);
  }

  // Set engine addresses for current chain
  for (const name of currencyNames) {
    await batchMinter.setEngineAddress(currencies[name], chainId, engines[name]);
  }
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  }); 