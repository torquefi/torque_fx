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
  const torqueBatchMinter = await get('TorqueBatchMinter');
  const torqueFX = await get('TorqueFX');
  const torquePayments = await get('TorquePayments');
  const torqueGateway = await get('TorqueGateway');

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
      const createPoolTx = await dexContract.createPoolWithDefaults(
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

  // Link TorqueBatchMinter with currencies and engines
  console.log('\n2. Linking TorqueBatchMinter...');
  const batchMinterContract = await ethers.getContractAt('TorqueBatchMinter', torqueBatchMinter.address);

  for (let i = 0; i < currencyContracts.length; i++) {
    const currency = currencyContracts[i];
    const engine = engineContracts[i];
    
    try {
      const linkCurrencyTx = await batchMinterContract.linkCurrency(currency.address, engine.address);
      await linkCurrencyTx.wait();
      console.log(`✅ Linked ${currency.symbol} with ${engine.name}`);
    } catch (error: any) {
      console.log(`⚠️  Failed to link ${currency.symbol}:`, error?.message || 'Unknown error');
    }
  }

  // Link TorqueStake with TorqueUSD
  console.log('\n3. Linking TorqueStake...');
  const stakeContract = await ethers.getContractAt('TorqueStake', torqueStake.address);

  try {
    const setStakingTokenTx = await stakeContract.setStakingToken(torqueUSD.address);
    await setStakingTokenTx.wait();
    console.log('✅ TorqueStake linked with TorqueUSD');
  } catch (error: any) {
    console.log('⚠️  Failed to link TorqueStake:', error?.message || 'Unknown error');
  }

  // Link TorqueRewards with TorqueUSD
  console.log('\n4. Linking TorqueRewards...');
  const rewardsContract = await ethers.getContractAt('TorqueRewards', torqueRewards.address);

  try {
    const setRewardTokenTx = await rewardsContract.setRewardToken(torqueUSD.address);
    await setRewardTokenTx.wait();
    console.log('✅ TorqueRewards linked with TorqueUSD');
  } catch (error: any) {
    console.log('⚠️  Failed to link TorqueRewards:', error?.message || 'Unknown error');
  }

  // Link TorqueRouter with TorqueDEX
  console.log('\n5. Linking TorqueRouter...');
  const routerContract = await ethers.getContractAt('TorqueRouter', torqueRouter.address);

  try {
    const setDEXTx = await routerContract.setDEX(torqueDEX.address);
    await setDEXTx.wait();
    console.log('✅ TorqueRouter linked with TorqueDEX');
  } catch (error: any) {
    console.log('⚠️  Failed to link TorqueRouter:', error?.message || 'Unknown error');
  }

  // Link TorqueFX with TorqueDEX
  console.log('\n6. Linking TorqueFX...');
  const fxContract = await ethers.getContractAt('TorqueFX', torqueFX.address);

  try {
    const setDEXTx = await fxContract.setDEXPool(ethers.keccak256(ethers.toUtf8Bytes("ETH/USD")), torqueDEX.address);
    await setDEXTx.wait();
    console.log('✅ TorqueFX linked with TorqueDEX');
  } catch (error: any) {
    console.log('⚠️  Failed to link TorqueFX:', error?.message || 'Unknown error');
  }

  // Link TorquePayments with TorqueUSD
  console.log('\n7. Linking TorquePayments...');
  const paymentsContract = await ethers.getContractAt('TorquePayments', torquePayments.address);

  // Add all Torque currencies as supported
  const allTorqueCurrencies = [
    { address: torqueUSD.address, symbol: 'TUSD' },
    ...currencyContracts.map(currency => ({
      address: currency.address,
      symbol: currency.symbol
    }))
  ];

  for (const currency of allTorqueCurrencies) {
    try {
      const setCurrencyTx = await paymentsContract.setTorqueCurrency(currency.address, true);
      await setCurrencyTx.wait();
      console.log(`✅ ${currency.symbol} added as supported currency`);
    } catch (error: any) {
      console.log(`⚠️  Failed to add ${currency.symbol}:`, error?.message || 'Unknown error');
    }
  }

  // Link TorqueGateway with TorquePayments
  console.log('\n8. Linking TorqueGateway...');
  const gatewayContract = await ethers.getContractAt('TorqueGateway', torqueGateway.address);

  try {
    const setPaymentsTx = await gatewayContract.setPaymentsContract(torquePayments.address);
    await setPaymentsTx.wait();
    console.log('✅ TorqueGateway linked with TorquePayments');
  } catch (error: any) {
    console.log('⚠️  Failed to link TorqueGateway:', error?.message || 'Unknown error');
  }

  console.log('\n✅ Contract linking completed!');
  console.log('\n📋 Linking Summary:');
  console.log(`Network: ${network.name}`);
  console.log(`Deployer: ${deployer}`);
  console.log(`\nLinked Contracts:`);
  console.log(`  TorqueDEX: ${torqueDEX.address}`);
  console.log(`  TorqueBatchMinter: ${torqueBatchMinter.address}`);
  console.log(`  TorqueStake: ${torqueStake.address}`);
  console.log(`  TorqueRewards: ${torqueRewards.address}`);
  console.log(`  TorqueRouter: ${torqueRouter.address}`);
  console.log(`  TorqueFX: ${torqueFX.address}`);
  console.log(`  TorquePayments: ${torquePayments.address}`);
  console.log(`  TorqueGateway: ${torqueGateway.address}`);
  console.log(`\nCurrency Pools Created:`);
  currencyContracts.forEach(currency => {
    console.log(`  ${currency.symbol}/TUSD pool`);
  });
};

func.tags = ['Torque', 'Link'];
func.dependencies = ['01_deploy_torque'];

export default func; 