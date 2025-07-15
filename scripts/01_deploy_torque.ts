import { HardhatRuntimeEnvironment } from 'hardhat/types';
import { DeployFunction } from 'hardhat-deploy/types';
import { ethers } from 'hardhat';

const func: DeployFunction = async function (hre: HardhatRuntimeEnvironment) {
  const { deployments, getNamedAccounts, network } = hre;
  const { deploy } = deployments;
  const { deployer } = await getNamedAccounts();

  console.log(`\nDeploying Torque contracts to ${network.name}...`);
  console.log(`Deployer: ${deployer}`);

  // Get LayerZero endpoint for this network
  const lzEndpoint = await getLZEndpoint(network.config.chainId);
  console.log(`LayerZero Endpoint: ${lzEndpoint}`);

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
  const engines = [
    { name: 'Torque USD Engine', contract: 'TorqueUSDEngine' },
    { name: 'Torque EUR Engine', contract: 'TorqueEUREngine' },
    { name: 'Torque GBP Engine', contract: 'TorqueGBPEngine' },
    { name: 'Torque JPY Engine', contract: 'TorqueJPYEngine' },
    { name: 'Torque AUD Engine', contract: 'TorqueAUDEngine' },
    { name: 'Torque CAD Engine', contract: 'TorqueCADEngine' },
    { name: 'Torque CHF Engine', contract: 'TorqueCHFEngine' },
    { name: 'Torque NZD Engine', contract: 'TorqueNZDEngine' },
    { name: 'Torque XAU Engine', contract: 'TorqueXAUEngine' },
    { name: 'Torque XAG Engine', contract: 'TorqueXAGEngine' },
  ];

  const deployedEngines = [];
  for (const engine of engines) {
    const deployed = await deploy(engine.contract, {
      from: deployer,
      args: [lzEndpoint, deployer],
      log: true,
      waitConfirmations: 1,
    });
    deployedEngines.push({
      name: engine.name,
      address: deployed.address,
      contract: engine.contract,
    });
    console.log(`${engine.name} deployed to: ${deployed.address}`);
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
  console.log(`\nCurrency Engines:`);
  deployedEngines.forEach(engine => {
    console.log(`  ${engine.name}: ${engine.address}`);
  });

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
    2741: '0x3c2269811836af69497E5F486A85D7316753cf62', // Abstract
    56: '0x3c2269811836af69497E5F486A85D7316753cf62', // BSC

    252: '0x3c2269811836af69497E5F486A85D7316753cf62', // Fraxtal
    43114: '0x3c2269811836af69497E5F486A85D7316753cf62', // Avalanche
    // Testnet
    11155111: '0xae92d5aD7583AD66E49A0c67BAd18F6ba52dDDc1', // Sepolia
    421613: '0x6EDCE65403992e310A62460808c4b910D972f10f', // Arbitrum Sepolia
    84531: '0x6EDCE65403992e310A62460808c4b910D972f10f', // Base Goerli
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