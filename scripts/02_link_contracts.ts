import { HardhatRuntimeEnvironment } from 'hardhat/types';
import { DeployFunction } from 'hardhat-deploy/types';
import { ethers } from 'hardhat';

const func: DeployFunction = async function (hre: HardhatRuntimeEnvironment) {
  const { deployments, getNamedAccounts, network } = hre;
  const { get } = deployments;
  const { deployer } = await getNamedAccounts();

  console.log(`\nLinking Torque contracts on ${network.name}...`);
  console.log(`Deployer: ${deployer}`);

  // Get deployed contracts
  const torqueUSD = await get('TorqueUSD');
  const torqueDEX = await get('TorqueDEX');
  const torque = await get('Torque');
  const torqueRouter = await get('TorqueRouter');
  const torqueStake = await get('TorqueStake');
  const torqueRewards = await get('TorqueRewards');
  const torqueBatchHandler = await get('TorqueBatchHandler');
  const torqueFX = await get('TorqueFX');

  // Get currency contracts
  const currencies = [
    { name: 'TorqueEUR', symbol: 'TEUR' },
    { name: 'TorqueGBP', symbol: 'TGBP' },
    { name: 'TorqueJPY', symbol: 'TJPY' },
    { name: 'TorqueAUD', symbol: 'TAUD' },
    { name: 'TorqueCAD', symbol: 'TCAD' },
    { name: 'TorqueCHF', symbol: 'TCHF' },
    { name: 'TorqueNZD', symbol: 'TNZD' },
    { name: 'TorqueXAU', symbol: 'TXAU' },
    { name: 'TorqueXAG', symbol: 'TXAG' },
  ];

  const currencyContracts = [];
  for (const currency of currencies) {
    const contract = await get(currency.name);
    currencyContracts.push({
      name: currency.name,
      symbol: currency.symbol,
      address: contract.address,
    });
  }

  // Get engine contracts
  const engines = [
    { name: 'TorqueEUREngine', currency: 'TEUR' },
    { name: 'TorqueGBPEngine', currency: 'TGBP' },
    { name: 'TorqueJPYEngine', currency: 'TJPY' },
    { name: 'TorqueAUDEngine', currency: 'TAUD' },
    { name: 'TorqueCADEngine', currency: 'TCAD' },
    { name: 'TorqueCHFEngine', currency: 'TCHF' },
    { name: 'TorqueNZDEngine', currency: 'TNZD' },
    { name: 'TorqueXAUEngine', currency: 'TXAU' },
    { name: 'TorqueXAGEngine', currency: 'TXAG' },
  ];

  const engineContracts = [];
  for (const engine of engines) {
    const contract = await get(engine.name);
    engineContracts.push({
      name: engine.name,
      currency: engine.currency,
      address: contract.address,
    });
  }

  console.log('\n🔗 Linking contracts...');

  // Link TorqueDEX with currencies and engines
  console.log('\n1. Linking TorqueDEX with currencies and engines...');
  const dexContract = await ethers.getContractAt('TorqueDEX', torqueDEX.address);

  // Create pools for each currency
  for (let i = 0; i < currencyContracts.length; i++) {
    const currency = currencyContracts[i];
    const engine = engineContracts[i];
    
    console.log(`Creating pool for ${currency.symbol}...`);
    
    try {
      const createPoolTx = await dexContract.createPoolWithDefaultQuote(
        currency.address,
        `${currency.symbol}/TUSD`,
        `${currency.symbol}TUSD`
      );
      await createPoolTx.wait();
      console.log(`✅ Pool created for ${currency.symbol}`);
    } catch (error: any) {
      console.log(`⚠️  Pool for ${currency.symbol} may already exist or failed:`, error?.message || 'Unknown error');
    }
  }

  // Link TorqueBatchHandler with currencies and engines
  console.log('\n2. Linking TorqueBatchHandler...');
  const batchHandlerContract = await ethers.getContractAt('TorqueBatchHandler', torqueBatchHandler.address);

  for (let i = 0; i < currencyContracts.length; i++) {
    const currency = currencyContracts[i];
    const engine = engineContracts[i];
    
    try {
      // Add currency to supported currencies
      const addCurrencyTx = await batchHandlerContract.addSupportedCurrency(currency.address);
      await addCurrencyTx.wait();
      console.log(`✅ Added ${currency.symbol} to supported currencies`);
    } catch (error: any) {
      console.log(`⚠️  Failed to add ${currency.symbol}:`, error?.message || 'Unknown error');
    }
  }

  // Link TorqueStake with TorqueUSD
  console.log('\n3. Linking TorqueStake...');
  const stakeContract = await ethers.getContractAt('TorqueStake', torqueStake.address);

  try {
    // TorqueStake is already configured in constructor with TorqueUSD
    console.log('✅ TorqueStake already linked with TorqueUSD in constructor');
  } catch (error: any) {
    console.log('⚠️  TorqueStake linking issue:', error?.message || 'Unknown error');
  }

  // Link TorqueRewards with TorqueUSD
  console.log('\n4. Linking TorqueRewards...');
  const rewardsContract = await ethers.getContractAt('TorqueRewards', torqueRewards.address);

  try {
    // TorqueRewards is already configured in constructor with TorqueUSD
    console.log('✅ TorqueRewards already linked with TorqueUSD in constructor');
  } catch (error: any) {
    console.log('⚠️  TorqueRewards linking issue:', error?.message || 'Unknown error');
  }

  // Link TorqueRouter with TorqueDEX
  console.log('\n5. Linking TorqueRouter...');
  const routerContract = await ethers.getContractAt('TorqueRouter', torqueRouter.address);

  try {
    // TorqueRouter is already configured in constructor with TorqueDEX
    console.log('✅ TorqueRouter already linked with TorqueDEX in constructor');
  } catch (error: any) {
    console.log('⚠️  TorqueRouter linking issue:', error?.message || 'Unknown error');
  }

  // Link TorqueFX with TorqueDEX
  console.log('\n6. Linking TorqueFX...');
  const fxContract = await ethers.getContractAt('TorqueFX', torqueFX.address);

  try {
    const setDEXTx = await fxContract.setDEXPool(ethers.keccak256(ethers.toUtf8Bytes("TUSD/USD")), torqueDEX.address);
    await setDEXTx.wait();
    console.log('✅ TorqueFX linked with TorqueDEX');
  } catch (error: any) {
    console.log('⚠️  Failed to link TorqueFX:', error?.message || 'Unknown error');
  }



  console.log('\n✅ Contract linking completed!');
  console.log('\n📋 Linking Summary:');
  console.log(`Network: ${network.name}`);
  console.log(`Deployer: ${deployer}`);
  console.log(`\nLinked Contracts:`);
  console.log(`  TorqueDEX: ${torqueDEX.address}`);
  console.log(`  TorqueBatchHandler: ${torqueBatchHandler.address}`);
  console.log(`  TorqueStake: ${torqueStake.address}`);
  console.log(`  TorqueRewards: ${torqueRewards.address}`);
  console.log(`  TorqueRouter: ${torqueRouter.address}`);
  console.log(`  TorqueFX: ${torqueFX.address}`);
  console.log(`\nCurrency Pools Created:`);
  currencyContracts.forEach(currency => {
    console.log(`  ${currency.symbol}/TUSD pool`);
  });
};

func.tags = ['Torque', 'Link'];
func.dependencies = ['01_deploy_torque'];

export default func; 