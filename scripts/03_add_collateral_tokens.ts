import { ethers } from "hardhat";
import { readFileSync } from "fs";

async function main() {
  console.log("Adding multi-collateral support to Torque engines...");

  // Get the signer
  const [deployer] = await ethers.getSigners();
  console.log("Using account:", deployer.address);

  // Get network info
  const network = await ethers.provider.getNetwork();
  const deploymentFile = `deployment-${network.name}-${network.chainId}.json`;
  
  let deploymentData;
  try {
    deploymentData = JSON.parse(readFileSync(deploymentFile, 'utf8'));
    console.log(`📁 Loaded deployment data from ${deploymentFile}`);
  } catch (error) {
    console.error(`❌ Could not load deployment file: ${deploymentFile}`);
    console.error("Please run the deployment script first: yarn hardhat run scripts/01_deploy_torque.ts --network <network>");
    process.exit(1);
  }

  // Common token addresses (replace with actual addresses for your network)
  const USDC_ADDRESS = "0xA0b86a33E6441b8c4C8C8C8C8C8C8C8C8C8C8C8C"; // Replace with actual USDC address
  const USDT_ADDRESS = "0xdAC17F958D2ee523a2206206994597C13D831ec7"; // USDT on mainnet
  const WETH_ADDRESS = "0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2"; // WETH on mainnet
  const WBTC_ADDRESS = "0x2260FAC5E5542a773Aa44fBCfeDf7C193bc2C599"; // WBTC on mainnet

  // Price feed addresses (replace with actual Chainlink price feed addresses)
  const USDC_PRICE_FEED = "0x8fFfFfd4AfB6115b954Bd326cbe7B4BA576818f6"; // USDC/USD on mainnet
  const USDT_PRICE_FEED = "0x3E7d1eAB13ad0104d2750B8863b489D65364e32D"; // USDT/USD on mainnet
  const ETH_PRICE_FEED = "0x5f4eC3Df9cbd43714FE2740f5E3616155c5b8419"; // ETH/USD on mainnet
  const BTC_PRICE_FEED = "0xF4030086522a5bEEa4988F8cA5B36dbC97BeE88c"; // BTC/USD on mainnet

  // Get engine addresses from deployment data
  const ENGINE_ADDRESSES = {
    TORQUE_USD_ENGINE: deploymentData.contracts.engines.find((e: any) => e.contract === 'TorqueUSDEngine')?.address,
    TORQUE_EUR_ENGINE: deploymentData.contracts.engines.find((e: any) => e.contract === 'TorqueEUREngine')?.address,
    TORQUE_GBP_ENGINE: deploymentData.contracts.engines.find((e: any) => e.contract === 'TorqueGBPEngine')?.address,
    TORQUE_JPY_ENGINE: deploymentData.contracts.engines.find((e: any) => e.contract === 'TorqueJPYEngine')?.address,
    TORQUE_AUD_ENGINE: deploymentData.contracts.engines.find((e: any) => e.contract === 'TorqueAUDEngine')?.address,
    TORQUE_CAD_ENGINE: deploymentData.contracts.engines.find((e: any) => e.contract === 'TorqueCADEngine')?.address,
    TORQUE_CHF_ENGINE: deploymentData.contracts.engines.find((e: any) => e.contract === 'TorqueCHFEngine')?.address,
    TORQUE_NZD_ENGINE: deploymentData.contracts.engines.find((e: any) => e.contract === 'TorqueNZDEngine')?.address,
    TORQUE_XAU_ENGINE: deploymentData.contracts.engines.find((e: any) => e.contract === 'TorqueXAUEngine')?.address,
    TORQUE_XAG_ENGINE: deploymentData.contracts.engines.find((e: any) => e.contract === 'TorqueXAGEngine')?.address
  };

  // Validate all engine addresses are found
  for (const [key, address] of Object.entries(ENGINE_ADDRESSES)) {
    if (!address) {
      console.error(`❌ Missing engine address for ${key}`);
      process.exit(1);
    }
    console.log(`✅ ${key}: ${address}`);
  }

  try {
    // Get all engine contracts
    const engineFactories = {
      TorqueUSDEngine: await ethers.getContractFactory("TorqueUSDEngine"),
      TorqueEUREngine: await ethers.getContractFactory("TorqueEUREngine"),
      TorqueGBPEngine: await ethers.getContractFactory("TorqueGBPEngine"),
      TorqueJPYEngine: await ethers.getContractFactory("TorqueJPYEngine"),
      TorqueAUDEngine: await ethers.getContractFactory("TorqueAUDEngine"),
      TorqueCADEngine: await ethers.getContractFactory("TorqueCADEngine"),
      TorqueCHFEngine: await ethers.getContractFactory("TorqueCHFEngine"),
      TorqueNZDEngine: await ethers.getContractFactory("TorqueNZDEngine"),
      TorqueXAUEngine: await ethers.getContractFactory("TorqueXAUEngine"),
      TorqueXAGEngine: await ethers.getContractFactory("TorqueXAGEngine")
    };

    const engines = {
      usd: engineFactories.TorqueUSDEngine.attach(ENGINE_ADDRESSES.TORQUE_USD_ENGINE) as any,
      eur: engineFactories.TorqueEUREngine.attach(ENGINE_ADDRESSES.TORQUE_EUR_ENGINE) as any,
      gbp: engineFactories.TorqueGBPEngine.attach(ENGINE_ADDRESSES.TORQUE_GBP_ENGINE) as any,
      jpy: engineFactories.TorqueJPYEngine.attach(ENGINE_ADDRESSES.TORQUE_JPY_ENGINE) as any,
      aud: engineFactories.TorqueAUDEngine.attach(ENGINE_ADDRESSES.TORQUE_AUD_ENGINE) as any,
      cad: engineFactories.TorqueCADEngine.attach(ENGINE_ADDRESSES.TORQUE_CAD_ENGINE) as any,
      chf: engineFactories.TorqueCHFEngine.attach(ENGINE_ADDRESSES.TORQUE_CHF_ENGINE) as any,
      nzd: engineFactories.TorqueNZDEngine.attach(ENGINE_ADDRESSES.TORQUE_NZD_ENGINE) as any,
      xau: engineFactories.TorqueXAUEngine.attach(ENGINE_ADDRESSES.TORQUE_XAU_ENGINE) as any,
      xag: engineFactories.TorqueXAGEngine.attach(ENGINE_ADDRESSES.TORQUE_XAG_ENGINE) as any
    };

    console.log("\n=== Adding USDT as collateral to all engines ===");
    
    // Add USDT to all engines
    for (const [currency, engine] of Object.entries(engines)) {
      console.log(`Adding USDT to Torque${currency.toUpperCase()}Engine...`);
      const tx = await engine.addCollateralToken(USDT_ADDRESS, 6, USDT_PRICE_FEED);
      await tx.wait();
      console.log(`✅ USDT added to Torque${currency.toUpperCase()}Engine`);
    }

    console.log("\n=== Adding ETH as collateral to all engines ===");
    
    // Add ETH to all engines
    for (const [currency, engine] of Object.entries(engines)) {
      console.log(`Adding ETH to Torque${currency.toUpperCase()}Engine...`);
      const tx = await engine.addCollateralToken(WETH_ADDRESS, 18, ETH_PRICE_FEED);
      await tx.wait();
      console.log(`✅ ETH added to Torque${currency.toUpperCase()}Engine`);
    }

    console.log("\n=== Adding BTC as collateral to all engines ===");
    
    // Add BTC to all engines
    for (const [currency, engine] of Object.entries(engines)) {
      console.log(`Adding BTC to Torque${currency.toUpperCase()}Engine...`);
      const tx = await engine.addCollateralToken(WBTC_ADDRESS, 8, BTC_PRICE_FEED);
      await tx.wait();
      console.log(`✅ BTC added to Torque${currency.toUpperCase()}Engine`);
    }

    console.log("\n=== Verification ===");
    
    // Verify supported collateral for all engines
    for (const [currency, engine] of Object.entries(engines)) {
      const supported = await engine.getSupportedCollateral();
      console.log(`Torque${currency.toUpperCase()}Engine supported collateral:`, supported);
    }

    console.log("\n🎉 Multi-collateral setup complete!");
    console.log("\n📊 Summary:");
    console.log(`✅ Processed ${Object.keys(engines).length} engines:`);
    Object.keys(engines).forEach(currency => {
      console.log(`   - Torque${currency.toUpperCase()}Engine`);
    });
    
    console.log("\n💎 Users can now deposit:");
    console.log("- USDC (default)");
    console.log("- USDT");
    console.log("- ETH (WETH)");
    console.log("- BTC (WBTC)");
    console.log("\n🔧 To deposit with specific collateral:");
    console.log("await engine.depositCollateral(tokenAddress, amount);");
    
    console.log("\n🌐 All engines now support multi-collateral functionality!");

  } catch (error) {
    console.error("Error adding collateral tokens:", error);
    process.exit(1);
  }
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  }); 