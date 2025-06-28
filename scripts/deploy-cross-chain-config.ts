import { ethers } from "hardhat";
import { layerzeroMainnetEndpoints } from "../hardhat.config";

// Cross-chain configuration script for TorqueBatchMinter
// This script should be run after deploying to all chains

const CHAINS = [
  { name: "ethereum", chainId: 1 },
  { name: "arbitrum", chainId: 42161 },
  { name: "optimism", chainId: 10 },
  { name: "polygon", chainId: 137 },
  { name: "base", chainId: 8453 },
  { name: "sonic", chainId: 146 },
  { name: "abstract", chainId: 2741 },
  { name: "bsc", chainId: 56 },
  { name: "hyperevm", chainId: 999 },
  { name: "fraxtal", chainId: 252 },
  { name: "avalanche", chainId: 43114 },
];

interface DeploymentData {
  chainId: number;
  batchMinter: string;
  currencies: { [key: string]: string };
  engines: { [key: string]: string };
  error?: string; // Optional error property for failed deployments
}

async function main() {
  console.log("=== TORQUE BATCH MINTER CROSS-CHAIN CONFIGURATION ===");
  
  // Load deployment results from previous deployment
  const fs = require('fs');
  let deploymentResults: { [chainName: string]: DeploymentData };
  
  try {
    const data = fs.readFileSync('deployment-results.json', 'utf8');
    deploymentResults = JSON.parse(data);
  } catch (error) {
    console.error("❌ Could not load deployment-results.json");
    console.error("Please run deploy-all-chains.ts first");
    process.exit(1);
  }

  const [deployer] = await ethers.getSigners();
  console.log("Configuring with deployer:", deployer.address);

  // Configure cross-chain connections for each chain
  for (const chain of CHAINS) {
    const chainName = chain.name;
    const chainData = deploymentResults[chainName];
    
    if (!chainData || chainData.error) {
      console.log(`⚠️  Skipping ${chainName} - no deployment data`);
      continue;
    }

    console.log(`\n🔗 Configuring ${chainName.toUpperCase()} cross-chain connections...`);
    
    try {
      // Connect to the batch minter on this chain
      const batchMinter = await ethers.getContractAt("TorqueBatchMinter", chainData.batchMinter);
      
      // Configure engine addresses for all other chains
      await configureCrossChainEngines(batchMinter, deploymentResults, chainName);
      
      console.log(`✅ ${chainName} cross-chain configuration completed`);
      
    } catch (error: any) {
      console.error(`❌ Failed to configure ${chainName}:`, error.message);
    }
  }

  console.log("\n🎉 Cross-chain configuration completed!");
  console.log("Batch minter is now ready for cross-chain operations");
}

async function configureCrossChainEngines(
  batchMinter: any,
  deploymentResults: { [chainName: string]: DeploymentData },
  currentChainName: string
) {
  const currencyNames = ["USD", "EUR", "GBP", "JPY", "AUD", "CAD", "CHF", "NZD", "XAU", "XAG"];
  
  for (const targetChain of CHAINS) {
    const targetChainName = targetChain.name;
    
    // Skip self
    if (targetChainName === currentChainName) {
      continue;
    }
    
    const targetChainData = deploymentResults[targetChainName];
    if (!targetChainData || targetChainData.error) {
      console.log(`   ⚠️  Skipping ${targetChainName} - no deployment data`);
      continue;
    }
    
    console.log(`   🔗 Configuring ${targetChainName} (Chain ID: ${targetChain.chainId})`);
    
    // Set engine addresses for each currency on the target chain
    for (const currencyName of currencyNames) {
      const currencyAddress = targetChainData.currencies[currencyName];
      const engineAddress = targetChainData.engines[currencyName];
      
      if (currencyAddress && engineAddress) {
        try {
          const tx = await batchMinter.setEngineAddress(
            currencyAddress,
            targetChain.chainId,
            engineAddress
          );
          await tx.wait();
          console.log(`     ✅ ${currencyName}: ${engineAddress}`);
        } catch (error: any) {
          console.log(`     ❌ ${currencyName}: ${error.message}`);
        }
      }
    }
  }
}

// Utility function to verify cross-chain configuration
async function verifyCrossChainConfig() {
  console.log("\n🔍 Verifying cross-chain configuration...");
  
  const fs = require('fs');
  const deploymentResults = JSON.parse(fs.readFileSync('deployment-results.json', 'utf8'));
  
  for (const chain of CHAINS) {
    const chainName = chain.name;
    const chainData = deploymentResults[chainName];
    
    if (!chainData || chainData.error) continue;
    
    console.log(`\n📋 ${chainName.toUpperCase()} Configuration:`);
    
    try {
      const batchMinter = await ethers.getContractAt("TorqueBatchMinter", chainData.batchMinter);
      
      // Get supported currencies
      const currencyNames = ["USD", "EUR", "GBP", "JPY", "AUD", "CAD", "CHF", "NZD", "XAU", "XAG"];
      
      for (const currencyName of currencyNames) {
        const currencyAddress = chainData.currencies[currencyName];
        const isSupported = await batchMinter.supportedCurrencies(currencyAddress);
        
        if (isSupported) {
          console.log(`   ✅ ${currencyName}: Supported`);
          
          // Check engine addresses for each chain
          for (const targetChain of CHAINS) {
            const engineAddress = await batchMinter.engineAddresses(currencyAddress, targetChain.chainId);
            if (engineAddress !== ethers.ZeroAddress) {
              console.log(`     🔗 ${targetChain.name}: ${engineAddress}`);
            }
          }
        } else {
          console.log(`   ❌ ${currencyName}: Not supported`);
        }
      }
      
    } catch (error: any) {
      console.log(`   ❌ Error: ${error.message}`);
    }
  }
}

// Add verification to main if needed
if (process.argv.includes("--verify")) {
  verifyCrossChainConfig()
    .then(() => process.exit(0))
    .catch((error) => {
      console.error(error);
      process.exit(1);
    });
} else {
  main()
    .then(() => process.exit(0))
    .catch((error) => {
      console.error(error);
      process.exit(1);
    });
} 