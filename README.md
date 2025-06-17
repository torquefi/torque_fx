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
- **Leveraged Trading**: Open long/short positions with up to 100x leverage
- **Account System**: Create multiple accounts with custom leverage and referral tracking
- **Risk Management**: Circuit breaker, position size limits, and liquidation incentives
- **Rewards**: Stake, earn, and claim rewards via TorqueRewards

## Architecture

- `TorqueDEX.sol`: Native AMM with concentrated and stable liquidity models
- `TorqueLP.sol`: LP token contract for DEX liquidity positions
- `TorqueRouter.sol`: Trading pair and price feed management
- `Torque.sol`: Native ERC20 token with voting and omnichain support
- `TorqueRewards.sol`: Staking and rewards distribution
- `TorqueFX.sol`: Main leveraged trading contract
- `4337/`: ERC-4337 account abstraction contracts
  - `TorqueAccount.sol`: User account and leverage management
  - `TorqueAccountFactory.sol`: Account creation and management
  - `TorqueAccountBundler.sol`: Operation bundling and execution
  - `TorqueAccountRecovery.sol`: Account recovery and guardian management
  - `TorqueAccountUpgrade.sol`: Account upgrades and leverage changes
  - `TorqueAccountGasOptimizer.sol`: Gas optimization for operations
  - `TorqueAccountCrossChain.sol`: Cross-chain account operations
  - `EntryPoint.sol`: ERC-4337 entry point contract
- `currencies/`: Currency-specific contracts
- `engines/`: Currency-specific engines for minting and redeeming Torque currencies

## Contract Addresses

| Contract         | Address (Mainnet) | Address (Testnet) |
|------------------|------------------|-------------------|
| Torque           | `0x...`          | `0x...`           |
| TorqueUSD        | `0x...`          | `0x...`           |
| TorqueEUR        | `0x...`          | `0x...`           |
| TorqueGBP        | `0x...`          | `0x...`           |
| TorqueJPY        | `0x...`          | `0x...`           |
| TorqueAUD        | `0x...`          | `0x...`           |
| TorqueCAD        | `0x...`          | `0x...`           |
| TorqueCHF        | `0x...`          | `0x...`           |
| TorqueNZD        | `0x...`          | `0x...`           |
| TorqueXAU        | `0x...`          | `0x...`           |
| TorqueXAG        | `0x...`          | `0x...`           |
| TorqueFX         | `0x...`          | `0x...`           |
| TorqueDEX        | `0x...`          | `0x...`           |
| TorqueRouter     | `0x...`          | `0x...`           |
| TorqueRewards    | `0x...`          | `0x...`           |
| TorqueAccount    | `0x...`          | `0x...`           |
| TorqueUSDEngine  | `0x...`          | `0x...`           |
| TorqueEUREngine  | `0x...`          | `0x...`           |
| TorqueGBPEngine  | `0x...`          | `0x...`           |
| TorqueJPYEngine  | `0x...`          | `0x...`           |
| TorqueAUDEngine  | `0x...`          | `0x...`           |
| TorqueCADEngine  | `0x...`          | `0x...`           |
| TorqueCHFEngine  | `0x...`          | `0x...`           |
| TorqueNZDEngine  | `0x...`          | `0x...`           |
| TorqueXAUEngine  | `0x...`          | `0x...`           |
| TorqueXAGEngine  | `0x...`          | `0x...`           |
| Treasury         | `0x...`          | `0x...`           |

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
npx hardhat run scripts/deploy.ts --network <network-name>
```

## Testing

Run the full test suite:

```bash
npx hardhat test
```

## License

This project is licensed under the MIT License. See the LICENSE file for details.