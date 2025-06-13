import { ethers } from "hardhat";

async function main() {
  const [deployer] = await ethers.getSigners();
  console.log("Deploying contracts with the account:", deployer.address);

  // Deploy mock USDC for testing
  const MockUSDC = await ethers.getContractFactory("MockERC20");
  const usdc = await MockUSDC.deploy("USD Coin", "USDC", 6);
  await usdc.deployed();
  console.log("MockUSDC deployed to:", usdc.address);

  // Deploy TorqueAccount
  const TorqueAccount = await ethers.getContractFactory("TorqueAccount");
  const torqueAccount = await TorqueAccount.deploy();
  await torqueAccount.deployed();
  console.log("TorqueAccount deployed to:", torqueAccount.address);

  // Deploy TorqueFX
  const TorqueFX = await ethers.getContractFactory("TorqueFX");
  const torqueFX = await TorqueFX.deploy(usdc.address, torqueAccount.address);
  await torqueFX.deployed();
  console.log("TorqueFX deployed to:", torqueFX.address);

  // Deploy mock price feed for testing
  const MockPriceFeed = await ethers.getContractFactory("MockPriceFeed");
  const mockPriceFeed = await MockPriceFeed.deploy();
  await mockPriceFeed.deployed();
  console.log("MockPriceFeed deployed to:", mockPriceFeed.address);

  // Set up price feed for a test pair
  const pairId = ethers.utils.keccak256(ethers.utils.toUtf8Bytes("ETH/USD"));
  await torqueFX.setPriceFeed(pairId, mockPriceFeed.address);
  console.log("Price feed set for pair:", pairId);

  // Set initial liquidation thresholds
  await torqueFX.setLiquidationThresholds(8500, 9500); // 85% and 95%
  console.log("Liquidation thresholds set");

  // Set fee recipient
  await torqueFX.setFeeRecipient(deployer.address);
  console.log("Fee recipient set to:", deployer.address);

  // Log deployment summary
  console.log("\nDeployment Summary:");
  console.log("-------------------");
  console.log("MockUSDC:", usdc.address);
  console.log("TorqueAccount:", torqueAccount.address);
  console.log("TorqueFX:", torqueFX.address);
  console.log("MockPriceFeed:", mockPriceFeed.address);
  console.log("Test Pair ID:", pairId);
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  }); 