import { ethers } from "hardhat";
import { layerzeroMainnetEndpoints, layerzeroTestnetEndpoints } from "../hardhat.config";

async function main() {
  const [deployer] = await ethers.getSigners();
  console.log("Deploying contracts with the account:", deployer.address);

  // Get current network
  const network = await ethers.provider.getNetwork();
  const chainId = network.chainId;
  console.log("Deploying to chain ID:", chainId);

  // Get LayerZero endpoint for current chain
  const networkName = getNetworkName(chainId);
  
  // Determine if we're on mainnet or testnet and get appropriate endpoints
  const isMainnet = isMainnetChain(chainId);
  const endpoints = isMainnet ? layerzeroMainnetEndpoints : layerzeroTestnetEndpoints;
  
  const lzEndpoint = endpoints[networkName as keyof typeof endpoints];
  if (!lzEndpoint) {
    throw new Error(`No LayerZero endpoint found for chain ID ${chainId} (${networkName})`);
  }

  console.log(`Network: ${networkName} (${isMainnet ? 'Mainnet' : 'Testnet'})`);
  console.log("LayerZero endpoint:", lzEndpoint);

  // Deploy mock USDC for testing (replace with real USDC addresses in production)
  const MockUSDC = await ethers.getContractFactory("MockERC20");
  const usdc = await MockUSDC.deploy("USD Coin", "USDC", 6);
  await usdc.deployed();
  console.log("MockUSDC deployed to:", usdc.address);

  // Deploy mock price feed for testing
  const MockPriceFeed = await ethers.getContractFactory("MockPriceFeed");
  const priceFeed = await MockPriceFeed.deploy(8, "USD/ETH", 18); // $2000 ETH price
  await priceFeed.deployed();
  console.log("MockPriceFeed deployed to:", priceFeed.address);

  // Deploy all Torque currencies
  const currencies = await deployCurrencies(lzEndpoint, deployer.address);
  console.log("All currencies deployed");

  // Deploy all Torque engines
  const engines = await deployEngines(currencies, usdc.address, priceFeed.address, lzEndpoint);
  console.log("All engines deployed");

  // Deploy TorqueBatchMinter
  const TorqueBatchMinter = await ethers.getContractFactory("TorqueBatchMinter");
  const batchMinter = await TorqueBatchMinter.deploy(lzEndpoint, deployer.address);
  await batchMinter.deployed();
  console.log("TorqueBatchMinter deployed to:", batchMinter.address);

  // Configure batch minter with all engines
  await configureBatchMinter(batchMinter, currencies, engines, chainId);
  console.log("Batch minter configured");

  // Deploy main Torque token
  const Torque = await ethers.getContractFactory("Torque");
  const torque = await Torque.deploy("Torque", "TORQ", lzEndpoint, deployer.address);
  await torque.deployed();
  console.log("Torque token deployed to:", torque.address);

  // Deploy other contracts (keeping existing logic)
  await deployOtherContracts(usdc, torque, deployer);

  // Log deployment summary
  console.log("\n=== DEPLOYMENT SUMMARY ===");
  console.log("Network:", getNetworkName(chainId));
  console.log("Chain ID:", chainId);
  console.log("Deployer:", deployer.address);
  console.log("LayerZero Endpoint:", lzEndpoint);
  console.log("\n--- Currencies ---");
  Object.entries(currencies).forEach(([name, address]) => {
    console.log(`${name}: ${address}`);
  });
  console.log("\n--- Engines ---");
  Object.entries(engines).forEach(([name, address]) => {
    console.log(`${name}: ${address}`);
  });
  console.log("\n--- Other Contracts ---");
  console.log("MockUSDC:", usdc.address);
  console.log("MockPriceFeed:", priceFeed.address);
  console.log("TorqueBatchMinter:", batchMinter.address);
  console.log("Torque:", torque.address);
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
    await currency.deployed();
    currencies[name] = currency.address;
    console.log(`Torque${name} deployed to:`, currency.address);
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
      usdcAddress,        // collateral token
      priceFeedAddress,   // price feed
      currencies[name],   // torque token
      lzEndpoint
    );
    await engine.deployed();
    engines[name] = engine.address;
    console.log(`Torque${name}Engine deployed to:`, engine.address);
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

async function deployOtherContracts(usdc: any, torque: any, deployer: any) {
  // Deploy EntryPoint for ERC-4337
  const EntryPoint = await ethers.getContractFactory("EntryPoint");
  const entryPoint = await EntryPoint.deploy();
  await entryPoint.deployed();
  console.log("EntryPoint deployed to:", entryPoint.address);

  // Deploy TorqueDEX
  const TorqueDEX = await ethers.getContractFactory("TorqueDEX");
  const torqueDEX = await TorqueDEX.deploy(
    usdc.address,
    usdc.address,
    "Torque LP Token",
    "TLP",
    deployer.address,
    false // isStablePair
  );
  await torqueDEX.deployed();
  console.log("TorqueDEX deployed to:", torqueDEX.address);

  // Deploy TorqueAccount
  const TorqueAccount = await ethers.getContractFactory("TorqueAccount");
  const torqueAccount = await TorqueAccount.deploy(
    entryPoint.address,
    usdc.address,
    deployer.address,
    torqueDEX.address
  );
  await torqueAccount.deployed();
  console.log("TorqueAccount deployed to:", torqueAccount.address);

  // Deploy TorqueFX
  const TorqueFX = await ethers.getContractFactory("TorqueFX");
  const torqueFX = await TorqueFX.deploy(
    torqueAccount.address,
    torqueDEX.address,
    usdc.address
  );
  await torqueFX.deployed();
  console.log("TorqueFX deployed to:", torqueFX.address);

  // Deploy other 4337 contracts
  const contracts = [
    { name: "TorqueAccountFactory", args: [torqueAccount.address, entryPoint.address] },
    { name: "TorqueAccountRecovery", args: [torqueAccount.address, deployer.address] },
    { name: "TorqueAccountUpgrade", args: [torqueAccount.address, deployer.address] },
    { name: "TorqueAccountBundler", args: [torqueAccount.address, torqueFX.address] },
    { name: "TorqueAccountCrossChain", args: [torqueAccount.address, ethers.ZeroAddress] },
    { name: "TorqueAccountGasOptimizer", args: [torqueAccount.address, torqueFX.address] },
  ];

  for (const contract of contracts) {
    const Contract = await ethers.getContractFactory(contract.name);
    const instance = await Contract.deploy(...contract.args);
    await instance.deployed();
    console.log(`${contract.name} deployed to:`, instance.address);
  }

  // Set initial parameters
  await torqueFX.setLiquidationThresholds(8500, 9500);
  await torqueFX.setFeeRecipient(deployer.address);
  await torqueFX.setMaxPositionSize(ethers.parseUnits("1000000", 6));
  await torqueDEX.setFee(4);
}

function getNetworkName(chainId: number): string {
  const networks: { [key: number]: string } = {
    1: "ethereum",
    42161: "arbitrum",
    10: "optimism",
    137: "polygon",
    8453: "base",
    146: "sonic",
    2741: "abstract",
    56: "bsc",
    11155111: "sepolia",
    421614: "arbitrumSepolia",
    11155420: "optimismSepolia",
    80001: "polygonMumbai",
    84531: "baseGoerli",
  };
  return networks[chainId] || "unknown";
}

function isMainnetChain(chainId: number): boolean {
  const mainnetChainIds = [1, 42161, 10, 137, 8453, 146, 2741, 56, 999, 252, 43114];
  return mainnetChainIds.includes(chainId);
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
  