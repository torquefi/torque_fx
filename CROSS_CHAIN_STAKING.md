# Cross-Chain Staking System

## Overview

The Torque protocol now supports cross-chain staking, allowing users to stake both TORQ tokens and LP tokens across multiple blockchain networks. This system leverages LayerZero's OApp protocol for secure cross-chain messaging and OFT (Omnichain Fungible Token) for seamless token bridging.

## Architecture

### 1. Token Types
- **TORQ**: Main governance token (OFT)
- **LP Tokens**: Liquidity provider receipt tokens (ERC-20)
- **Reward Tokens**: Distributed as staking rewards

### 2. Contract Structure
- **TorqueStake.sol**: Main staking contract with OApp functionality
- **TorqueLP.sol**: LP token as ERC-20 receipt token for DEX liquidity
- **Torque.sol**: TORQ token as OFT for cross-chain governance

## Key Features

### 1. Cross-Chain Staking
- Stake TORQ and LP tokens on any supported chain
- Batch staking across multiple chains in one transaction
- Automatic token bridging via OFT protocol

### 2. Flexible Lock Periods
- Minimum lock: 7 days
- Maximum lock: 7 years (2555 days)
- Variable APR based on lock duration (20% - 400%)

### 3. Cross-Chain Reward Distribution
- Earn rewards on any chain
- Unified reward tracking across all networks
- Cross-chain reward claiming

### 4. Governance Integration
- Vote power calculation across all chains
- Lock duration multiplier for governance power
- Cross-chain governance participation

## Supported Networks

The staking system supports 11 major blockchain networks:
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

## Core Functions

### 1. Cross-Chain Staking
```solidity
function stakeCrossChain(
    uint16[] calldata dstChainIds,
    uint256[] calldata amounts,
    uint256[] calldata lockDurations,
    bool[] calldata isLp,
    bytes[] calldata adapterParams
) external nonReentrant
```

**Parameters:**
- `dstChainIds`: Array of destination chain IDs
- `amounts`: Array of token amounts to stake
- `lockDurations`: Array of lock durations for each stake
- `isLp`: Array indicating if each stake is LP (true) or TORQ (false)
- `adapterParams`: LayerZero adapter parameters for gas optimization

### 2. Cross-Chain Unstaking
```solidity
function unstakeCrossChain(
    uint16[] calldata dstChainIds,
    bytes[] calldata adapterParams
) external nonReentrant
```

### 3. Single-Chain Staking (Legacy)
```solidity
function stakeLp(uint256 amount, uint256 lockDuration) external nonReentrant
function stakeTorq(uint256 amount, uint256 lockDuration) external nonReentrant
function unstakeLp() external nonReentrant
function unstakeTorq() external nonReentrant
```

### 4. Reward Management
```solidity
function claimRewards(bool isLp) external nonReentrant
```

## Cross-Chain Flow

### 1. Staking Process
```
User (Ethereum)                    Arbitrum
     |                                |
     | 1. Call stakeCrossChain()      |
     |                                |
     | 2. Transfer OFTs to contract   |
     |    (TORQ/LP tokens)            |
     |                                |
     | 3. Burn OFTs on source chain   |
     |                                |
     | 4. Send LayerZero message      |
     |    ┌─────────────────────────┐  |
     |    │ CrossChainStakeRequest │  |
     |    │ - user address         │  |
     |    │ - amount               │  |
     |    │ - lockDuration         │  |
     |    │ - isLp flag            │  |
     |    │ - sourceChainId: 1     │  |
     |    └─────────────────────────┘  |
     |                                |
     |                                | 5. Receive message
     |                                |
     |                                | 6. Mint OFTs to user
     |                                |
     |                                | 7. Create stake position
     |                                |
     |                                | 8. Update cross-chain tracking
     |                                |
     |                                | 9. Emit completion event
```

### 2. Unstaking Process
```
User (Ethereum)                    Arbitrum
     |                                |
     | 1. Call unstakeCrossChain()    |
     |                                |
     | 2. Send LayerZero message      |
     |                                |
     |                                | 3. Receive message
     |                                |
     |                                | 4. Calculate rewards
     |                                |
     |                                | 5. Apply early exit penalty
     |                                |    (if applicable)
     |                                |
     |                                | 6. Transfer tokens to user
     |                                |
     |                                | 7. Burn OFTs on destination
     |                                |
     |                                | 8. Mint OFTs on source chain
     |                                |
     | 9. Receive tokens              |
     |                                |
```

## APR Calculation

### Dynamic APR Based on Lock Duration
```solidity
function _calculateAPR(uint256 lockDuration) internal pure returns (uint256) {
    if (lockDuration <= MIN_LOCK_DURATION) {
        return MIN_APR; // 20%
    }
    if (lockDuration >= MAX_LOCK_DURATION) {
        return MAX_APR; // 400%
    }

    // Linear interpolation between MIN_APR and MAX_APR
    uint256 durationRange = MAX_LOCK_DURATION - MIN_LOCK_DURATION;
    uint256 aprRange = MAX_APR - MIN_APR;
    
    return MIN_APR + ((lockDuration - MIN_LOCK_DURATION) * aprRange) / durationRange;
}
```

**APR Ranges:**
- 7 days: 20% APR
- 1 year: ~210% APR
- 7 years: 400% APR

## Governance Integration

### Vote Power Calculation
```solidity
function _updateVotePower(address user) internal {
    Stake storage lpStake = lpStakes[user];
    Stake storage torqStake = torqStakes[user];

    uint256 totalPower = 0;

    // Calculate LP vote power with lock multiplier
    if (lpStake.amount > 0) {
        uint256 lockDuration = lpStake.lockEnd - block.timestamp;
        uint256 multiplier = 1e18 + ((lockDuration * (VOTE_POWER_MULTIPLIER - 1e18)) / MAX_LOCK_DURATION);
        totalPower += (lpStake.amount * multiplier) / 1e18;
    }

    // Calculate TORQ vote power with lock multiplier
    if (torqStake.amount > 0) {
        uint256 lockDuration = torqStake.lockEnd - block.timestamp;
        uint256 multiplier = 1e18 + ((lockDuration * (VOTE_POWER_MULTIPLIER - 1e18)) / MAX_LOCK_DURATION);
        totalPower += (torqStake.amount * multiplier) / 1e18;
    }

    votePower[user] = totalPower;
}
```

**Vote Power Features:**
- Base vote power = staked amount
- Lock duration multiplier (up to 2x for max lock)
- Cross-chain vote power aggregation
- Real-time vote power updates

## Admin Functions

### 1. Cross-Chain Configuration
```solidity
function setStakeAddress(uint16 chainId, address stakeAddress) external onlyOwner
```
Sets the TorqueStake contract address for a specific chain.

### 2. Treasury Management
```solidity
function setTreasuryFeeRecipient(address _treasuryFeeRecipient) external onlyOwner
```
Updates the treasury address for early exit penalties.

### 3. Emergency Functions
```solidity
function emergencyWithdraw(address token, address to, uint256 amount) external onlyOwner
```
Recovers stuck tokens from the contract.

## Query Functions

### 1. Cross-Chain Stake Information
```solidity
function getCrossChainStakeInfo(address user, uint16 chainId) external view returns (uint256)
function getTotalCrossChainStakes(address user) external view returns (uint256)
```

### 2. Gas Estimation
```solidity
function getCrossChainStakeQuote(
    uint16[] calldata dstChainIds,
    bytes[] calldata adapterParams
) external view returns (uint256 totalGasEstimate)
```

### 3. Stake Information
```solidity
function getStakeInfo(address user) external view returns (
    uint256 lpAmount,
    uint256 lpLockEnd,
    uint256 lpRewards,
    uint256 lpApr,
    uint256 torqAmount,
    uint256 torqLockEnd,
    uint256 torqRewards,
    uint256 torqApr,
    uint256 userVotePower
)
```

## Events

### Cross-Chain Events
```solidity
event CrossChainStakeRequested(
    address indexed user,
    uint16 indexed dstChainId,
    uint256 amount,
    uint256 lockDuration,
    bool isLp,
    bool isStake
);

event CrossChainStakeCompleted(
    address indexed user,
    uint16 indexed srcChainId,
    uint256 amount,
    bool isLp,
    bool isStake
);

event CrossChainStakeFailed(
    address indexed user,
    uint16 indexed srcChainId,
    string reason
);
```

### Standard Events
```solidity
event Staked(address indexed user, uint256 amount, uint256 lockDuration, bool isLp);
event Unstaked(address indexed user, uint256 amount, bool isLp, bool isEarly);
event RewardPaid(address indexed user, uint256 reward, bool isLp);
event VotePowerUpdated(address indexed user, uint256 newPower);
```

## Usage Examples

### 1. Cross-Chain Staking
```typescript
// Stake TORQ on Ethereum and LP tokens on Arbitrum
const dstChainIds = [1, 42161];
const amounts = [
    ethers.parseEther("1000"), // 1000 TORQ on Ethereum
    ethers.parseEther("500")   // 500 LP tokens on Arbitrum
];
const lockDurations = [365 days, 730 days]; // 1 year, 2 years
const isLp = [false, true]; // TORQ, then LP
const adapterParams = [
    ethers.AbiCoder.defaultAbiCoder().encode(["uint16", "uint256"], [1, 200000]),
    ethers.AbiCoder.defaultAbiCoder().encode(["uint16", "uint256"], [1, 200000])
];

await torqueStake.stakeCrossChain(
    dstChainIds,
    amounts,
    lockDurations,
    isLp,
    adapterParams
);
```

### 2. Cross-Chain Unstaking
```typescript
// Unstake from Ethereum and Polygon
const dstChainIds = [1, 137];
const adapterParams = [
    ethers.AbiCoder.defaultAbiCoder().encode(["uint16", "uint256"], [1, 200000]),
    ethers.AbiCoder.defaultAbiCoder().encode(["uint16", "uint256"], [1, 200000])
];

await torqueStake.unstakeCrossChain(dstChainIds, adapterParams);
```

### 3. Gas Estimation
```typescript
const gasQuote = await torqueStake.getCrossChainStakeQuote(
    dstChainIds,
    adapterParams
);
console.log(`Estimated gas: ${gasQuote.toString()}`);
```

## Security Features

### 1. Access Control
- Only owner can set cross-chain addresses
- Only owner can update treasury recipient
- Emergency functions are owner-only

### 2. Reentrancy Protection
- All staking functions use `nonReentrant` modifier
- Internal functions are protected

### 3. Early Exit Penalties
- 50% penalty for early unstaking
- Penalties sent to treasury
- Automatic penalty calculation

### 4. Error Handling
- Comprehensive error handling in cross-chain operations
- Failed operations emit events for monitoring
- Try-catch blocks prevent contract failures

## Deployment Process

### 1. Deploy on Each Chain
```typescript
const TorqueStake = await ethers.getContractFactory("TorqueStake");
const torqueStake = await TorqueStake.deploy(
    lpTokenAddress,
    torqTokenAddress,
    rewardTokenAddress,
    treasuryAddress,
    lzEndpoint,
    owner
);
```

### 2. Configure Cross-Chain Addresses
```typescript
// Set stake contract addresses for each chain
await torqueStake.setStakeAddress(42161, arbitrumStakeAddress);
await torqueStake.setStakeAddress(137, polygonStakeAddress);
// ... repeat for all chains
```

### 3. Verify Configuration
Ensure all cross-chain addresses are properly configured before allowing cross-chain operations.

## Benefits

### 1. User Benefits
- **Multi-Chain Access**: Stake on any supported network
- **Higher Yields**: Access to best yields across all chains
- **Flexible Locking**: Choose lock duration based on preferences
- **Governance Power**: Earn vote power across all networks
- **Gas Efficiency**: Batch operations reduce costs

### 2. Protocol Benefits
- **Liquidity Distribution**: Spread liquidity across networks
- **User Retention**: Longer lock periods with higher rewards
- **Governance Participation**: Increased voter engagement
- **Cross-Chain Integration**: Seamless multi-chain experience

### 3. Technical Benefits
- **OFT Integration**: Automatic token bridging
- **LayerZero Security**: Trusted cross-chain messaging
- **Scalable Architecture**: Easy to add new networks
- **Comprehensive Tracking**: Full cross-chain position visibility

## Future Enhancements

### 1. Advanced Features
- Cross-chain reward optimization
- Dynamic APR based on network conditions
- Cross-chain governance proposals
- Advanced staking strategies

### 2. Network Expansion
- Support for additional LayerZero networks
- Integration with other cross-chain protocols
- Multi-protocol staking aggregation

### 3. User Experience
- Simplified cross-chain staking UI
- Automated yield optimization
- Cross-chain position management tools
- Real-time analytics and reporting 