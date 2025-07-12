import { ethers } from "hardhat";

async function main() {
  console.log("Adding multi-collateral support to Torque engines...");

  // Get the signer
  const [deployer] = await ethers.getSigners();
  console.log("Using account:", deployer.address);

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

  // Engine addresses (replace with actual deployed engine addresses)
  const ENGINE_ADDRESSES = {
    TORQUE_USD_ENGINE: "0x...", // Replace with actual TorqueUSDEngine address
    TORQUE_EUR_ENGINE: "0x...", // Replace with actual TorqueEUREngine address
    TORQUE_GBP_ENGINE: "0x...", // Replace with actual TorqueGBPEngine address
    TORQUE_JPY_ENGINE: "0x...", // Replace with actual TorqueJPYEngine address
    TORQUE_AUD_ENGINE: "0x...", // Replace with actual TorqueAUDEngine address
    TORQUE_CAD_ENGINE: "0x...", // Replace with actual TorqueCADEngine address
    TORQUE_CHF_ENGINE: "0x...", // Replace with actual TorqueCHFEngine address
    TORQUE_NZD_ENGINE: "0x...", // Replace with actual TorqueNZDEngine address
    TORQUE_XAU_ENGINE: "0x...", // Replace with actual TorqueXAUEngine address
    TORQUE_XAG_ENGINE: "0x..."  // Replace with actual TorqueXAGEngine address
  };

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
      usd: engineFactories.TorqueUSDEngine.attach(ENGINE_ADDRESSES.TORQUE_USD_ENGINE),
      eur: engineFactories.TorqueEUREngine.attach(ENGINE_ADDRESSES.TORQUE_EUR_ENGINE),
      gbp: engineFactories.TorqueGBPEngine.attach(ENGINE_ADDRESSES.TORQUE_GBP_ENGINE),
      jpy: engineFactories.TorqueJPYEngine.attach(ENGINE_ADDRESSES.TORQUE_JPY_ENGINE),
      aud: engineFactories.TorqueAUDEngine.attach(ENGINE_ADDRESSES.TORQUE_AUD_ENGINE),
      cad: engineFactories.TorqueCADEngine.attach(ENGINE_ADDRESSES.TORQUE_CAD_ENGINE),
      chf: engineFactories.TorqueCHFEngine.attach(ENGINE_ADDRESSES.TORQUE_CHF_ENGINE),
      nzd: engineFactories.TorqueNZDEngine.attach(ENGINE_ADDRESSES.TORQUE_NZD_ENGINE),
      xau: engineFactories.TorqueXAUEngine.attach(ENGINE_ADDRESSES.TORQUE_XAU_ENGINE),
      xag: engineFactories.TorqueXAGEngine.attach(ENGINE_ADDRESSES.TORQUE_XAG_ENGINE)
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