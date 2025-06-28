# Torque FX Deployment Guide

## Overview

This guide covers the deployment of Torque across multiple chains, including the cross-chain batch minting functionality.

## Prerequisites

1. **Environment Setup**
   ```bash
   npm install
   cp .env.example .env
   ```

2. **Environment Variables**
   ```env
   PRIVATE_KEY=your_private_key_here
   ETHEREUM_RPC_URL=https://eth-mainnet.alchemyapi.io/v2/your_key
   ARBITRUM_RPC_URL=https://arb-mainnet.g.alchemy.com/v2/your_key
   OPTIMISM_RPC_URL=https://opt-mainnet.g.alchemy.com/v2/your_key
   POLYGON_RPC_URL=https://polygon-mainnet.g.alchemy.com/v2/your_key
   BASE_RPC_URL=https://mainnet.base.org
   SONIC_RPC_URL=https://mainnet.sonic.oasys.games
   ABSTRACT_RPC_URL=https://rpc.abstract.money
   BSC_RPC_URL=https://bsc-dataseed.binance.org
   HYPEREVM_RPC_URL=https://rpc.hyperevm.com
   FRAXTAL_RPC_URL=https://rpc.fraxtal.com
   AVALANCHE_RPC_URL=https://api.avax.network/ext/bc/C/rpc
   ```

## Deployment Flow

### 1. Single Chain Deployment

For testing or single-chain deployment:

```bash
# Deploy to current network
npx hardhat run scripts/deploy.ts --network ethereum
```

This deploys:
- ✅ Mock USDC and Price Feed
- ✅ All Torque currencies (USD, EUR, GBP, JPY, AUD, CAD, CHF, NZD, XAU, XAG)
- ✅ All Torque engines
- ✅ **TorqueBatchMinter** (configured for current chain)
- ✅ Main Torque token
- ✅ ERC-4337 contracts (EntryPoint, TorqueAccount, etc.)
- ✅ DEX and other infrastructure

### 2. Multi-Chain Deployment

For production deployment across all supported chains:

```bash
# Deploy to all chains
npx hardhat run scripts/deploy-all-chains.ts
```

This deploys the same contracts across all 11 chains:
- Ethereum (Chain ID: 1)
- Arbitrum (Chain ID: 42161)
- Optimism (Chain ID: 10)
- Polygon (Chain ID: 137)
- Base (Chain ID: 8453)
- Sonic (Chain ID: 146)
- Abstract (Chain ID: 2741)
- BSC (Chain ID: 56)
- HyperEVM (Chain ID: 999)
- Fraxtal (Chain ID: 252)
- Avalanche (Chain ID: 43114)

### 3. Cross-Chain Configuration

After multi-chain deployment, configure cross-chain connections:

```bash
# Configure cross-chain batch minter connections
npx hardhat run scripts/deploy-cross-chain-config.ts --network ethereum
```

This script:
- 🔗 Connects batch minters across all chains
- 📋 Sets engine addresses for each currency on each chain
- ✅ Enables cross-chain minting functionality

### 4. Verification

Verify the cross-chain configuration:

```bash
# Verify cross-chain setup
npx hardhat run scripts/deploy-cross-chain-config.ts --network ethereum --verify
```

## TorqueBatchMinter Features

### What It Enables

1. **Cross-Chain Batch Minting**
   - Mint tokens across multiple chains in a single transaction
   - Support for up to 50 chains simultaneously (flexible for future expansion)
   - Gas-optimized batch processing

2. **Multi-Currency Support**
   - All 10 Torque currencies supported
   - USD, EUR, GBP, JPY, AUD, CAD, CHF, NZD, XAU, XAG

3. **LayerZero Integration**
   - Secure cross-chain communication
   - Automatic message routing
   - Built-in error handling

### Usage Example

```solidity
// Mint TorqueEUR across multiple chains
batchMinter.batchMint(
    torqueEURAddress,           // Currency to mint
    1000 * 1e6,                // Total collateral (1000 USDC)
    [1, 42161, 10],            // Ethereum, Arbitrum, Optimism
    [500, 300, 200],           // Amounts per chain
    [adapterParams1, adapterParams2, adapterParams3] // Gas params
);
```

### Gas Estimation

```solidity
// Get gas estimate for batch operation
uint256 totalGas = batchMinter.getBatchMintQuote(
    [1, 42161, 10],            // Destination chains
    [adapterParams1, adapterParams2, adapterParams3] // Gas params
);
```

## Contract Addresses

After deployment, addresses are saved to `deployment-results.json`:

```json
{
  "ethereum": {
    "chainId": 1,
    "batchMinter": "0x...",
    "currencies": {
      "USD": "0x...",
      "EUR": "0x...",
      // ... all currencies
    },
    "engines": {
      "USD": "0x...",
      "EUR": "0x...",
      // ... all engines
    }
  }
  // ... other chains
}
```

## Security Features

### Checks-Effects-Interactions Pattern
- ✅ All functions follow CEI pattern
- ✅ ReentrancyGuard protection
- ✅ Proper input validation
- ✅ Event emissions for transparency

### Admin Controls
- ✅ Owner-only configuration functions
- ✅ Emergency withdrawal capabilities
- ✅ Configurable batch sizes
- ✅ Currency whitelisting

## Testing

```bash
# Run all tests
npm test

# Test batch minter specifically
npx hardhat test test/TorqueBatchMinter.test.ts
```

## Monitoring

### Events to Monitor
- `BatchMintInitiated`: When batch minting starts
- `BatchMintCompleted`: When minting succeeds on a chain
- `BatchMintFailed`: When minting fails (with reason)

### Key Metrics
- Cross-chain transaction success rates
- Gas costs per batch operation
- Currency distribution across chains
- Error rates and failure reasons

## Troubleshooting

### Common Issues

1. **LayerZero Endpoint Issues**
   - Verify endpoint addresses in `hardhat.config.ts`
   - Check network connectivity

2. **Cross-Chain Configuration Failures**
   - Ensure all chains are deployed first
   - Verify deployer has sufficient gas on all chains

3. **Batch Minting Failures**
   - Check collateral token approvals
   - Verify engine addresses are set correctly
   - Monitor LayerZero message delivery

### Support

For deployment issues:
1. Check deployment logs in `deployment-results.json`
2. Verify environment variables
3. Ensure sufficient gas on all networks
4. Check LayerZero endpoint connectivity

| Functionality | TorqueAccount Required | Reason |
|---------------|----------------------|---------|
| **Engine Minting** | ❌ NO | Direct collateral deposit |
| **Batch Minting** | ❌ NO | Cross-chain minting |
| **Staking** | ❌ NO | Direct token staking |
| **DEX Liquidity** | ❌ NO | Direct liquidity provision |
| **Trading** | ✅ YES | Account-based positions |
| **Account Operations** | ✅ YES | Self-referential | 