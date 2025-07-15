import { HardhatRuntimeEnvironment } from 'hardhat/types';
import { DeployFunction } from 'hardhat-deploy/types';
import { ethers } from 'hardhat';

const func: DeployFunction = async function (hre: HardhatRuntimeEnvironment) {
  const { deployments, getNamedAccounts, network } = hre;
  const { deploy } = deployments;
  const { deployer } = await getNamedAccounts();

  console.log(`\nDeploying Torque contracts to ${network.name}...`);
  console.log(`Deployer: ${deployer}`);

  // Get LayerZero endpoint
  const lzEndpoint = await getLZEndpoint(network.config.chainId);
  console.log(`LayerZero Endpoint: ${lzEndpoint}`);

  // Type definitions
  interface EngineConfig {
    name: string;
    contract: string;
    collateralToken: string;
    priceFeed: string;
    currencySymbol: string;
  }

  interface DeployedEngine {
    name: string;
    address: string;
    contract: string;
    currency: string;
  }

  // Multi-chain USDC addresses
  const USDC_ADDRESSES: { [chainId: number]: string } = {
    1: "0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48", // Ethereum mainnet
    8453: "0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913", // Base
    42161: "0xaf88d065e77c8cC2239327C5EDb3A432268e5831", // Arbitrum
    137: "0x3c499c542cEF5E3811e1192ce70d8cC03d5c3359", // Polygon
    10: "0x0b2C639c533813f4Aa9D7837CAf62653d097Ff85", // Optimism
    43114: "0xB97EF9Ef8734C71904D8002F8b6Bc66Dd9c48a6E", // Avalanche
    56: "0x8AC76a51cc950d9822D68b83fE1Ad97B32Cd580d", // BSC
    146: "0x29219dd400f2Bf60E5a23d13Be72B486D4038894" // Sonic
  };

  // Multi-chain currency pair price feeds
  const CURRENCY_PRICE_FEEDS: { [chainId: number]: { [pair: string]: string } } = {
    1: { // Ethereum mainnet
      EUR_USD: "0xb49f677943BC038e9857d61E7d053CaA2C1734C1",
      GBP_USD: "0x5c0Ab2d9b5a7ed9f470386e82BB36A3613cDd4b5",
      JPY_USD: "0xBcE206caE7f0ec07b545EddE332A47C2F75bbeb3",
      AUD_USD: "0x77F9710E7d0A19669A13c055F62cd80d313dF022",
      CAD_USD: "0xa34317DB73e77d453b1B8d04550c44d10e981C8e",
      CHF_USD: "0x449d117117838fFA61263B61dA6301AA2a88B13A",
      NZD_USD: "0x3977CFc9e4f29C184D4675f4EB8e0013236e5f3e",
      XAU_USD: "0x214eD9Da11D2fbe465a6fc601a91E62EbEc1a0D6",
      XAG_USD: "0x379589227b15F1a12195D3f2d90bBc9F31f95235",
      USDC_USD: "0x8fFfFfd4AfB6115b954Bd326cbe7B4BA576818f6"
    },
        8453: { // Base
       EUR_USD: "0xc91D87E81faB8f93699ECf7Ee9B44D11e1D53F0F",
       GBP_USD: "0xCceA6576904C118037695eB71195a5425E69Fa15",
       JPY_USD: "0x0000000000000000000000000000000000000000", // No JPY/USD feed available
       AUD_USD: "0x46e51B8cA41d709928EdA9Ae43e42193E6CDf229",
       CAD_USD: "0xA840145F87572E82519d578b1F36340368a25D5d",
       CHF_USD: "0x3A1d6444fb6a402470098E23DaD0B7E86E14252F",
       NZD_USD: "0x06bdFe07E71C476157FC025d3cCD4BBe08e83EF9",
       XAU_USD: "0x5213eBB69743b85644dbB6E25cdF994aFBb8cF31",
       XAG_USD: "0x0000000000000000000000000000000000000000", // No XAG/USD feed available
       USDC_USD: "0xd30e2101a97dcbAeBCBC04F14C3f624E67A35165"
     },
    42161: { // Arbitrum
      EUR_USD: "0xA14d53bC1F1c0F31B4aA3BD109344E5009051a84",
      GBP_USD: "0x9C4424Fd84C6661F97D8d6b3fc3C1aAc2BeDd137",
      JPY_USD: "0x3dD6e51CB9caE717d5a8778CF79A04029f9cFDF8",
      AUD_USD: "0x9854e9a850e7C354c1de177eA953a6b1fba8Fc22",
      CAD_USD: "0xf6DA27749484843c4F02f5Ad1378ceE723dD61d4",
      CHF_USD: "0xe32AccC8c4eC03F6E75bd3621BfC9Fbb234E1FC3",
      NZD_USD: "0x0000000000000000000000000000000000000000", // No NZD/USD feed available
      XAU_USD: "0x1F954Dc24a49708C26E0C1777f16750B5C6d5a2c",
      XAG_USD: "0xC56765f04B248394CF1619D20dB8082Edbfa75b1",
      USDC_USD: "0x50834F3163758fcC1Df9973b6e91f0F0F0434aD3"
    },
    137: { // Polygon
      EUR_USD: "0x73366Fe0AA0Ded304479862808e02506FE556a98",
      GBP_USD: "0x099a2540848573e94fb1Ca0Fa420b00acbBc845a",
      JPY_USD: "0xD647a6fC9BC6402301583C91decC5989d8Bc382D",
      AUD_USD: "0x062Df9C4efd2030e243ffCc398b652e8b8F95C6f",
      CAD_USD: "0xACA44ABb8B04D07D883202F99FA5E3c53ed57Fb5",
      CHF_USD: "0xc76f762CedF0F78a439727861628E0fdfE1e70c2",
      NZD_USD: "0xa302a0B8a499fD0f00449df0a490DedE21105955",
      XAU_USD: "0x0C466540B2ee1a31b441671eac0ca886e051E410",
      XAG_USD: "0x461c7B8D370a240DdB46B402748381C3210136b3",
      USDC_USD: "0xfE4A8cc5b5B2366C1B58Bea3858e81843581b2F7"
    },
        10: { // Optimism
       EUR_USD: "0x3626369857A10CcC6cc3A6e4f5C2f5984a519F20",
       GBP_USD: "0x0000000000000000000000000000000000000000", // No GBP/USD feed available
       JPY_USD: "0x536944c3A71FEb7c1E5C66Ee37d1a148d8D8f619",
       AUD_USD: "0x39be70E93D2D285C9E71be7f70FC5a45A7777B14",
       CAD_USD: "0x0000000000000000000000000000000000000000", // No CAD/USD feed available
       CHF_USD: "0x0000000000000000000000000000000000000000", // No CHF/USD feed available
       NZD_USD: "0x0000000000000000000000000000000000000000", // No NZD/USD feed available
       XAU_USD: "0x8F7bFb42Bf7421c2b34AAD619be4654bFa7B3B8B",
       XAG_USD: "0x290dd71254874f0d4356443607cb8234958DEe49",
       USDC_USD: "0x16a9FA2FDa030272Ce99B29CF780dFA30361E0f3"
     },
     43114: { // Avalanche
       EUR_USD: "0x192f2DBA961Bb0277520C082d6bfa87D5961333E",
       GBP_USD: "0x0000000000000000000000000000000000000000", // No GBP/USD feed available
       JPY_USD: "0xf8B283aD4d969ECFD70005714DD5910160565b94",
       AUD_USD: "0x0000000000000000000000000000000000000000", // No AUD/USD feed available
       CAD_USD: "0x0000000000000000000000000000000000000000", // No CAD/USD feed available
       CHF_USD: "0xA418573AB5226711c8564Eeb449c3618ABFaf677",
       NZD_USD: "0x0000000000000000000000000000000000000000", // No NZD/USD feed available
       XAU_USD: "0x1F41EF93dece881Ad0b98082B2d44D3f6F0C515B",
       XAG_USD: "0xA771e0D1e9E1eCc07C56CC38240779E54337d682",
       USDC_USD: "0x97FE42a7E96640D932bbc0e1580c73E705A8EB73"
     },
     56: { // BSC
      EUR_USD: "0x0bf79F617988C472DcA68ff41eFe1338955b9A80",
      GBP_USD: "0x8FAf16F710003E538189334541F5D4a391Da46a0",
      JPY_USD: "0x22Db8397a6E77E41471dE256a7803829fDC8bC57",
      AUD_USD: "0x498F912B09B5dF618c77fcC9E8DA503304Df92bF",
      CAD_USD: "0x0000000000000000000000000000000000000000", // No CAD/USD feed available
      CHF_USD: "0x964261740356cB4aaD0C3D2003Ce808A4176a46d",
      NZD_USD: "0x0000000000000000000000000000000000000000", // No NZD/USD feed available
      XAU_USD: "0x86896fEB19D8A607c3b11f2aF50A0f239Bd71CD0",
      XAG_USD: "0x817326922c909b16944817c207562B25C4dF16aD",
      USDC_USD: "0x90c069C4538adAc136E051052E14c1cD799C41B7"
     },
     146: { // Sonic
       EUR_USD: "0x0fceF1123FDBEdC89a0189B15D35B7A33B7694c0",
       GBP_USD: "0x0000000000000000000000000000000000000000", // No GBP/USD feed available
       JPY_USD: "0x0000000000000000000000000000000000000000", // No JPY/USD feed available
       AUD_USD: "0x0000000000000000000000000000000000000000", // No AUD/USD feed available
       CAD_USD: "0x0000000000000000000000000000000000000000", // No CAD/USD feed available
       CHF_USD: "0x0000000000000000000000000000000000000000", // No CHF/USD feed available
       NZD_USD: "0x0000000000000000000000000000000000000000", // No NZD/USD feed available
       XAU_USD: "0x0000000000000000000000000000000000000000", // No XAU/USD feed available
       XAG_USD: "0x0000000000000000000000000000000000000000", // No XAG/USD feed available
       USDC_USD: "0x55bCa887199d5520B3Ce285D41e6dC10C08716C9"
     },
     // Testnet chains
     11155111: { // Ethereum Sepolia
       EUR_USD: "0x1a81afB8146aeFfCFc5E50e8479e826E7D55b910",
       GBP_USD: "0x91FAB41F5f3bE955963a986366edAcff1aaeaa83",
       JPY_USD: "0x8A6af2B75F23831ADc973ce6288e5329F63D86c6",
       AUD_USD: "0xB0C712f98daE15264c8E26132BCC91C40aD4d5F9",
       CAD_USD: "0x0000000000000000000000000000000000000000", // No CAD/USD feed available
       CHF_USD: "0x0000000000000000000000000000000000000000", // No CHF/USD feed available
       NZD_USD: "0x0000000000000000000000000000000000000000", // No NZD/USD feed available
       XAU_USD: "0xC5981F461d74c46eB4b0CF3f4Ec79f025573B0Ea",
       XAG_USD: "0x0000000000000000000000000000000000000000", // No XAG/USD feed available
       USDC_USD: "0x0000000000000000000000000000000000000000" // placeholder
     },
     421613: { // Arbitrum Sepolia
       EUR_USD: "0x0000000000000000000000000000000000000000", // No EUR/USD feed available
       GBP_USD: "0x0000000000000000000000000000000000000000", // No GBP/USD feed available
       CAD_USD: "0x0000000000000000000000000000000000000000", // No CAD/USD feed available
       CHF_USD: "0x0000000000000000000000000000000000000000", // No CHF/USD feed available
       NZD_USD: "0x0000000000000000000000000000000000000000", // No NZD/USD feed available
       XAU_USD: "0x0000000000000000000000000000000000000000", // No XAU/USD feed available
       XAG_USD: "0x0000000000000000000000000000000000000000", // No XAG/USD feed available
       USDC_USD: "0x0000000000000000000000000000000000000000" // placeholder
     },
     84532: { // Base Sepolia
       EUR_USD: "0x0000000000000000000000000000000000000000", // No EUR/USD feed available
       GBP_USD: "0x0000000000000000000000000000000000000000", // No GBP/USD feed available
       CAD_USD: "0x0000000000000000000000000000000000000000", // No CAD/USD feed available
       CHF_USD: "0x0000000000000000000000000000000000000000", // No CHF/USD feed available
       NZD_USD: "0x0000000000000000000000000000000000000000", // No NZD/USD feed available
       XAU_USD: "0x0000000000000000000000000000000000000000", // No XAU/USD feed available
       XAG_USD: "0x0000000000000000000000000000000000000000", // No XAG/USD feed available
       USDC_USD: "0x0000000000000000000000000000000000000000" // placeholder
     },
     80002: { // Polygon Amoy
       EUR_USD: "0xa73B1C149CB4a0bf27e36dE347CBcfbe88F65DB2",
       GBP_USD: "0x0000000000000000000000000000000000000000", // No GBP/USD feed available
       CAD_USD: "0x0000000000000000000000000000000000000000", // No CAD/USD feed available
       CHF_USD: "0x0000000000000000000000000000000000000000", // No CHF/USD feed available
       NZD_USD: "0x0000000000000000000000000000000000000000", // No NZD/USD feed available
       XAU_USD: "0x0000000000000000000000000000000000000000", // No XAU/USD feed available
       XAG_USD: "0x0000000000000000000000000000000000000000", // No XAG/USD feed available
       USDC_USD: "0x0000000000000000000000000000000000000000" // placeholder
     },
     11155420: { // Optimism Sepolia
       EUR_USD: "0x828eda6b1B7266AD4d04Eb18468B965fc70940bd",
       GBP_USD: "0xbC1d7d0fb258164ad94B26D6718F256Aa85e1CaF",
       AUD_USD: "0x9AD8e9Fb2b2E6a25c1E89250Ff61945d68477977",
       CAD_USD: "0x0000000000000000000000000000000000000000", // No CAD/USD feed available
       CHF_USD: "0x0000000000000000000000000000000000000000", // No CHF/USD feed available
       NZD_USD: "0x0000000000000000000000000000000000000000", // No NZD/USD feed available
       XAU_USD: "0xa6932B792e4b4FfA1e78e63671f42d0aff02eD73",
       XAG_USD: "0x231eEe8c370512c48713c79966a969AC7c3E3bAd",
       USDC_USD: "0x0000000000000000000000000000000000000000" // placeholder
     },
     97: { // BSC Testnet
       EUR_USD: "0x0000000000000000000000000000000000000000", // No EUR/USD feed available
       GBP_USD: "0x0000000000000000000000000000000000000000", // No GBP/USD feed available
       JPY_USD: "0x0000000000000000000000000000000000000000", // No JPY/USD feed available
       AUD_USD: "0x0000000000000000000000000000000000000000", // No AUD/USD feed available
       CAD_USD: "0x0000000000000000000000000000000000000000", // No CAD/USD feed available
       CHF_USD: "0x0000000000000000000000000000000000000000", // No CHF/USD feed available
       NZD_USD: "0x0000000000000000000000000000000000000000", // No NZD/USD feed available
       XAU_USD: "0x4E08A779a85d28Cc96515379903A6029487CEbA0",
       XAG_USD: "0x0000000000000000000000000000000000000000", // No XAG/USD feed available
       USDC_USD: "0x0000000000000000000000000000000000000000" // placeholder
     }
  };

  // Get current chain ID
  const currentChainId = network.config.chainId!;
  const currentChainPriceFeeds = CURRENCY_PRICE_FEEDS[currentChainId] || {};
  const currentChainUSDC = USDC_ADDRESSES[currentChainId] || "0x0000000000000000000000000000000000000000";

  console.log(`\n🌐 Network: ${network.name} (Chain ID: ${currentChainId})`);
  console.log(`📋 USDC Address: ${currentChainUSDC}`);
  console.log(`📋 Currency Price Feeds:`);
  Object.entries(currentChainPriceFeeds).forEach(([pair, feed]) => {
    console.log(`   ${pair}: ${feed}`);
  });

  // Validate that we have the necessary price feeds for deployment
  const requiredFeeds = ['USDC_USD'];
  for (const feed of requiredFeeds) {
    if (!currentChainPriceFeeds[feed] || currentChainPriceFeeds[feed] === "0x0000000000000000000000000000000000000000") {
      console.warn(`⚠️  Warning: ${feed} price feed not available on ${network.name}`);
    }
  }

  // Default collateral token (USDC)
  const DEFAULT_COLLATERAL_TOKEN = currentChainUSDC;

  // Deploy TorqueUSD (TUSD) - the quote asset for all pairs
  console.log('\n1. Deploying TorqueUSD (TUSD)...');
  const torqueUSD = await deploy('TorqueUSD', {
    from: deployer,
    args: ['Torque USD', 'TUSD', lzEndpoint, deployer],
    log: true,
    waitConfirmations: 1,
  });
  console.log(`TorqueUSD deployed to: ${torqueUSD.address}`);

  // Deploy TorqueDEX (main DEX contract with pool management)
  console.log('\n2. Deploying TorqueDEX...');
  const torqueDEX = await deploy('TorqueDEX', {
    from: deployer,
    args: [lzEndpoint, deployer],
    log: true,
    waitConfirmations: 1,
  });
  console.log(`TorqueDEX deployed to: ${torqueDEX.address}`);

  // Set TUSD token in DEX
  console.log('\n3. Setting TUSD token in DEX...');
  const dexContract = await ethers.getContractAt('TorqueDEX', torqueDEX.address);
  const setTUSDTx = await dexContract.setDefaultQuoteAsset(torqueUSD.address);
  await setTUSDTx.wait();
  console.log('TUSD token set in DEX');

  // Deploy currency tokens
  console.log('\n4. Deploying currency tokens...');
  const currencies = [
    { name: 'Torque EUR', symbol: 'TEUR', contract: 'TorqueEUR' },
    { name: 'Torque GBP', symbol: 'TGBP', contract: 'TorqueGBP' },
    { name: 'Torque JPY', symbol: 'TJPY', contract: 'TorqueJPY' },
    { name: 'Torque AUD', symbol: 'TAUD', contract: 'TorqueAUD' },
    { name: 'Torque CAD', symbol: 'TCAD', contract: 'TorqueCAD' },
    { name: 'Torque CHF', symbol: 'TCHF', contract: 'TorqueCHF' },
    { name: 'Torque NZD', symbol: 'TNZD', contract: 'TorqueNZD' },
    { name: 'Torque XAU', symbol: 'TXAU', contract: 'TorqueXAU' },
    { name: 'Torque XAG', symbol: 'TXAG', contract: 'TorqueXAG' },
  ];

  const deployedCurrencies = [];
  for (const currency of currencies) {
    const deployed = await deploy(currency.contract, {
      from: deployer,
      args: [currency.name, currency.symbol, lzEndpoint, deployer],
      log: true,
      waitConfirmations: 1,
    });
    deployedCurrencies.push({
      name: currency.name,
      symbol: currency.symbol,
      address: deployed.address,
      contract: currency.contract,
    });
    console.log(`${currency.symbol} deployed to: ${deployed.address}`);
  }

  // Deploy currency engines
  console.log('\n5. Deploying currency engines...');
  const engines: EngineConfig[] = [
    { 
      name: 'Torque USD Engine', 
      contract: 'TorqueUSDEngine',
      collateralToken: DEFAULT_COLLATERAL_TOKEN,
      priceFeed: currentChainPriceFeeds.USDC_USD || "0x0000000000000000000000000000000000000000", // USDC/USD
      currencySymbol: 'TUSD'
    },
    { 
      name: 'Torque EUR Engine', 
      contract: 'TorqueEUREngine',
      collateralToken: DEFAULT_COLLATERAL_TOKEN,
      priceFeed: currentChainPriceFeeds.EUR_USD || "0x0000000000000000000000000000000000000000",
      currencySymbol: 'TEUR'
    },
    { 
      name: 'Torque GBP Engine', 
      contract: 'TorqueGBPEngine',
      collateralToken: DEFAULT_COLLATERAL_TOKEN,
      priceFeed: currentChainPriceFeeds.GBP_USD || "0x0000000000000000000000000000000000000000",
      currencySymbol: 'TGBP'
    },
    { 
      name: 'Torque JPY Engine', 
      contract: 'TorqueJPYEngine',
      collateralToken: DEFAULT_COLLATERAL_TOKEN,
      priceFeed: currentChainPriceFeeds.JPY_USD || "0x0000000000000000000000000000000000000000",
      currencySymbol: 'TJPY'
    },
    { 
      name: 'Torque AUD Engine', 
      contract: 'TorqueAUDEngine',
      collateralToken: DEFAULT_COLLATERAL_TOKEN,
      priceFeed: currentChainPriceFeeds.AUD_USD || "0x0000000000000000000000000000000000000000",
      currencySymbol: 'TAUD'
    },
    { 
      name: 'Torque CAD Engine', 
      contract: 'TorqueCADEngine',
      collateralToken: DEFAULT_COLLATERAL_TOKEN,
      priceFeed: currentChainPriceFeeds.CAD_USD || "0x0000000000000000000000000000000000000000",
      currencySymbol: 'TCAD'
    },
    { 
      name: 'Torque CHF Engine', 
      contract: 'TorqueCHFEngine',
      collateralToken: DEFAULT_COLLATERAL_TOKEN,
      priceFeed: currentChainPriceFeeds.CHF_USD || "0x0000000000000000000000000000000000000000",
      currencySymbol: 'TCHF'
    },
    { 
      name: 'Torque NZD Engine', 
      contract: 'TorqueNZDEngine',
      collateralToken: DEFAULT_COLLATERAL_TOKEN,
      priceFeed: currentChainPriceFeeds.NZD_USD || "0x0000000000000000000000000000000000000000",
      currencySymbol: 'TNZD'
    },
    { 
      name: 'Torque XAU Engine', 
      contract: 'TorqueXAUEngine',
      collateralToken: DEFAULT_COLLATERAL_TOKEN,
      priceFeed: currentChainPriceFeeds.XAU_USD || "0x0000000000000000000000000000000000000000",
      currencySymbol: 'TXAU'
    },
    { 
      name: 'Torque XAG Engine', 
      contract: 'TorqueXAGEngine',
      collateralToken: DEFAULT_COLLATERAL_TOKEN,
      priceFeed: currentChainPriceFeeds.XAG_USD || "0x0000000000000000000000000000000000000000",
      currencySymbol: 'TXAG'
    },
  ];

  const deployedEngines: DeployedEngine[] = [];
  for (const engine of engines) {
    // Find the corresponding currency contract
    const currencyContract = deployedCurrencies.find(c => c.symbol === engine.currencySymbol);
    if (!currencyContract) {
      throw new Error(`Currency contract not found for ${engine.currencySymbol}`);
    }

    // Check if price feed is available for this engine
    if (!engine.priceFeed || engine.priceFeed === "0x0000000000000000000000000000000000000000") {
      console.log(`⏭️  Skipping ${engine.name} - price feed not available on ${network.name}`);
      continue;
    }

    console.log(`\n🚀 Deploying ${engine.name}...`);
    console.log(`   Collateral Token: ${engine.collateralToken}`);
    console.log(`   Price Feed: ${engine.priceFeed}`);
    console.log(`   Currency Token: ${currencyContract.address}`);

    const deployed = await deploy(engine.contract, {
      from: deployer,
      args: [
        engine.collateralToken,  // USDC address
        engine.priceFeed,        // Currency pair price feed
        currencyContract.address, // Torque currency token address
        lzEndpoint               // LayerZero endpoint
      ],
      log: true,
      waitConfirmations: 1,
    });
    deployedEngines.push({
      name: engine.name,
      address: deployed.address,
      contract: engine.contract,
      currency: engine.currencySymbol,
    });
    console.log(`✅ ${engine.name} deployed to: ${deployed.address}`);
  }

  // Deploy main Torque contract
  console.log('\n6. Deploying main Torque contract...');
  const torque = await deploy('Torque', {
    from: deployer,
    args: [lzEndpoint, deployer],
    log: true,
    waitConfirmations: 1,
  });
  console.log(`Torque deployed to: ${torque.address}`);

  // Deploy TorqueLP (LP token template)
  console.log('\n7. Deploying TorqueLP template...');
  const torqueLP = await deploy('TorqueLP', {
    from: deployer,
    args: ['Torque LP Template', 'TLP', lzEndpoint, deployer],
    log: true,
    waitConfirmations: 1,
  });
  console.log(`TorqueLP template deployed to: ${torqueLP.address}`);

  // Deploy TorqueRouter
  console.log('\n8. Deploying TorqueRouter...');
  const torqueRouter = await deploy('TorqueRouter', {
    from: deployer,
    args: [torqueDEX.address, lzEndpoint, deployer],
    log: true,
    waitConfirmations: 1,
  });
  console.log(`TorqueRouter deployed to: ${torqueRouter.address}`);

  // Deploy TorqueStake
  console.log('\n9. Deploying TorqueStake...');
  const torqueStake = await deploy('TorqueStake', {
    from: deployer,
    args: [torqueUSD.address, lzEndpoint, deployer],
    log: true,
    waitConfirmations: 1,
  });
  console.log(`TorqueStake deployed to: ${torqueStake.address}`);

  // Deploy TorqueBatchHandler
  console.log('\n10. Deploying TorqueBatchHandler...');
  const torqueBatchHandler = await deploy('TorqueBatchHandler', {
    from: deployer,
    args: [lzEndpoint, deployer],
    log: true,
    waitConfirmations: 1,
  });
  console.log(`TorqueBatchHandler deployed to: ${torqueBatchHandler.address}`);

  // Deploy TorqueFX (main trading contract)
  console.log('\n11. Deploying TorqueFX...');
  const torqueFX = await deploy('TorqueFX', {
    from: deployer,
    args: [torqueDEX.address, torqueUSD.address],
    log: true,
    waitConfirmations: 1,
  });
  console.log(`TorqueFX deployed to: ${torqueFX.address}`);

  // Deploy TorqueRewards
  console.log('\n12. Deploying TorqueRewards...');
  const torqueRewards = await deploy('TorqueRewards', {
    from: deployer,
    args: [torqueUSD.address, torqueFX.address],
    log: true,
    waitConfirmations: 1,
  });
  console.log(`TorqueRewards deployed to: ${torqueRewards.address}`);

  console.log('\n✅ All contracts deployed successfully!');
  console.log('\n📋 Deployment Summary:');
  console.log(`Network: ${network.name}`);
  console.log(`Deployer: ${deployer}`);
  console.log(`LayerZero Endpoint: ${lzEndpoint}`);
  console.log(`\nCore Contracts:`);
  console.log(`  TorqueUSD (TUSD): ${torqueUSD.address}`);
  console.log(`  TorqueDEX: ${torqueDEX.address}`);
  console.log(`  Torque: ${torque.address}`);
  console.log(`  TorqueRouter: ${torqueRouter.address}`);
  console.log(`  TorqueStake: ${torqueStake.address}`);
  console.log(`  TorqueFX: ${torqueFX.address}`);
  console.log(`  TorqueRewards: ${torqueRewards.address}`);
  console.log(`  TorqueBatchHandler: ${torqueBatchHandler.address}`);
  console.log(`\nCurrency Tokens:`);
  deployedCurrencies.forEach(currency => {
    console.log(`  ${currency.symbol}: ${currency.address}`);
  });
  console.log(`\nCurrency Engines (${deployedEngines.length}/${engines.length} deployed):`);
  deployedEngines.forEach(engine => {
    console.log(`  ✅ ${engine.name} (${engine.currency}): ${engine.address}`);
  });
  
  // Show skipped engines
  const skippedEngines = engines.filter(engine => {
    const deployed = deployedEngines.find(e => e.contract === engine.contract);
    return !deployed;
  });
  
  if (skippedEngines.length > 0) {
    console.log(`\n⏭️  Skipped Engines (missing price feeds):`);
    skippedEngines.forEach(engine => {
      console.log(`  ⏭️  ${engine.name} (${engine.currencySymbol})`);
    });
    console.log(`\n💡 To deploy skipped engines, add the required price feeds for ${network.name} to the CURRENCY_PRICE_FEEDS configuration.`);
  }

  // Store deployment info for linking
  const deploymentData = {
    network: network.name,
    deployer,
    lzEndpoint,
    contracts: {
      torqueUSD: torqueUSD.address,
      torqueDEX: torqueDEX.address,
      torque: torque.address,
      torqueRouter: torqueRouter.address,
      torqueStake: torqueStake.address,
      torqueFX: torqueFX.address,
      torqueRewards: torqueRewards.address,
      torqueBatchHandler: torqueBatchHandler.address,
      currencies: deployedCurrencies,
      engines: deployedEngines,
    },
  };

  // Save deployment data to file
  const fs = require('fs');
  fs.writeFileSync(
    `deployment-${network.name}-${network.config.chainId}.json`,
    JSON.stringify(deploymentData, null, 2)
  );
};

// Helper function to get LayerZero endpoint for a chain
async function getLZEndpoint(chainId?: number): Promise<string> {
  if (!chainId) {
    throw new Error('Chain ID not found');
  }

  const endpoints: { [chainId: number]: string } = {
    // Mainnet
    1: '0x66A71Dcef29A0fFBDBE3c6a460a3B5BC225Cd675', // Ethereum
    42161: '0x3c2269811836af69497E5F486A85D7316753cf62', // Arbitrum
    10: '0x3c2269811836af69497E5F486A85D7316753cf62', // Optimism
    137: '0x3c2269811836af69497E5F486A85D7316753cf62', // Polygon
    8453: '0xb6319cC6c8c27A8F5dAF0dD3DF91EA35C4720dd7', // Base
    146: '0x3c2269811836af69497E5F486A85D7316753cf62', // Sonic

    56: '0x3c2269811836af69497E5F486A85D7316753cf62', // BSC
    43114: '0x3c2269811836af69497E5F486A85D7316753cf62', // Avalanche
    // Testnet
    11155111: '0xae92d5aD7583AD66E49A0c67BAd18F6ba52dDDc1', // Sepolia
    421613: '0x6EDCE65403992e310A62460808c4b910D972f10f', // Arbitrum Sepolia
    84532: '0x6EDCE65403992e310A62460808c4b910D972f10f', // Base Sepolia
  };

  const endpoint = endpoints[chainId];
  if (!endpoint) {
    throw new Error(`LayerZero endpoint not found for chain ID ${chainId}`);
  }

  return endpoint;
}

func.tags = ['Torque', 'Deploy'];
func.dependencies = [];

export default func; 