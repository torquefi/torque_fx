import { ethers } from "hardhat";
import { layerzeroEndpoints } from "../layerzero.config";

async function main() {
  const [deployer] = await ethers.getSigners();
  console.log("Deploying contracts with the account:", deployer.address);

  // Deploy mock USDC for testing
  const MockUSDC = await ethers.getContractFactory("MockERC20");
  const usdc = await MockUSDC.deploy("USD Coin", "USDC", 6);
  await usdc.deployed();
  console.log("MockUSDC deployed to:", usdc.address);

  // Deploy EntryPoint for ERC-4337
  const EntryPoint = await ethers.getContractFactory("EntryPoint");
  const entryPoint = await EntryPoint.deploy();
  await entryPoint.deployed();
  console.log("EntryPoint deployed to:", entryPoint.address);

  // Deploy TorqueDEX
  const TorqueDEX = await ethers.getContractFactory("TorqueDEX");
  const torqueDEX = await TorqueDEX.deploy(
    usdc.address, // token0
    usdc.address, // token1 (using USDC for testing)
    "Torque LP Token",
    "TLP",
    deployer.address, // feeRecipient
    ethers.ZeroAddress, // lzEndpoint (mock for testing)
    ethers.ZeroAddress // torqueAccount (will be set after deployment)
  );
  await torqueDEX.deployed();
  console.log("TorqueDEX deployed to:", torqueDEX.address);

  // Deploy TorqueAccount
  const TorqueAccount = await ethers.getContractFactory("TorqueAccount");
  const torqueAccount = await TorqueAccount.deploy(
    entryPoint.address,
    usdc.address,
    deployer.address, // guardian
    torqueDEX.address
  );
  await torqueAccount.deployed();
  console.log("TorqueAccount deployed to:", torqueAccount.address);

  // Update TorqueDEX with TorqueAccount address
  await torqueDEX.setTorqueAccount(torqueAccount.address);
  console.log("TorqueDEX updated with TorqueAccount address");

  // Deploy TorqueFX
  const TorqueFX = await ethers.getContractFactory("TorqueFX");
  const torqueFX = await TorqueFX.deploy(
    torqueAccount.address,
    torqueDEX.address,
    usdc.address
  );
  await torqueFX.deployed();
  console.log("TorqueFX deployed to:", torqueFX.address);

  // Deploy TorqueAccountFactory
  const TorqueAccountFactory = await ethers.getContractFactory("TorqueAccountFactory");
  const torqueAccountFactory = await TorqueAccountFactory.deploy(
    torqueAccount.address,
    entryPoint.address
  );
  await torqueAccountFactory.deployed();
  console.log("TorqueAccountFactory deployed to:", torqueAccountFactory.address);

  // Deploy TorqueAccountRecovery
  const TorqueAccountRecovery = await ethers.getContractFactory("TorqueAccountRecovery");
  const torqueAccountRecovery = await TorqueAccountRecovery.deploy(
    torqueAccount.address,
    deployer.address // guardian
  );
  await torqueAccountRecovery.deployed();
  console.log("TorqueAccountRecovery deployed to:", torqueAccountRecovery.address);

  // Deploy TorqueAccountUpgrade
  const TorqueAccountUpgrade = await ethers.getContractFactory("TorqueAccountUpgrade");
  const torqueAccountUpgrade = await TorqueAccountUpgrade.deploy(
    torqueAccount.address,
    deployer.address // guardian
  );
  await torqueAccountUpgrade.deployed();
  console.log("TorqueAccountUpgrade deployed to:", torqueAccountUpgrade.address);

  // Deploy TorqueAccountBundler
  const TorqueAccountBundler = await ethers.getContractFactory("TorqueAccountBundler");
  const torqueAccountBundler = await TorqueAccountBundler.deploy(
    torqueAccount.address,
    torqueFX.address
  );
  await torqueAccountBundler.deployed();
  console.log("TorqueAccountBundler deployed to:", torqueAccountBundler.address);

  // Deploy TorqueAccountCrossChain
  const TorqueAccountCrossChain = await ethers.getContractFactory("TorqueAccountCrossChain");
  const torqueAccountCrossChain = await TorqueAccountCrossChain.deploy(
    torqueAccount.address,
    ethers.ZeroAddress // lzEndpoint (mock for testing)
  );
  await torqueAccountCrossChain.deployed();
  console.log("TorqueAccountCrossChain deployed to:", torqueAccountCrossChain.address);

  // Deploy TorqueAccountGasOptimizer
  const TorqueAccountGasOptimizer = await ethers.getContractFactory("TorqueAccountGasOptimizer");
  const torqueAccountGasOptimizer = await TorqueAccountGasOptimizer.deploy(
    torqueAccount.address,
    torqueFX.address
  );
  await torqueAccountGasOptimizer.deployed();
  console.log("TorqueAccountGasOptimizer deployed to:", torqueAccountGasOptimizer.address);

  // Deploy Torque token with LayerZero support
  const Torque = await ethers.getContractFactory("Torque");
  const torque = await Torque.deploy(
    "Torque",
    "TORQ",
    layerzeroEndpoints.ethereum
  );
  await torque.deployed();
  console.log("Torque token deployed to:", torque.address);

  // Set initial parameters
  await torqueFX.setLiquidationThresholds(8500, 9500); // 85% and 95%
  await torqueFX.setFeeRecipient(deployer.address);
  await torqueFX.setMaxPositionSize(ethers.parseUnits("1000000", 6)); // 1M USDC
  await torqueDEX.setFee(4); // 0.04%

  // Log deployment summary
  console.log("\nDeployment Summary:");
  console.log("-------------------");
  console.log("MockUSDC:", usdc.address);
  console.log("EntryPoint:", entryPoint.address);
  console.log("TorqueDEX:", torqueDEX.address);
  console.log("TorqueAccount:", torqueAccount.address);
  console.log("TorqueFX:", torqueFX.address);
  console.log("TorqueAccountFactory:", torqueAccountFactory.address);
  console.log("TorqueAccountRecovery:", torqueAccountRecovery.address);
  console.log("TorqueAccountUpgrade:", torqueAccountUpgrade.address);
  console.log("TorqueAccountBundler:", torqueAccountBundler.address);
  console.log("TorqueAccountCrossChain:", torqueAccountCrossChain.address);
  console.log("TorqueAccountGasOptimizer:", torqueAccountGasOptimizer.address);
  console.log("Torque token:", torque.address);
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
  