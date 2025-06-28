# Cross-Chain DEX Implementation

## Overview

The TorqueDEX has been enhanced with LayerZero integration to support cross-chain liquidity provision. This allows users to add and remove liquidity across multiple blockchain networks in a single transaction.

## Key Features

### 1. Cross-Chain Liquidity Provision
- **Batch Operations**: Add/remove liquidity to multiple chains simultaneously
- **LayerZero Integration**: Secure cross-chain messaging using LayerZero protocol
- **Gas Estimation**: Built-in gas estimation for cross-chain operations
- **Error Handling**: Comprehensive error handling and recovery mechanisms

### 2. Supported Networks
The DEX supports the following blockchain networks:
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

## Contract Architecture

### TorqueDEX.sol
The main DEX contract now inherits from:
- `OApp`: LayerZero's OApp for cross-chain messaging
- `Ownable`: Access control for administrative functions
- `ReentrancyGuard`: Protection against reentrancy attacks

### Key Components

#### 1. Cross-Chain State Management
```solidity
// Cross-chain liquidity tracking
mapping(uint16 => mapping(address => uint256)) public crossChainLiquidity;
mapping(uint16 => bool) public supportedChainIds;
mapping(uint16 => address) public dexAddresses;
```

#### 2. Cross-Chain Liquidity Request Structure
```solidity
struct CrossChainLiquidityRequest {
    address user;
    uint256 amount0;
    uint256 amount1;
    int256 lowerTick;
    int256 upperTick;
    uint16 sourceChainId;
    bool isAdd; // true for add, false for remove
}
```

## Core Functions

### 1. Cross-Chain Liquidity Addition
```solidity
function addCrossChainLiquidity(
    uint16[] calldata dstChainIds,
    uint256[] calldata amounts0,
    uint256[] calldata amounts1,
    int256[] calldata lowerTicks,
    int256[] calldata upperTicks,
    bytes[] calldata adapterParams
) external nonReentrant
```

**Parameters:**
- `dstChainIds`: Array of destination chain IDs
- `amounts0`: Array of token0 amounts for each chain
- `amounts1`: Array of token1 amounts for each chain
- `lowerTicks`: Array of lower tick bounds for concentrated liquidity
- `upperTicks`: Array of upper tick bounds for concentrated liquidity
- `adapterParams`: Array of LayerZero adapter parameters for gas optimization

### 2. Cross-Chain Liquidity Removal
```solidity
function removeCrossChainLiquidity(
    uint16[] calldata dstChainIds,
    uint256[] calldata liquidityAmounts,
    bytes[] calldata adapterParams
) external nonReentrant
```

### 3. Cross-Chain Message Handling
```solidity
function _nonblockingLzReceive(
    uint16 srcChainId,
    bytes memory srcAddress,
    uint64 nonce,
    bytes memory payload
) internal override
```

This function handles incoming cross-chain liquidity requests from other networks.

## Admin Functions

### 1. DEX Address Configuration
```solidity
function setDEXAddress(uint16 chainId, address dexAddress) external onlyOwner
```
Sets the TorqueDEX contract address for a specific chain.

### 2. Fee Management
```solidity
function setFee(uint256 _feeBps) external onlyOwner
function setFeeRecipient(address _feeRecipient) external onlyOwner
```
- `setFee`: Updates the trading fee (max 0.3%)
- `setFeeRecipient`: Updates the fee recipient address

### 3. Cross-Chain Liquidity Queries
```solidity
function getCrossChainLiquidity(address user, uint16 chainId) external view returns (uint256)
function getTotalCrossChainLiquidity(address user) external view returns (uint256 total)
```

### 4. Gas Estimation
```solidity
function getCrossChainLiquidityQuote(
    uint16[] calldata dstChainIds,
    bytes[] calldata adapterParams
) external view returns (uint256 totalGasEstimate)
```

### 5. Emergency Functions
```solidity
function emergencyWithdraw(address token, address to, uint256 amount) external onlyOwner
```
Recovers stuck tokens from the contract.

## Events

### Cross-Chain Events
```solidity
event CrossChainLiquidityRequested(
    address indexed user,
    uint16 indexed dstChainId,
    uint256 amount0,
    uint256 amount1,
    int256 lowerTick,
    int256 upperTick,
    bool isAdd
);

event CrossChainLiquidityCompleted(
    address indexed user,
    uint16 indexed srcChainId,
    uint256 liquidity,
    uint256 amount0,
    uint256 amount1,
    bool isAdd
);

event CrossChainLiquidityFailed(
    address indexed user,
    uint16 indexed srcChainId,
    string reason
);
```

## Deployment Process

### 1. Deploy on Each Chain
Deploy TorqueDEX on all supported chains with the appropriate LayerZero endpoint:

```typescript
const TorqueDEX = await ethers.getContractFactory("TorqueDEX");
const torqueDEX = await TorqueDEX.deploy(
    token0Address,
    token1Address,
    "Torque LP Token",
    "TLP",
    feeRecipient,
    false, // isStablePair
    lzEndpoint,
    owner
);
```

### 2. Configure Cross-Chain Addresses
Set the DEX addresses for each chain on all deployed contracts:

```typescript
// On each chain, set the addresses of DEX contracts on other chains
await torqueDEX.setDEXAddress(42161, arbitrumDexAddress);
await torqueDEX.setDEXAddress(137, polygonDexAddress);
// ... repeat for all chains
```

### 3. Verify Configuration
Ensure all cross-chain addresses are properly configured before allowing cross-chain operations.

## Usage Examples

### Adding Cross-Chain Liquidity
```typescript
// Add liquidity to Ethereum and Arbitrum simultaneously
const dstChainIds = [1, 42161];
const amounts0 = [ethers.parseEther("1000"), ethers.parseEther("1000")];
const amounts1 = [ethers.parseEther("1000"), ethers.parseEther("1000")];
const lowerTicks = [-1000, -1000];
const upperTicks = [1000, 1000];
const adapterParams = [
    ethers.AbiCoder.defaultAbiCoder().encode(["uint16", "uint256"], [1, 200000]),
    ethers.AbiCoder.defaultAbiCoder().encode(["uint16", "uint256"], [1, 200000])
];

await torqueDEX.addCrossChainLiquidity(
    dstChainIds,
    amounts0,
    amounts1,
    lowerTicks,
    upperTicks,
    adapterParams
);
```

### Getting Gas Estimates
```typescript
const gasQuote = await torqueDEX.getCrossChainLiquidityQuote(
    dstChainIds,
    adapterParams
);
console.log(`Estimated gas: ${gasQuote.toString()}`);
```

## Security Considerations

### 1. Access Control
- Only the contract owner can set DEX addresses
- Only the contract owner can modify fees and fee recipient
- Emergency withdrawal functions are owner-only
- All administrative functions use `onlyOwner` modifier

### 2. Reentrancy Protection
- All cross-chain functions use `nonReentrant` modifier
- Internal functions are protected against reentrancy attacks

### 3. Error Handling
- Comprehensive error handling in cross-chain message processing
- Failed operations emit events for monitoring
- Try-catch blocks prevent contract failures

### 4. Validation
- Chain ID validation before cross-chain operations
- Array length validation for batch operations
- Token approval validation
- Zero address validation for fee recipient

## Gas Optimization

### 1. Batch Operations
- Multiple chains in a single transaction
- Reduced gas costs compared to individual transactions

### 2. Adapter Parameters
- LayerZero adapter parameters for gas optimization
- Custom gas limits for different chains

### 3. Efficient Storage
- Optimized data structures for cross-chain tracking
- Minimal storage overhead

## Monitoring and Maintenance

### 1. Event Monitoring
Monitor cross-chain events for:
- Successful liquidity operations
- Failed operations and reasons
- Gas usage patterns

### 2. Regular Maintenance
- Update DEX addresses when contracts are upgraded
- Monitor gas costs and optimize adapter parameters
- Review and update supported chains as needed

### 3. Emergency Procedures
- Emergency withdrawal functions for stuck tokens
- Circuit breaker mechanisms if needed
- Owner controls for critical parameters

## Testing

### 1. Unit Tests
- Test all cross-chain functions
- Verify error handling
- Test access controls

### 2. Integration Tests
- Test cross-chain message passing
- Verify liquidity tracking across chains
- Test gas estimation accuracy

### 3. Network Tests
- Test on testnet networks
- Verify LayerZero integration
- Test with real cross-chain messaging

## Future Enhancements

### 1. Additional Features
- Cross-chain swaps
- Cross-chain yield farming
- Cross-chain governance

### 2. Optimizations
- More efficient gas estimation
- Batch message optimization
- Advanced error recovery

### 3. Network Expansion
- Support for additional LayerZero networks
- Integration with other cross-chain protocols
- Multi-protocol liquidity aggregation 