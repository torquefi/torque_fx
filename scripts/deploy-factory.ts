import hre from "hardhat";
// import { verify } from "./verify";

async function main() {
  const [deployer] = await hre.ethers.getSigners();
  console.log("Deploying contracts with the account:", deployer.address);

  // Get network info
  const network = await hre.ethers.provider.getNetwork();
  console.log("Network chain ID:", network.chainId);

  // Get LayerZero endpoint for this network
  const lzEndpoint = await getLZEndpoint(network.chainId);
  console.log("LayerZero Endpoint:", lzEndpoint);

  // Deploy TorqueDEXFactory
  console.log("\n=== Deploying TorqueDEXFactory ===");
  const TorqueDEXFactory = await hre.ethers.getContractFactory("TorqueDEXFactory");
  const factory = await TorqueDEXFactory.deploy(
    lzEndpoint,
    deployer.address, // owner
    deployer.address  // default fee recipient
  );
  await factory.waitForDeployment();
  const factoryAddress = await factory.getAddress();
  console.log("TorqueDEXFactory deployed to:", factoryAddress);

  // Deploy TUSD as the quote asset
  console.log("\n=== Deploying TUSD (Quote Asset) ===");
  const MockERC20 = await hre.ethers.getContractFactory("MockERC20");
  
  const tusd = await MockERC20.deploy("TrueUSD", "TUSD", 18);
  await tusd.waitForDeployment();
  const tusdAddress = await tusd.getAddress();
  console.log("TUSD deployed to:", tusdAddress);

  // Set TUSD as the quote asset in the factory
  console.log("\n=== Setting TUSD as Quote Asset ===");
  const setTUSD = await factory.setTUSDToken(tusdAddress);
  await setTUSD.wait();
  console.log("TUSD set as quote asset in factory");

  // Deploy some example base tokens for testing
  console.log("\n=== Deploying Example Base Tokens ===");
  
  const weth = await MockERC20.deploy("Wrapped Ether", "WETH", 18);
  await weth.waitForDeployment();
  const wethAddress = await weth.getAddress();
  console.log("WETH deployed to:", wethAddress);

  const usdc = await MockERC20.deploy("USD Coin", "USDC", 6);
  await usdc.waitForDeployment();
  const usdcAddress = await usdc.getAddress();
  console.log("USDC deployed to:", usdcAddress);

  const btc = await MockERC20.deploy("Bitcoin", "BTC", 8);
  await btc.waitForDeployment();
  const btcAddress = await btc.getAddress();
  console.log("BTC deployed to:", btcAddress);

  const link = await MockERC20.deploy("Chainlink", "LINK", 18);
  await link.waitForDeployment();
  const linkAddress = await link.getAddress();
  console.log("LINK deployed to:", linkAddress);

  // Create DEX pairs with TUSD as quote asset
  console.log("\n=== Creating DEX Pairs (TUSD as Quote Asset) ===");
  
  // WETH/TUSD pair
  const wethTusdDex = await factory.createDEX(
    wethAddress,
    "WETH/TUSD",
    "WETH-TUSD",
    deployer.address,
    false // not stable pair
  );
  await wethTusdDex.wait();
  const wethTusdDexAddress = await factory.getDEX(wethAddress);
  console.log("WETH/TUSD DEX created at:", wethTusdDexAddress);

  // USDC/TUSD stable pair
  const usdcTusdDex = await factory.createDEX(
    usdcAddress,
    "USDC/TUSD",
    "USDC-TUSD",
    deployer.address,
    true // stable pair
  );
  await usdcTusdDex.wait();
  const usdcTusdDexAddress = await factory.getDEX(usdcAddress);
  console.log("USDC/TUSD DEX created at:", usdcTusdDexAddress);

  // BTC/TUSD pair
  const btcTusdDex = await factory.createDEX(
    btcAddress,
    "BTC/TUSD",
    "BTC-TUSD",
    deployer.address,
    false // not stable pair
  );
  await btcTusdDex.wait();
  const btcTusdDexAddress = await factory.getDEX(btcAddress);
  console.log("BTC/TUSD DEX created at:", btcTusdDexAddress);

  // LINK/TUSD pair
  const linkTusdDex = await factory.createDEX(
    linkAddress,
    "LINK/TUSD",
    "LINK-TUSD",
    deployer.address,
    false // not stable pair
  );
  await linkTusdDex.wait();
  const linkTusdDexAddress = await factory.getDEX(linkAddress);
  console.log("LINK/TUSD DEX created at:", linkTusdDexAddress);

  // Get DEX info
  const dexCount = await factory.getDEXCount();
  console.log("\nTotal DEX pairs created:", dexCount.toString());

  const allDexs = await factory.getAllDEXs();
  console.log("All DEX addresses:", allDexs);

  // Verify TUSD is set correctly
  const factoryTUSD = await factory.tusdToken();
  console.log("Factory TUSD address:", factoryTUSD);
  console.log("TUSD set in factory:", await factory.tusdSet());

  // Test pair queries
  console.log("\n=== Testing Pair Queries ===");
  console.log("WETH has DEX:", await factory.hasDEX(wethAddress));
  console.log("USDC has DEX:", await factory.hasDEX(usdcAddress));
  console.log("BTC has DEX:", await factory.hasDEX(btcAddress));
  console.log("LINK has DEX:", await factory.hasDEX(linkAddress));

  // Verify contracts on Etherscan (if not localhost)
  /*
  if (network.chainId !== 31337) {
    console.log("\n=== Verifying Contracts ===");
    
    // Wait a bit for deployment to be indexed
    await new Promise(resolve => setTimeout(resolve, 30000));
    
    try {
      await verify(factoryAddress, [
        lzEndpoint,
        deployer.address,
        deployer.address
      ]);
      console.log("TorqueDEXFactory verified on Etherscan");
    } catch (error) {
      console.log("Failed to verify TorqueDEXFactory:", error);
    }

    try {
      await verify(tusdAddress, ["TrueUSD", "TUSD", 18]);
      console.log("TUSD verified on Etherscan");
    } catch (error) {
      console.log("Failed to verify TUSD:", error);
    }

    try {
      await verify(wethAddress, ["Wrapped Ether", "WETH", 18]);
      console.log("WETH verified on Etherscan");
    } catch (error) {
      console.log("Failed to verify WETH:", error);
    }

    try {
      await verify(usdcAddress, ["USD Coin", "USDC", 6]);
      console.log("USDC verified on Etherscan");
    } catch (error) {
      console.log("Failed to verify USDC:", error);
    }

    try {
      await verify(btcAddress, ["Bitcoin", "BTC", 8]);
      console.log("BTC verified on Etherscan");
    } catch (error) {
      console.log("Failed to verify BTC:", error);
    }

    try {
      await verify(linkAddress, ["Chainlink", "LINK", 18]);
      console.log("LINK verified on Etherscan");
    } catch (error) {
      console.log("Failed to verify LINK:", error);
    }
  }
  */

  console.log("\n=== Deployment Summary ===");
  console.log("Factory:", factoryAddress);
  console.log("TUSD (Quote Asset):", tusdAddress);
  console.log("WETH:", wethAddress);
  console.log("USDC:", usdcAddress);
  console.log("BTC:", btcAddress);
  console.log("LINK:", linkAddress);
  console.log("\nDEX Pairs:");
  console.log("WETH/TUSD DEX:", wethTusdDexAddress);
  console.log("USDC/TUSD DEX:", usdcTusdDexAddress);
  console.log("BTC/TUSD DEX:", btcTusdDexAddress);
  console.log("LINK/TUSD DEX:", linkTusdDexAddress);
}

// Helper function to get LayerZero endpoint for different networks
async function getLZEndpoint(chainId: number): Promise<string> {
  const endpoints: { [key: number]: string } = {
    1: "0x66A71Dcef29A0fFBDBE3c6a460a3B5BC225Cd675", // Ethereum
    42161: "0x3c2269811836af69497E5F486A85D7316753cf62", // Arbitrum
    10: "0x3c2269811836af69497E5F486A85D7316753cf62", // Optimism
    137: "0x3c2269811836af69497E5F486A85D7316753cf62", // Polygon
    8453: "0xb6319cC6c8c27A8F5dAF0dD3DF91EA35C4720dd7", // Base
    146: "0x3c2269811836af69497E5F486A85D7316753cf62", // Sonic
    2741: "0x3c2269811836af69497E5F486A85D7316753cf62", // Abstract
    56: "0x3c2269811836af69497E5F486A85D7316753cf62", // BSC
    999: "0x3c2269811836af69497E5F486A85D7316753cf62", // HyperEVM
    252: "0x3c2269811836af69497E5F486A85D7316753cf62", // Fraxtal
    43114: "0x3c2269811836af69497E5F486A85D7316753cf62", // Avalanche
    31337: "0x0000000000000000000000000000000000000000" // Localhost
  };

  const endpoint = endpoints[chainId];
  if (!endpoint) {
    throw new Error(`No LayerZero endpoint found for chain ID ${chainId}`);
  }
  return endpoint;
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  }); 