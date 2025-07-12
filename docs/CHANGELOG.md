# Changelog

All notable changes to the Torque Protocol will be documented in this file.

## [2.1.0] - 2024-12-19

### 🚀 New Features

#### Multi-Collateral Engine Support
- **NEW**: Added multi-collateral support to Torque engines
- **NEW**: Support for USDC, USDT, ETH, BTC, and custom tokens as collateral
- **NEW**: Post-deployment collateral token addition via `addCollateralToken()`
- **NEW**: Chainlink price feed integration for accurate USD valuation
- **NEW**: Flexible deposit functions for different collateral types

#### Multi-Collateral Functions
- `addCollateralToken(address token, uint8 decimals, address priceFeed)` - Add new collateral
- `removeCollateralToken(address token)` - Remove collateral token
- `getSupportedCollateral()` - Get list of supported collateral
- `isCollateralSupported(address token)` - Check if token is supported
- `getCollateralValue(address token, uint256 amount)` - Get USD value of collateral
- `depositCollateral(address token, uint256 amount)` - Deposit specific collateral

#### Deployment Scripts
- **NEW**: `03_add_collateral_tokens.ts` - Script to add multi-collateral support
- **NEW**: `npm run add-collateral` - Add collateral tokens to engines
- **NEW**: `npm run add-collateral:testnet` - Add collateral tokens on testnet

#### Documentation
- **NEW**: `docs/MULTI_COLLATERAL.md` - Comprehensive multi-collateral documentation
- **NEW**: Frontend integration examples
- **NEW**: Network-specific token addresses
- **NEW**: Troubleshooting guide

### 🔧 Technical Improvements

#### Engine Architecture
- **Enhanced**: Base `TorqueEngine.sol` with multi-collateral support
- **Enhanced**: Price feed integration for non-stablecoin tokens
- **Enhanced**: Decimal handling for different token types
- **Enhanced**: Collateral validation and management

#### Security Features
- **Enhanced**: Owner-only collateral token management
- **Enhanced**: Price feed validation and error handling
- **Enhanced**: Proper decimal conversion for accurate valuations

### 📚 Documentation Updates

- **NEW**: Multi-collateral setup guide
- **NEW**: Token address references for mainnet and testnet
- **NEW**: Frontend integration examples
- **NEW**: Collateral selection UI examples

---

## [2.0.0] - 2024-12-19

### 🚀 Major Changes

#### Removed TorqueAccount System
- **BREAKING**: Removed ERC-4337 account abstraction system
- **BREAKING**: Removed all TorqueAccount-related contracts
- **BREAKING**: Updated all contracts to work with direct wallet connections

#### Removed Contracts
- `TorqueAccount.sol` - User account management contract
- `TorqueAccountFactory.sol` - Account creation factory
- `TorqueAccountBundler.sol` - Operation bundling
- `TorqueAccountRecovery.sol` - Account recovery system
- `TorqueAccountUpgrade.sol` - Account upgrade functionality
- `TorqueAccountGasOptimizer.sol` - Gas optimization
- `TorqueAccountCrossChain.sol` - Cross-chain account operations
- `EntryPoint.sol` - ERC-4337 entry point
- `ITorqueAccount.sol` - Account interface

#### Updated Contracts

**TorqueFX.sol**
- Removed `ITorqueAccount` dependency
- Updated constructor: `(address _dexContract, address _usdc)`
- Removed `accountId` parameters from functions
- Updated `openPosition()`: `(address baseToken, address quoteToken, uint256 collateral, uint256 leverage, bool isLong)`
- Updated `closePosition()`: `(bytes32 pair)`
- Updated `liquidate()` to use position size directly
- Simplified position management without account verification
- **ENHANCED**: Increased maximum leverage to 500x (50000 basis points)

**TorquePayments.sol**
- Removed `ITorqueAccount` dependency
- Updated constructor: `(address _usdc, address _lzEndpoint)`
- Removed `accountId` parameters from payment functions
- Simplified payment processing with direct wallet balances
- Removed account verification requirements

**TorqueRouter.sol**
- Removed `ITorqueAccount` dependency
- Updated constructor: `()`
- Removed account validation functions

**TorqueGateway.sol**
- Removed `ITorqueAccount` dependency
- Updated constructor: `(address _paymentsContract, address _usdc)`
- Simplified payment session processing

**TorqueRewards.sol**
- Removed `ITorqueAccount` dependency
- Updated constructor: `(address _rewardToken, address _torquePayments, address _torqueFX)`
- Removed referral reward function that depended on TorqueAccount

#### Updated Scripts

**01_deploy_torque.ts**
- Removed all 4337 contract deployments
- Updated contract deployment order and dependencies
- Removed TorqueAccount references from deployment summary

**02_link_contracts.ts**
- Removed all TorqueAccount linking code
- Added TorqueFX and TorquePayments linking
- Updated summary to reflect new contract structure

#### Updated Tests
- Removed TorqueAccount dependencies from test files
- Updated function calls to match new contract interfaces
- Simplified test setup for direct wallet integration

#### Updated Configuration
- Added optimizer and `viaIR` settings to resolve compilation issues
- Removed `@account-abstraction/contracts` dependency
- Updated package.json scripts to use new deployment approach

### ✨ New Features

#### Direct Wallet Integration
- **Simplified User Experience**: No account creation or management required
- **Lower Gas Costs**: Eliminated account abstraction overhead
- **Faster Transactions**: Direct wallet interactions
- **Better Compatibility**: Works with all standard wallet providers
- **Reduced Complexity**: Streamlined architecture

#### Enhanced Leverage Support
- **500x Maximum Leverage**: Increased from 100x to 500x
- **UI Slider Integration**: Users specify leverage via frontend controls
- **Dynamic Leverage**: Adjust leverage per trade based on risk tolerance

### 🔧 Technical Improvements

- **Gas Optimization**: Reduced gas costs by removing account management
- **Simplified Architecture**: Cleaner contract interactions
- **Better Performance**: Faster transaction processing
- **Easier Integration**: Standard wallet connection patterns

### 📚 Documentation Updates

- Updated README.md with new architecture
- Added Direct Wallet Integration section
- Added Migration Guide
- Updated contract addresses table
- Updated deployment instructions

### 🧪 Testing

- Updated test suite for new contract interfaces
- Removed TorqueAccount-related tests
- Added tests for direct wallet integration

### 🔄 Migration Notes

#### For Users
- No action required - existing positions and balances are preserved
- New direct wallet integration provides better user experience
- Reduced gas costs for all operations

#### For Developers
- Update frontend to use direct wallet connections
- Remove TorqueAccount integration code
- Update contract calls to use new function signatures
- Simplified integration patterns

#### For Integrators
- Remove account creation and management flows
- Update to use standard wallet connection patterns
- Simplified API integration

### 🐛 Bug Fixes

- Fixed "Stack too deep" compilation errors with optimizer settings
- Resolved contract linking issues
- Fixed test compilation errors

### 📦 Dependencies

- Removed: `@account-abstraction/contracts`
- Updated: All contracts to work with direct wallet integration

---

## [1.0.0] - 2024-12-01

### 🎉 Initial Release

- Initial implementation with ERC-4337 account abstraction
- TorqueAccount system for user management
- Leveraged trading with account-based positions
- Multi-currency payment system
- Cross-chain functionality via LayerZero
- Comprehensive rewards system 