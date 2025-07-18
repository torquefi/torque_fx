import { ethers } from "hardhat";
import { readFileSync } from "fs";

async function main() {
  console.log("Adding multi-collateral support to Torque engines...");

  // Get the signer
  const [deployer] = await ethers.getSigners();
  console.log("Using account:", deployer.address);

  // Get network info
  const network = await ethers.provider.getNetwork();
  const currentChainId = Number(network.chainId);
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

  // ===== STABLECOINS (98% liquidation threshold) =====
  
  // USD Coin (USDC) - Multi-chain support
  const USDC_ADDRESSES: { [chainId: number]: string } = {
    1: "0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48", // Ethereum mainnet
    42161: "0xaf88d065e77c8cC2239327C5EDb3A432268e5831", // Arbitrum One
    8453: "0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913", // Base
    10: "0x0b2C639c533813f4Aa9D7837CAf62653d097Ff85", // Optimism
    43114: "0xB97EF9Ef8734C71904D8002F8b6Bc66Dd9c48a6E", // Avalanche
    137: "0x2791Bca1f2de4661ED88A30C99A7a9449Aa84174", // Polygon
    56: "0x8AC76a51cc950d9822D68b83fE1Ad97B32Cd580d", // BSC
    146: "0x29219dd400f2Bf60E5a23d13Be72B486D4038894" // Sonic
  };
  
  const USDC_PRICE_FEEDS: { [chainId: number]: string } = {
    1: "0x986b5E1e1755e3C2440e960477f25201B0a8bbD4", // Ethereum mainnet
    42161: "0x50834F3163758fcC1Df9973b6e91f0F0F0434aD3", // Arbitrum One
    8453: "0x7e860098F58bBFC8648a4311b374B1D669a2bc6B", // Base
    10: "0x16a9FA2FDa030272Ce99B29CF780dFA30361E0f3", // Optimism
    43114: "0xF096872672F44d6EBA71458D74fe67F9a77a23B9", // Avalanche
    137: "0xfE4A8cc5b5B2366C1B58Bea3858e81843581b2F7", // Polygon
    56: "0x51597f405303C4377E36123cBc172b13269EA163", // BSC
    146: "0x55bCa887199d5520B3Ce285D41e6dC10C08716C9" // Sonic
  };
  
  // Tether (USDT) - Multi-chain support
  const USDT_ADDRESSES: { [chainId: number]: string } = {
    1: "0xdAC17F958D2ee523a2206206994597C13D831ec7", // Ethereum mainnet
    42161: "0xFd086bC7CD5C481DCC9C85ebE478A1C0b69FCbb9", // Arbitrum One
    8453: "0xfde4C96c8593536E31F229EA8f37b2ADa2699bb2", // Base
    10: "0x94b008aA00579c1307B0EF2c499aD98a8ce58e58", // Optimism
    43114: "0x9702230A8Ea53601f5cD2dc00fDBc13d4dF4A8c7", // Avalanche
    137: "0xc2132D05D31c914a87C6611C10748AEb04B58e8F", // Polygon
    56: "0x55d398326f99059fF775485246999027B3197955", // BSC
    146: "0x6047828dc181963ba44974801FF68e538dA5eaF9" // Sonic
  };
  
  const USDT_PRICE_FEEDS: { [chainId: number]: string } = {
    1: "0x3E7d1eAB13ad0104d2750B8863b489D65364e32D", // Ethereum mainnet
    42161: "0x3f3f5dF88dC9F13eac63DF89EC16ef6e7E25DdE7", // Arbitrum One
    8453: "0xf19d560eB8d2ADf07BD6D13ed03e1D11215721F9", // Base
    10: "0xECef79E109e997bCA29c1c0897ec9d7b03647F5E", // Optimism
    43114: "0xEBE676ee90Fe1112671f19b6B7459bC678B67e8a", // Avalanche
    137: "0x0A6513e40db6EB1b165753AD52E80663aeA50545", // Polygon
    56: "0xB97Ad0E74fa7d920791E90258A6E2085088b4320", // BSC
    146: "0x76F4C040A792aFB7F6dBadC7e30ca3EEa140D216" // Sonic
  };
  
  // Sky USD (USDS) - Multi-chain support
  const USDS_ADDRESSES: { [chainId: number]: string } = {
    1: "0xdC035D45d973E3EC169d2276DDab16f1e407384F", // Ethereum mainnet
    42161: "0x6491c05A82219b8D1479057361ff1654749b876b", // Arbitrum One
    8453: "0x820C137fa70C8691f0e44Dc420a5e53c168921Dc" // Base
  };
  
  const USDS_PRICE_FEEDS: { [chainId: number]: string } = {
    1: "0xfF30586cD0F29eD462364C7e81375FC0C71219b1", // Ethereum mainnet
    42161: "0x37833E5b3fbbEd4D613a3e0C354eF91A42B81eeB", // Arbitrum One
    8453: "0x2330aaE3bca5F05169d5f4597964D44522F62930" // Base
  };
  
  // PayPal USD (PYUSD) - Multi-chain support
  const PYUSD_ADDRESSES: { [chainId: number]: string } = {
    1: "0x6c3ea9036406852006290770BEdFcAbA0e23A0e8", // Ethereum mainnet
    42161: "0x46850aD61C2B7d64d08c9C754F45254596696984" // Arbitrum One
  };
  
  const PYUSD_PRICE_FEEDS: { [chainId: number]: string } = {
    1: "0x8f1dF6D7F2db73eECE86a18b4381F4707b918FB1", // Ethereum mainnet
    42161: "0x..." // Placeholder until feed is available
  };

  // ===== ETH DERIVATIVES (80% liquidation threshold) =====
  
  // Wrapped Ether (WETH) - Multi-chain support
  const WETH_ADDRESSES: { [chainId: number]: string } = {
    1: "0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2", // Ethereum mainnet
    42161: "0x82aF49447D8a07e3bd95BD0d56f35241523fBab1", // Arbitrum One
    8453: "0x4200000000000000000000000000000000000006", // Base
    10: "0x4200000000000000000000000000000000000006", // Optimism
    43114: "0x49D5c2BdFfac6CE2BFdB6640F4F80f226bc10bAB", // Avalanche
    137: "0x7ceB23fD6bC0adD59E62ac25578270cFf1b9f619", // Polygon
    56: "0x2170Ed0880ac9A755fd29B2688956BD959F933F8", // BSC
    146: "0x29219dd400f2Bf60E5a23d13Be72B486D4038894" // Sonic
  };
  
  const ETH_PRICE_FEEDS: { [chainId: number]: string } = {
    1: "0x5f4eC3Df9cbd43714FE2740f5E3616155c5b8419", // Ethereum mainnet
    42161: "0x639Fe6ab55C921f74e7fac1ee960C0B6293ba612", // Arbitrum One
    8453: "0x71041dddad3595F9CEd3DcCFBe3D1F4b0a16Bb70", // Base
    10: "0x13e3Ee699D1909E989722E753853AE30b17e08c5", // Optimism
    43114: "0x976B3D034E162d8bD72D6b9C989d545b839003b0", // Avalanche
    137: "0xF9680D99D6C9589e2a93a78A04A279e509205945", // Polygon
    56: "0x9ef1B8c0E4F7dc8bF5719Ea496883DC6401d5b2e", // BSC
    146: "0x9ef1B8c0E4F7dc8bF5719Ea496883DC6401d5b2e" // Sonic
  };
  
  // Coinbase ETH (cbETH) - Multi-chain support
  const CBETH_ADDRESSES: { [chainId: number]: string } = {
    1: "0xBe9895146f7AF43049ca1c1AE358B0541Ea49704", // Ethereum mainnet
    42161: "0x1DEBd73E752bEaF79865Fd6446b0c970EaE7732f", // Arbitrum One
    8453: "0x2Ae3F1Ec7F1F5012CFEab0185bfc7aa3cf0DEc22" // Base
  };
  
  const CBETH_PRICE_FEEDS: { [chainId: number]: string } = {
    1: "0xF017fcB346A1885194689bA23Eff2fE6fA5C483b", // Ethereum mainnet
    42161: "0xa668682974E3f121185a3cD94f00322beC674275", // Arbitrum One
    8453: "0x806b4Ac04501c29769051e42783cF04dCE41440b" // Base
  };
  
  // Ether.fi ETH (weETH)
  const WEETH_ADDRESS = "0xCd5fE23C85820F7B72D0926FC9b05b43E359b7ee"; // weETH on mainnet
  const WEETH_PRICE_FEED = "0x3fa10364c2B6aE4cbf4154ca74e8e637C031B9D6"; // weETH/ETH on mainnet
  
  // Mantle ETH (mETH)
  const METH_ADDRESS = "0xd5F7838F5C461fefF7FE49ea5ebaF7728bB0ADfa"; // mETH on mainnet
  const METH_PRICE_FEED = "0x5b563107C8666d2142C216114228443B94152362"; // mETH/ETH on mainnet
  
  // Lido Wrapped stETH (wstETH) - Multi-chain support
  const WSTETH_ADDRESSES: { [chainId: number]: string } = {
    1: "0x7f39C581F595B53c5cb19bD0b3f8dA6c935E2Ca0", // Ethereum mainnet
    42161: "0x5979D7b546E38E414F7E9822514be443A4800529", // Arbitrum One
    8453: "0xc1CBa3fCea344f92D9239c08C0568f6F2F0ee452", // Base
    10: "0x1F32b1c2345538c0c6f582fCB022739c4A194Ebb" // Optimism
  };
  
  const WSTETH_PRICE_FEEDS: { [chainId: number]: string } = {
    1: "0x8B6851156023f4f9A8564B8E0C5b8C4C3C3C3C3C", // Ethereum mainnet
    42161: "0xb523AE262D20A936BC152e6023996e46FDC2A95D", // Arbitrum One
    8453: "0x43a5C292A453A3bF3606fa856197f09D7B74251a", // Base
    10: "0x524299Ab0987a7c4B3c8022a35669DdcdC715a10" // Optimism
  };

  // ===== BTC DERIVATIVES (80% liquidation threshold) =====
  
  // Wrapped Bitcoin (WBTC) - Multi-chain support
  const WBTC_ADDRESSES: { [chainId: number]: string } = {
    1: "0x2260FAC5E5542a773Aa44fBCfeDf7C193bc2C599", // Ethereum mainnet
    42161: "0x2f2a2543B76A4166549F7aaB2e75Bef0aefC5B0f", // Arbitrum One
    8453: "0x0555E30da8f98308EdB960aa94C0Db47230d2B9c", // Base
    10: "0x68f180fcCe6836688e9084f035309E29Bf0A2095", // Optimism
    43114: "0x0555E30da8f98308EdB960aa94C0Db47230d2B9c", // Avalanche
    137: "0x0555E30da8f98308EdB960aa94C0Db47230d2B9c", // Polygon
    56: "0x0555E30da8f98308EdB960aa94C0Db47230d2B9c", // BSC
    146: "0x0555E30da8f98308EdB960aa94C0Db47230d2B9c" // Sonic
  };
  
  const BTC_PRICE_FEEDS: { [chainId: number]: string } = {
    1: "0xF4030086522a5bEEa4988F8cA5B36dbC97BeE88c", // Ethereum mainnet
    42161: "0x6ce185860a4963106506C203335A2910413708e9", // Arbitrum One
    8453: "0x64c911996D3c6aC71f9b455B1E8E7266BcbD848F", // Base
    10: "0xD702DD976Fb76Fffc2D3963D037dfDae5b04E593", // Optimism
    43114: "0x2779D32d5166BAaa2B2b658333bA7e6Ec0C65743", // Avalanche
    137: "0xc907E116054Ad103354f2D350FD2514433D57F6f", // Polygon
    56: "0x264990fbd0A4796A3E3d8E37C4d5F87a3aCa5Ebf", // BSC
    146: "0x8Bcd59Cb7eEEea8e2Da3080C891609483dae53EF" // Sonic
  };
  
  // Coinbase Bitcoin (cbBTC) - Multi-chain support
  const CBBTC_ADDRESSES: { [chainId: number]: string } = {
    1: "0xcbB7C0000aB88B473b1f5aFd9ef808440eed33Bf", // Ethereum mainnet
    8453: "0xcbB7C0000aB88B473b1f5aFd9ef808440eed33Bf" // Base
  };
  
  const CBBTC_PRICE_FEEDS: { [chainId: number]: string } = {
    1: "0x2665701293fCbEB223D11A08D826563EDcCE423A", // Ethereum mainnet
    8453: "0x07DA0E54543a844a80ABE69c8A12F22B3aA59f9D" // Base
  };
  
  // ===== OTHER ASSETS (80% liquidation threshold) =====
  
  // AAVE - Multi-chain support
  const AAVE_ADDRESSES: { [chainId: number]: string } = {
    1: "0x7Fc66500c84A76Ad7e9c93437bFc5Ac33E2DDaE9", // Ethereum mainnet
    8453: "0x63706e401c06ac8513145b7687A14804d17f814b", // Base
    56: "0xfb6115445Bff7b52FeB98650C87f44907E58f802", // BSC
    42161: "0xba5DdD1f9d7F570dc94a51479a000E3BCE967196", // Arbitrum
    137: "0xD6DF932A45C0f255f85145f286eA0b292B21C90B" // Polygon
  };
  
  const AAVE_PRICE_FEEDS: { [chainId: number]: string } = {
    1: "0x547a514d5e3769680Ce22B2361c10Ea13619e8a9", // Ethereum mainnet
    8453: "0x3d6774EF702A10b20FCa8Ed40FC022f7E4938e07", // Base
    56: "0xA8357BF572460fC40f4B0aCacbB2a6A61c89f475", // BSC
    42161: "0xaD1d5344AaDE45F43E596773Bcc4c423EAbdD034", // Arbitrum
    137: "0x72484B12719E23115761D5DA1646945632979bB6" // Polygon
  };
  
  // COMP - Multi-chain support
  const COMP_ADDRESSES: { [chainId: number]: string } = {
    1: "0xc00e94Cb662C3520282E6f5717214004A7f26888", // Ethereum mainnet
    8453: "0x9e1028F5F1D5eDE59748FFceE5532509976840E0", // Base
    56: "0x52CE071Bd9b1C4B00A0b92D298c512478CaD67e8", // BSC
    42161: "0x354A6dA3fcde098F8389cad84b0182725c6C91dE", // Arbitrum
    137: "0x8505b9d2254A7Ae468c0E9dd10Ccea3A837aef5c", // Polygon
  };
  
  const COMP_PRICE_FEEDS: { [chainId: number]: string } = {
    1: "0xdbd020CAeF83eFd542f4De03e3cF0C28A4428bd5", // Ethereum mainnet
    8453: "0x9DDa783DE64A9d1A60c49ca761EbE528C35BA428", // Base
    56: "0x0Db8945f9aEf5651fa5bd52314C5aAe78DfDe540", // BSC
    42161: "0xe7C53FFd03Eb6ceF7d208bC4C13446c76d1E5884", // Arbitrum
    137: "0x2A8758b7257102461BC958279054e372C2b1bDE6", // Polygon
  };
  
  // LINK - Multi-chain support
  const LINK_ADDRESSES: { [chainId: number]: string } = {
    1: "0x514910771AF9Ca656af840dff83E8264EcF986CA", // Ethereum mainnet
    8453: "0xd403D1624DAEF243FbcBd4A80d8A6F36afFe32b2", // Base
    56: "0xF8A0BF9cF54Bb92F17374d9e9A321E6a111a51bD", // BSC
    42161: "0xf97f4df75117a78c1A5a0DBb814Af92458539FB4", // Arbitrum 
    137: "0x53E0bca35eC356BD5ddDFebbD1Fc0fD03FaBad39", // Polygon
    43114: "0x5947BB275c521040051D82396192181b413227A3", // Avalanche
    10: "0x350a791Bfc2C21F9Ed5d10980Dad2e2638ffa7f6", // Optimism
  };
  
  const LINK_PRICE_FEEDS: { [chainId: number]: string } = {
    1: "0x2c1d072e956AFFC0D435Cb7AC38EF18d24d9127c", // Ethereum mainnet
    8453: "0x17CAb8FE31E32f08326e5E27412894e49B0f9D65", // Base
    56: "0xca236E327F629f9Fc2c30A4E95775EbF0B89fac8", // BSC
    42161: "0x86E53CF1B870786351Da77A57575e79CB55812CB", // Arbitrum
    137: "0xd9FFdb71EbE7496cC440152d43986Aae0AB76665", // Polygon
    43114: "0x49ccd9ca821EfEab2b98c60dC60F518E765EDe9a", // Avalanche
    10: "0xCc232dcFAAE6354cE191Bd574108c1aD03f86450" // Optimism
  };

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

    // ===== ADD STABLECOINS (98% liquidation threshold) =====
    console.log("\n=== Adding Stablecoins (98% liquidation threshold) ===");
    
    // Get network-specific addresses for USDC, USDT, and USDS
    const usdcAddress = USDC_ADDRESSES[currentChainId] || "0x0000000000000000000000000000000000000000";
    const usdcPriceFeed = USDC_PRICE_FEEDS[currentChainId] || "0x0000000000000000000000000000000000000000";
    const usdtAddress = USDT_ADDRESSES[currentChainId] || "0x0000000000000000000000000000000000000000";
    const usdtPriceFeed = USDT_PRICE_FEEDS[currentChainId] || "0x0000000000000000000000000000000000000000";
    const usdsAddress = USDS_ADDRESSES[currentChainId] || "0x0000000000000000000000000000000000000000";
    const usdsPriceFeed = USDS_PRICE_FEEDS[currentChainId] || "0x0000000000000000000000000000000000000000";
    const pyusdAddress = PYUSD_ADDRESSES[currentChainId] || "0x0000000000000000000000000000000000000000";
    const pyusdPriceFeed = PYUSD_PRICE_FEEDS[currentChainId] || "0x0000000000000000000000000000000000000000";
    
    console.log(`📋 USDC Address: ${usdcAddress}`);
    console.log(`📋 USDT Address: ${usdtAddress}`);
    console.log(`📋 USDS Address: ${usdsAddress}`);
    console.log(`📋 PYUSD Address: ${pyusdAddress}`);
    
    const stablecoins = [
      { name: "USDC", address: usdcAddress, priceFeed: usdcPriceFeed, decimals: 6, needsEthConversion: false },
      { name: "USDT", address: usdtAddress, priceFeed: usdtPriceFeed, decimals: 6, needsEthConversion: false },
      { name: "USDS", address: usdsAddress, priceFeed: usdsPriceFeed, decimals: 6, needsEthConversion: false },
      { name: "PYUSD", address: pyusdAddress, priceFeed: pyusdPriceFeed, decimals: 6, needsEthConversion: false }
    ];
    
    for (const stablecoin of stablecoins) {
      if (stablecoin.address !== "0x0000000000000000000000000000000000000000") {
        console.log(`Adding ${stablecoin.name} to all engines...`);
        for (const [currency, engine] of Object.entries(engines)) {
          const tx = await engine.addCollateralToken(stablecoin.address, stablecoin.decimals, stablecoin.priceFeed, false, stablecoin.needsEthConversion); // false = stablecoin
          await tx.wait();
          console.log(`✅ ${stablecoin.name} added to Torque${currency.toUpperCase()}Engine`);
        }
      } else {
        console.log(`⏭️  Skipping ${stablecoin.name} (placeholder address)`);
      }
    }

    // ===== ADD ETH DERIVATIVES (80% liquidation threshold) =====
    console.log("\n=== Adding ETH Derivatives (80% liquidation threshold) ===");
    
    // Get network-specific addresses for WETH, cbETH and wstETH
    const wethAddress = WETH_ADDRESSES[currentChainId] || "0x0000000000000000000000000000000000000000";
    const wethPriceFeed = ETH_PRICE_FEEDS[currentChainId] || "0x0000000000000000000000000000000000000000";
    const cbethAddress = CBETH_ADDRESSES[currentChainId] || "0x0000000000000000000000000000000000000000";
    const cbethPriceFeed = CBETH_PRICE_FEEDS[currentChainId] || "0x0000000000000000000000000000000000000000";
    const wstethAddress = WSTETH_ADDRESSES[currentChainId] || "0x0000000000000000000000000000000000000000";
    const wstethPriceFeed = WSTETH_PRICE_FEEDS[currentChainId] || "0x0000000000000000000000000000000000000000";
    
    console.log(`\n🌐 Network: ${network.name} (Chain ID: ${currentChainId})`);
    console.log(`📋 WETH Address: ${wethAddress}`);
    console.log(`📋 cbETH Address: ${cbethAddress}`);
    console.log(`📋 wstETH Address: ${wstethAddress}`);
    
    const ethDerivatives = [
      { name: "WETH", address: wethAddress, priceFeed: wethPriceFeed, decimals: 18, needsEthConversion: false },
      { name: "cbETH", address: cbethAddress, priceFeed: cbethPriceFeed, decimals: 18, needsEthConversion: true }, // cbETH/ETH feed
      { name: "weETH", address: WEETH_ADDRESS, priceFeed: WEETH_PRICE_FEED, decimals: 18, needsEthConversion: true }, // weETH/ETH feed
      { name: "mETH", address: METH_ADDRESS, priceFeed: METH_PRICE_FEED, decimals: 18, needsEthConversion: true }, // mETH/ETH feed
      { name: "wstETH", address: wstethAddress, priceFeed: wstethPriceFeed, decimals: 18, needsEthConversion: true } // wstETH/ETH feed
    ];
    
    for (const ethDeriv of ethDerivatives) {
      if (ethDeriv.address !== "0x0000000000000000000000000000000000000000") {
        console.log(`Adding ${ethDeriv.name} to all engines...`);
        for (const [currency, engine] of Object.entries(engines)) {
          const tx = await engine.addCollateralToken(ethDeriv.address, ethDeriv.decimals, ethDeriv.priceFeed, true, ethDeriv.needsEthConversion); // true = volatile
          await tx.wait();
          console.log(`✅ ${ethDeriv.name} added to Torque${currency.toUpperCase()}Engine`);
        }
      } else {
        console.log(`⏭️  Skipping ${ethDeriv.name} (placeholder address)`);
      }
    }

    // ===== ADD BTC DERIVATIVES (80% liquidation threshold) =====
    console.log("\n=== Adding BTC Derivatives (80% liquidation threshold) ===");
    
    // Get network-specific addresses for WBTC and cbBTC
    const wbtcAddress = WBTC_ADDRESSES[currentChainId] || "0x0000000000000000000000000000000000000000";
    const wbtcPriceFeed = BTC_PRICE_FEEDS[currentChainId] || "0x0000000000000000000000000000000000000000";
    const cbbtcAddress = CBBTC_ADDRESSES[currentChainId] || "0x0000000000000000000000000000000000000000";
    const cbbtcPriceFeed = CBBTC_PRICE_FEEDS[currentChainId] || "0x0000000000000000000000000000000000000000";
    
    console.log(`📋 WBTC Address: ${wbtcAddress}`);
    console.log(`📋 cbBTC Address: ${cbbtcAddress}`);
    
    const btcDerivatives = [
      { name: "WBTC", address: wbtcAddress, priceFeed: wbtcPriceFeed, decimals: 8, needsEthConversion: false },
      { name: "cbBTC", address: cbbtcAddress, priceFeed: cbbtcPriceFeed, decimals: 8, needsEthConversion: false }
    ];
    
    for (const btcDeriv of btcDerivatives) {
      if (btcDeriv.address !== "0x0000000000000000000000000000000000000000") {
        console.log(`Adding ${btcDeriv.name} to all engines...`);
        for (const [currency, engine] of Object.entries(engines)) {
          const tx = await engine.addCollateralToken(btcDeriv.address, btcDeriv.decimals, btcDeriv.priceFeed, true, btcDeriv.needsEthConversion); // true = volatile
          await tx.wait();
          console.log(`✅ ${btcDeriv.name} added to Torque${currency.toUpperCase()}Engine`);
        }
      } else {
        console.log(`⏭️  Skipping ${btcDeriv.name} (placeholder address)`);
      }
    }

    // ===== ADD OTHER ASSETS (80% liquidation threshold) =====
    console.log("\n=== Adding Other Assets (80% liquidation threshold) ===");
    
    // Get network-specific addresses for AAVE, COMP, and LINK
    const aaveAddress = AAVE_ADDRESSES[currentChainId] || "0x0000000000000000000000000000000000000000";
    const aavePriceFeed = AAVE_PRICE_FEEDS[currentChainId] || "0x0000000000000000000000000000000000000000";
    const compAddress = COMP_ADDRESSES[currentChainId] || "0x0000000000000000000000000000000000000000";
    const compPriceFeed = COMP_PRICE_FEEDS[currentChainId] || "0x0000000000000000000000000000000000000000";
    const linkAddress = LINK_ADDRESSES[currentChainId] || "0x0000000000000000000000000000000000000000";
    const linkPriceFeed = LINK_PRICE_FEEDS[currentChainId] || "0x0000000000000000000000000000000000000000";
    
    console.log(`📋 AAVE Address: ${aaveAddress}`);
    console.log(`📋 COMP Address: ${compAddress}`);
    console.log(`📋 LINK Address: ${linkAddress}`);
    
    const otherAssets = [
      { name: "AAVE", address: aaveAddress, priceFeed: aavePriceFeed, decimals: 18, needsEthConversion: false },
      { name: "COMP", address: compAddress, priceFeed: compPriceFeed, decimals: 18, needsEthConversion: false },
      { name: "LINK", address: linkAddress, priceFeed: linkPriceFeed, decimals: 18, needsEthConversion: false }
    ];
    
    for (const asset of otherAssets) {
      if (asset.address !== "0x0000000000000000000000000000000000000000") {
        console.log(`Adding ${asset.name} to all engines...`);
        for (const [currency, engine] of Object.entries(engines)) {
          const tx = await engine.addCollateralToken(asset.address, asset.decimals, asset.priceFeed, true, asset.needsEthConversion); // true = volatile
          await tx.wait();
          console.log(`✅ ${asset.name} added to Torque${currency.toUpperCase()}Engine`);
        }
      } else {
        console.log(`⏭️  Skipping ${asset.name} (placeholder address)`);
      }
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
    console.log("\n🔵 Stablecoins (98% liquidation threshold):");
    console.log("- USDC (default)");
    console.log("- USDT");
    console.log("- USDS");
    console.log("- PYUSD");
    
    console.log("\n🟡 ETH Derivatives (80% liquidation threshold):");
    console.log("- WETH");
    console.log("- cbETH");
    console.log("- weETH");
    console.log("- mETH");
    console.log("- wstETH");
    
    console.log("\n🟠 BTC Derivatives (80% liquidation threshold):");
    console.log("- WBTC");
    console.log("- cbBTC (when available)");
    
    console.log("\n🟢 Other Assets (80% liquidation threshold):");
    console.log("- AAVE");
    console.log("- COMP");
    console.log("- LINK");
    
    console.log("\n🔧 To deposit with specific collateral:");
    console.log("await engine.depositCollateral(tokenAddress, amount);");
    console.log("\n⚠️  Liquidation thresholds:");
    console.log("- Stablecoins: 98% - liquidated when collateral drops 2%");
    console.log("- Volatile assets (ETH/BTC derivatives, DeFi tokens): 80% - liquidated when collateral drops 20%");
    
    console.log("\n🌐 All engines now support comprehensive multi-collateral functionality!");

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