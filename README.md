# TorqueFX

TorqueFX is a decentralized exchange (DEX) and trading platform built on Ethereum and other leading EVM chains, featuring leveraged trading, AMM pools, and a comprehensive rewards system.

## Table of Contents

- [Overview](#overview)
- [Features](#features)
- [Architecture](#architecture)
- [Getting Started](#getting-started)
- [Contract Addresses](#contract-addresses)
- [Usage](#usage)
- [Testing](#testing)
- [Security](#security)
- [Audits](#audits)
- [Contributing](#contributing)
- [License](#license)

## Overview

TorqueFX is a modular DeFi protocol that enables users to:
- Trade with up to 100x leverage
- Provide and manage liquidity in AMM pools
- Earn rewards for trading and liquidity provision
- Manage accounts with custom leverage and referral systems

## Features

- **Leveraged Trading**: Open long/short positions with up to 100x leverage
- **AMM DEX**: Swap tokens and provide liquidity via TorqueDEX pools
- **Account System**: Create multiple accounts with custom leverage and referral tracking
- **Rewards**: Stake, earn, and claim rewards via TorqueRewards
- **Risk Management**: Circuit breaker, position size limits, and liquidation incentives
- **Security**: Reentrancy protection, pausable contracts, and upgradable architecture

## Architecture

- `TorqueDEX.sol`: Core AMM DEX contract
- `TorqueRouter.sol`: Trading pair and price feed management
- `Torque.sol`: Native ERC20 token with voting and omnichain support
- `TorqueRewards.sol`: Staking and rewards distribution
- `TorqueAccount.sol`: User account and leverage management
- `TorqueFX.sol`: Main leveraged trading contract
- `currencies/`: Directory containing currency-specific contracts (TorqueUSD, TorqueEUR, TorqueGBP, TorqueJPY, TorqueAUD, TorqueCAD, TorqueCHF, TorqueNZD, TorqueXAU, TorqueXAG)

## Getting Started

### Prerequisites

- Node.js (v14 or higher)
- npm or yarn
- Hardhat

### Installation

```bash
git clone https://github.com/yourusername/torque_fx.git
cd torque_fx
npm install
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

## Contract Addresses

> **Note:** Replace with actual deployed addresses.

| Contract         | Address (Mainnet) | Address (Testnet) |
|------------------|------------------|-------------------|
| TorqueFX         | `0x...`          | `0x...`           |
| TorqueDEX        | `0x...`          | `0x...`           |
| TorqueRouter     | `0x...`          | `0x...`           |
| Torque           | `0x...`          | `0x...`           |
| TorqueRewards    | `0x...`          | `0x...`           |
| TorqueAccount    | `0x...`          | `0x...`           |
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

## Usage

### Trading

- Connect your wallet (e.g., MetaMask)
- Create a Torque Account and set leverage
- Deposit USDC and open a leveraged position via the TorqueFX contract
- Monitor, modify, or close your position at any time

### Liquidity Provision

- Add liquidity to TorqueDEX pools to earn LP tokens and trading fees
- Stake LP tokens in TorqueRewards to earn additional rewards

### Staking & Rewards

- Stake Torque or LP tokens in the rewards contract
- Claim rewards periodically

## Testing

Run the full test suite:

```bash
npx hardhat test
```

## Security

- All contracts use OpenZeppelin libraries for security
- Circuit breaker and pausable mechanisms are implemented
- **Audits:** Security audits are recommended before mainnet deployment
- **Bug Bounty:** [Add details if available]

## Audits

> _Please use at your own risk._

## Contributing

1. Fork the repository
2. Create your feature branch (`git checkout -b feature/amazing-feature`)
3. Commit your changes (`git commit -m 'Add some amazing feature'`)
4. Push to the branch (`git push origin feature/amazing-feature`)
5. Open a Pull Request

## License

This project is licensed under the Business Source License (BUSL). See the LICENSE file for details.
