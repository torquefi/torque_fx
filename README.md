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

- `TorqueDEX.sol`: Core AMM DEX contract
- `TorqueRouter.sol`: Trading pair and price feed management
- `Torque.sol`: Native ERC20 token with voting and omnichain support
- `TorqueRewards.sol`: Staking and rewards distribution
- `TorqueAccount.sol`: User account and leverage management
- `TorqueFX.sol`: Main leveraged trading contract
- `currencies/`: Currency-specific contracts

## Contract Addresses

| Contract         | Address (Mainnet) | Address (Testnet) |
|------------------|------------------|-------------------|
| Torque           | `0x...`          | `0x...`           |
| TorqueFX         | `0x...`          | `0x...`           |
| TorqueDEX        | `0x...`          | `0x...`           |
| TorqueRouter     | `0x...`          | `0x...`           |
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

## Testing

Run the full test suite:

```bash
npx hardhat test
```

## Contributing

1. Fork the repository
2. Create your feature branch (`git checkout -b feature/amazing-feature`)
3. Commit your changes (`git commit -m 'Add some amazing feature'`)
4. Push to the branch (`git push origin feature/amazing-feature`)
5. Open a Pull Request

## License

This project is licensed under the Business Source License (BUSL). See the LICENSE file for details.
