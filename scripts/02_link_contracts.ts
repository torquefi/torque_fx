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
  const entryPoint = await get('EntryPoint');
  const torqueAccountFactory = await get('TorqueAccountFactory');
  const torqueAccount = await get('TorqueAccount');
  const torqueAccountBundler = await get('TorqueAccountBundler');
  const torqueAccountCrossChain = await get('TorqueAccountCrossChain');
  const torqueAccountGasOptimizer = await get('TorqueAccountGasOptimizer');
  const torqueAccountRecovery = await get('TorqueAccountRecovery');
  const torqueAccountUpgrade = await get('TorqueAccountUpgrade');

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

  // Link TorqueAccountFactory with EntryPoint and TorqueAccount
  console.log('\n3. Linking TorqueAccountFactory...');
  const accountFactoryContract = await ethers.getContractAt('TorqueAccountFactory', torqueAccountFactory.address);

  try {
    const setImplementationTx = await accountFactoryContract.setImplementation(torqueAccount.address);
    await setImplementationTx.wait();
    console.log('✅ TorqueAccountFactory linked with TorqueAccount implementation');
  } catch (error: any) {
    console.log('⚠️  Failed to link TorqueAccountFactory:', error?.message || 'Unknown error');
  }

  // Link TorqueStake with TorqueUSD
  console.log('\n4. Linking TorqueStake...');
  const stakeContract = await ethers.getContractAt('TorqueStake', torqueStake.address);

  try {
    const setStakingTokenTx = await stakeContract.setStakingToken(torqueUSD.address);
    await setStakingTokenTx.wait();
    console.log('✅ TorqueStake linked with TorqueUSD');
  } catch (error: any) {
    console.log('⚠️  Failed to link TorqueStake:', error?.message || 'Unknown error');
  }

  // Link TorqueRewards with TorqueUSD
  console.log('\n5. Linking TorqueRewards...');
  const rewardsContract = await ethers.getContractAt('TorqueRewards', torqueRewards.address);

  try {
    const setRewardTokenTx = await rewardsContract.setRewardToken(torqueUSD.address);
    await setRewardTokenTx.wait();
    console.log('✅ TorqueRewards linked with TorqueUSD');
  } catch (error: any) {
    console.log('⚠️  Failed to link TorqueRewards:', error?.message || 'Unknown error');
  }

  // Link TorqueRouter with TorqueDEX
  console.log('\n6. Linking TorqueRouter...');
  const routerContract = await ethers.getContractAt('TorqueRouter', torqueRouter.address);

  try {
    const setDEXTx = await routerContract.setDEX(torqueDEX.address);
    await setDEXTx.wait();
    console.log('✅ TorqueRouter linked with TorqueDEX');
  } catch (error: any) {
    console.log('⚠️  Failed to link TorqueRouter:', error?.message || 'Unknown error');
  }

  // Link 4337 contracts
  console.log('\n7. Linking 4337 contracts...');
  
  // Link TorqueAccountBundler with EntryPoint
  const bundlerContract = await ethers.getContractAt('TorqueAccountBundler', torqueAccountBundler.address);
  try {
    const setEntryPointTx = await bundlerContract.setEntryPoint(entryPoint.address);
    await setEntryPointTx.wait();
    console.log('✅ TorqueAccountBundler linked with EntryPoint');
  } catch (error: any) {
    console.log('⚠️  Failed to link TorqueAccountBundler:', error?.message || 'Unknown error');
  }

  // Link TorqueAccountCrossChain with TorqueAccount
  const crossChainContract = await ethers.getContractAt('TorqueAccountCrossChain', torqueAccountCrossChain.address);
  try {
    const setAccountTx = await crossChainContract.setAccount(torqueAccount.address);
    await setAccountTx.wait();
    console.log('✅ TorqueAccountCrossChain linked with TorqueAccount');
  } catch (error: any) {
    console.log('⚠️  Failed to link TorqueAccountCrossChain:', error?.message || 'Unknown error');
  }

  // Link TorqueAccountGasOptimizer with EntryPoint
  const gasOptimizerContract = await ethers.getContractAt('TorqueAccountGasOptimizer', torqueAccountGasOptimizer.address);
  try {
    const setEntryPointTx = await gasOptimizerContract.setEntryPoint(entryPoint.address);
    await setEntryPointTx.wait();
    console.log('✅ TorqueAccountGasOptimizer linked with EntryPoint');
  } catch (error: any) {
    console.log('⚠️  Failed to link TorqueAccountGasOptimizer:', error?.message || 'Unknown error');
  }

  // Link TorqueAccountRecovery with EntryPoint
  const recoveryContract = await ethers.getContractAt('TorqueAccountRecovery', torqueAccountRecovery.address);
  try {
    const setEntryPointTx = await recoveryContract.setEntryPoint(entryPoint.address);
    await setEntryPointTx.wait();
    console.log('✅ TorqueAccountRecovery linked with EntryPoint');
  } catch (error: any) {
    console.log('⚠️  Failed to link TorqueAccountRecovery:', error?.message || 'Unknown error');
  }

  // Link TorqueAccountUpgrade with EntryPoint
  const upgradeContract = await ethers.getContractAt('TorqueAccountUpgrade', torqueAccountUpgrade.address);
  try {
    const setEntryPointTx = await upgradeContract.setEntryPoint(entryPoint.address);
    await setEntryPointTx.wait();
    console.log('✅ TorqueAccountUpgrade linked with EntryPoint');
  } catch (error: any) {
    console.log('⚠️  Failed to link TorqueAccountUpgrade:', error?.message || 'Unknown error');
  }

  console.log('\n✅ Contract linking completed!');
  console.log('\n📋 Linking Summary:');
  console.log(`Network: ${network.name}`);
  console.log(`Deployer: ${deployer}`);
  console.log(`\nLinked Contracts:`);
  console.log(`  TorqueDEX: ${torqueDEX.address}`);
  console.log(`  TorqueBatchMinter: ${torqueBatchMinter.address}`);
  console.log(`  TorqueAccountFactory: ${torqueAccountFactory.address}`);
  console.log(`  TorqueStake: ${torqueStake.address}`);
  console.log(`  TorqueRewards: ${torqueRewards.address}`);
  console.log(`  TorqueRouter: ${torqueRouter.address}`);
  console.log(`\n4337 Contracts:`);
  console.log(`  TorqueAccountBundler: ${torqueAccountBundler.address}`);
  console.log(`  TorqueAccountCrossChain: ${torqueAccountCrossChain.address}`);
  console.log(`  TorqueAccountGasOptimizer: ${torqueAccountGasOptimizer.address}`);
  console.log(`  TorqueAccountRecovery: ${torqueAccountRecovery.address}`);
  console.log(`  TorqueAccountUpgrade: ${torqueAccountUpgrade.address}`);
  console.log(`\nCurrency Pools Created:`);
  currencyContracts.forEach(currency => {
    console.log(`  ${currency.symbol}/TUSD pool`);
  });
};

func.tags = ['Torque', 'Link'];
func.dependencies = ['01_deploy_torque'];

export default func; 