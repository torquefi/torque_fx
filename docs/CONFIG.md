# Torque FX Configuration

This directory contains all configuration files for the Torque FX protocol, organized by functionality and network support.

## Overview

The configuration system is designed to be:
- **Chain Agnostic**: Support for multiple chains and networks
- **Extensible**: Easy to add new networks, collaterals, and contracts
- **Centralized**: Single source of truth for all protocol configurations

## File Structure

```
config/
├── chains.ts          # Chain configurations and network metadata
├── collateral.ts      # Collateral token configurations
├── contracts.ts       # Contract addresses and deployment status
├── utils.ts          # Utility functions and helpers
├── index.ts          # Main export file
```

## Quick Start

```typescript
import { 
  CHAINS, 
  collateralTokens, 
  getChainById,
  getChainByName 
} from './config';

// Get information about a specific network
const ethereumInfo = getChainById(1);

// Get chain by name
const arbitrumInfo = getChainByName('arbitrum');

// Get all collateral tokens
const allCollaterals = collateralTokens;
```

## Supported Networks

### Mainnet Networks
- **Ethereum** (1) - Main Ethereum network
- **Arbitrum** (42161) - Arbitrum One
- **Optimism** (10) - Optimism
- **Polygon** (137) - Polygon PoS
- **Base** (8453) - Base
- **BSC** (56) - Binance Smart Chain
- **Avalanche** (43114) - Avalanche C-Chain
- **Sonic** (146) - Sonic
- **Abstract** (2741) - Abstract

- **Fraxtal** (252) - Fraxtal

### Testnet Networks
- **Sepolia** (11155111) - Ethereum testnet
- **Arbitrum Sepolia** (421614) - Arbitrum testnet
- **Base Goerli** (84531) - Base testnet

## Supported Collaterals

### Stablecoins
- **USDC** - USD Coin
- **USDT** - Tether USD
- **USDS** - Sky USD
- **PYUSD** - PayPal USD
- **WYST** - Wyoming Stable

### Crypto Assets
- **WETH** - Wrapped Ether
- **WBTC** - Wrapped Bitcoin
- **LINK** - Chainlink
- **cbBTC** - Coinbase Bitcoin
- **cbETH** - Coinbase Ether

### Liquid Staking Tokens
- **weETH** - Ether.fi ETH
- **rsETH** - Kelp DAO ETH
- **stETH** - Lido ETH
- **mETH** - Mantle ETH
- **stBTC** - Babylon BTC
- **vBTC** - Corn BTC

## Usage Examples

### Getting Network Information

```typescript
import { CHAINS, getChainById, getChainByName } from './config';

// Get comprehensive info for a single network
const ethereumInfo = getChainById(1);
console.log(ethereumInfo?.name); // "Ethereum"

// Get chain by name
const arbitrumInfo = getChainByName('arbitrum');

// Get all chains
const allChains = Object.values(CHAINS);
```

### Working with Collaterals

```typescript
import { collateralTokens } from './config';

// Get collateral configuration
const usdcConfig = collateralTokens.find(token => token.symbol === 'USDC');
console.log(usdcConfig?.contracts.ethereum); // USDC address on Ethereum

// Get all networks that support USDC
const usdcNetworks = Object.keys(usdcConfig?.contracts || {});

// Check if USDC is supported on Polygon
const isSupported = usdcConfig?.contracts.polygon !== undefined;
```

### Contract Addresses

```typescript
import { 
  getContractAddress, 
  getEngineAddress, 
  getCurrencyAddress,
  updateDeployment,
  getDeploymentByNetwork,
  getDeployedNetworks 
} from './config';

// Get specific contract address
const routerAddress = getContractAddress('ethereum', 'torqueRouter');

// Get engine address for USD
const usdEngine = getEngineAddress('arbitrum', 'USD');

// Get currency token address
const eurToken = getCurrencyAddress('polygon', 'EUR');

// Get deployment info for a network
const ethereumDeployment = getDeploymentByNetwork('ethereum');

// Get all deployed networks
const deployedNetworks = getDeployedNetworks();

// Update deployment after contract deployment
updateDeployment('ethereum', {
  torqueFX: '0x1234...',
  torqueRouter: '0x5678...'
}, true, '2024-01-01', '0xdeployer', '0xtxhash');
```

### Network Filtering

```typescript
import { filterNetworks, getNetworksByType } from './config';

// Get only deployed networks
const deployedNetworks = filterNetworks({ deployed: true });

// Get only mainnet networks
const mainnetNetworks = filterNetworks({ testnet: false });

// Get networks that support USDC
const usdcNetworks = filterNetworks({ hasCollateral: 'USDC' });

// Get networks grouped by type
const { mainnet, testnet } = getNetworksByType();
```

### Utility Functions

```typescript
import { 
  getRpcUrls, 
  getBlockExplorerUrl, 
  getLayerZeroEndpoint,
  formatNetworkName 
} from './config';

// Get RPC URLs for a network
const rpcUrls = getRpcUrls('ethereum');

// Get block explorer URL
const explorerUrl = getBlockExplorerUrl('arbitrum');

// Get LayerZero endpoint
const lzEndpoint = getLayerZeroEndpoint('polygon');

// Format network name for display
const displayName = formatNetworkName('arbitrum'); // "Arbitrum One"
```

## Adding New Networks

To add a new network, update the `CHAINS` object in `chains.ts`:

```typescript
export const CHAINS: Record<string, ChainConfig> = {
  // ... existing chains
  newNetwork: {
    id: 12345,
    name: 'New Network',
    network: 'new-network',
    nativeCurrency: {
      name: 'New Token',
      symbol: 'NEW',
      decimals: 18,
    },
    rpcUrls: {
      http: ['https://rpc.new-network.com'],
    },
    blockExplorers: {
      name: 'New Explorer',
      url: 'https://explorer.new-network.com',
      apiUrl: 'https://api.explorer.new-network.com',
    },
    layerZero: {
      endpointId: EndpointId.NEW_NETWORK_MAINNET,
      endpoint: '0x...',
    },
    testnet: false,
  },
};
```

Then add the deployment configuration in `contracts.ts`:

```typescript
export const MAINNET_DEPLOYMENTS: Record<string, DeploymentConfig> = {
  // ... existing deployments
  newNetwork: {
    chainId: 12345,
    network: 'new-network',
    addresses: {
      // ... contract addresses
    },
    deployed: false,
  },
};
```

## Adding New Collaterals

To add a new collateral token, update the `collateralTokens` array in `collateral.ts`:

```typescript
export const collateralTokens: CollateralToken[] = [
  // ... existing collaterals
  {
    symbol: "NEW_TOKEN",
    name: "New Token",
    contracts: {
      ethereum: "0x...",
      arbitrum: "0x...",
      // ... other networks
    },
    priceFeeds: {
      ethereum: "0x...",
      arbitrum: "0x...",
      // ... other networks
    }
  },
];
```

## Type Definitions

### ChainConfig
```typescript
interface ChainConfig {
  id: number;
  name: string;
  network: string;
  nativeCurrency: {
    name: string;
    symbol: string;
    decimals: number;
  };
  rpcUrls: {
    http: string[];
    webSocket?: string[];
  };
  blockExplorers: {
    name: string;
    url: string;
    apiUrl: string;
  };
  layerZero: {
    endpointId: EndpointId;
    endpoint: string;
  };
  testnet: boolean;
}
```

### CollateralToken
```typescript
interface CollateralToken {
  symbol: string;
  name: string;
  contracts: Record<string, string>; // chain -> contract address
  priceFeeds: Record<string, string>; // chain -> price feed address
}
```

### DeploymentConfig
```typescript
interface DeploymentConfig {
  chainId: number;
  network: string;
  addresses: ContractAddresses;
  deployed: boolean;
  deploymentDate?: string;
  deployer?: string;
  transactionHash?: string;
}
```

## Best Practices

1. **Always use the utility functions** instead of accessing configuration objects directly
2. **Validate network and collateral symbols** before using them
3. **Use TypeScript** to get full type safety and IntelliSense
4. **Update deployment status** after contract deployments
5. **Keep price feed addresses up to date** for accurate collateral valuations

## Contributing

When adding new configurations:

1. Update the appropriate configuration file
2. Add corresponding types if needed
3. Update this README with new examples
4. Test the configuration with the utility functions
5. Ensure all networks and collaterals are properly documented 