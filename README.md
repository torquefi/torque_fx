<p align="center">
  <img src="https://cdn.prod.website-files.com/6556f6be06fc2abb8a8da998/665ce0e7788b3d8fe85d1fed_torque-square%20copy%202.png" alt="Torque Logo" width="13.4%">
</p>
<p align="center">
  <i align="center">Smart contracts for Torque Protocol</i>
</p>

## Overview

Torque is a high-performance decentralized exchange (DEX) enabling foreign exchange and commodities trading across EVM-compatible networks. This repository contains the core contracts that power the protocol, including leveraged trading, AMM pools, and a comprehensive rewards system.

- **Website**: [torque.fi](https://torque.fi)
- **Documentation**: [docs.torque.fi](https://docs.torque.fi)
- **X (Twitter)**: [x.com/torquefi](https://x.com/torquefi)
- **Telegram**: [t.me/torquefi](https://t.me/torquefi)

## Features

- **fxAMM DEX**: Swap tokens and provide liquidity via TorqueDEX pools
- **Leveraged Trading**: Open long/short positions with up to 500x leverage
- **Liquidity Provision**: Provide DEX liquidity across stable and concentrated pools
- **Rewards**: Stake, earn, and claim rewards via Torque Rewards

## Architecture

- `Torque.sol`: Native ERC20 token with voting and omnichain support
- `TorqueDEX.sol`: AMM with concentrated and stable liquidity models
- `TorqueLP.sol`: LP token contract for DEX liquidity positions
- `TorqueRouter.sol`: Trading pair and price feed management
- `TorqueStake.sol`: Staking for LP and TORQ tokens with lock periods
- `TorqueBatchMinter.sol`: Batch minting for multiple destination chains
- `TorqueRewards.sol`: Flow-based rewards distribution (referral and cashback)
- `TorqueFX.sol`: Margin trading extension utilizing the DEX spot liquidity
- `currencies/`: Currency-specific contracts
- `engines/`: Currency-specific engines

## Configuration System

The project includes a comprehensive configuration system for managing networks, collateral, and contract addresses across multiple chains.

### Quick Start

```typescript
import { 
  getNetworkInfo, 
  getSupportedCollateralsForNetwork,
  getContractAddress 
} from './config';

// Get network information
const ethereumInfo = getNetworkInfo('ethereum');

// Get supported collaterals
const collaterals = getSupportedCollateralsForNetwork('arbitrum');

// Get contract addresses
const routerAddress = getContractAddress('ethereum', 'torqueRouter');
```

### Supported Networks

- **Mainnet**: Ethereum, Arbitrum, Optimism, Polygon, Base, BSC, Avalanche, Sonic, Abstract, HyperEVM, Fraxtal
- **Testnet**: Sepolia, Arbitrum Sepolia, Optimism Sepolia, Polygon Mumbai, Base Goerli

### Supported Collaterals

- **Stablecoins**: USDC, USDT, USDS, WYST, etc.
- **Other Assets**: cbBTC, cbETH, WETH, WBTC, LINK, etc.

For detailed configuration docs, see [`docs/config.md`](docs/CONFIG.md).

## Contract Addresses

Contract addresses are managed through the configuration system. Use the utility functions to access addresses:

```typescript
import { getContractAddress, getEngineAddress } from './config';

// Get specific contract address
const routerAddress = getContractAddress('ethereum', 'torqueRouter');

// Get engine address for a currency
const usdEngine = getEngineAddress('arbitrum', 'USD');
```

For the latest deployed addresses, check the configuration files in the `config/` directory.

## Getting Started

### Prerequisites

- Node.js (v14 or higher)
- npm or yarn
- Hardhat

### Installation

```bash
git clone https://github.com/torquefi/torque_fx.git
cd torque_fx
yarn
```

### Development

```bash
# Compile contracts
npx hardhat compile

# Run tests
npx hardhat test

# Deploy contracts
npx hardhat run scripts/01_deploy_torque.ts --network <network-name>

# Link contracts
npx hardhat run scripts/02_link_contracts.ts --network <network-name>
```

## Testing

Run the full test suite:

```bash
npx hardhat test
```

## License

This project is licensed under the GNU General Public License v3.0.