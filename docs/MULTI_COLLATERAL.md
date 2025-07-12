# Multi-Collateral Support for Torque Engines

The Torque engines now support multiple collateral tokens, allowing users to deposit various assets like USDC, USDT, ETH, and BTC to mint Torque currencies.

## Overview

Each Torque engine (USD, EUR, GBP, etc.) can now accept multiple collateral types, making the protocol more flexible and accessible to users with different asset preferences.

## Supported Collateral Tokens

### Default Collateral
- **USDC** - Default collateral for all engines (6 decimals)

### Additional Collateral (Post-Deployment)
- **USDT** - Tether USD (6 decimals)
- **ETH** - Wrapped Ethereum (18 decimals)
- **BTC** - Wrapped Bitcoin (8 decimals)
- **Custom tokens** - Any ERC20 token with proper price feeds

## How It Works

### 1. Engine Deployment
Engines are deployed with USDC as the default collateral token.

### 2. Adding New Collateral
After deployment, the owner can add new collateral tokens:

```javascript
// Add USDT as collateral
await engine.addCollateralToken(
    "0xdAC17F958D2ee523a2206206994597C13D831ec7", // USDT address
    6, // decimals
    "0x3E7d1eAB13ad0104d2750B8863b489D65364e32D"  // USDT/USD price feed
);

// Add ETH as collateral
await engine.addCollateralToken(
    "0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2", // WETH address
    18, // decimals
    "0x5f4eC3Df9cbd43714FE2740f5E3616155c5b8419"  // ETH/USD price feed
);
```

### 3. User Deposits
Users can deposit any supported collateral:

```javascript
// Deposit USDC (default)
await engine.depositCollateral(1000000); // 1 USDC

// Deposit USDT
await engine.depositCollateral(USDT_ADDRESS, 1000000); // 1 USDT

// Deposit ETH
await engine.depositCollateral(WETH_ADDRESS, ethers.parseEther("1")); // 1 ETH

// Deposit BTC
await engine.depositCollateral(WBTC_ADDRESS, ethers.parseUnits("0.1", 8)); // 0.1 BTC
```

## Price Feeds

### Chainlink Price Feeds
All non-stablecoin collateral tokens require Chainlink price feeds:

- **USDT/USD**: `0x3E7d1eAB13ad0104d2750B8863b489D65364e32D`
- **ETH/USD**: `0x5f4eC3Df9cbd43714FE2740f5E3616155c5b8419`
- **BTC/USD**: `0xF4030086522a5bEEa4988F8cA5B36dbC97BeE88c`

### Stablecoin Handling
Stablecoins (USDC, USDT) with no price feed are assumed to be 1:1 with USD.

## Deployment and Setup

### 1. Deploy Engines
```bash
npm run deploy
```

### 2. Add Multi-Collateral Support
```bash
npm run add-collateral
```

### 3. Verify Setup
```javascript
// Check supported collateral
const supported = await engine.getSupportedCollateral();
console.log("Supported collateral:", supported);

// Check if token is supported
const isSupported = await engine.isCollateralSupported(USDT_ADDRESS);
console.log("USDT supported:", isSupported);
```

## Contract Functions

### Owner Functions
- `addCollateralToken(address token, uint8 decimals, address priceFeed)` - Add new collateral
- `removeCollateralToken(address token)` - Remove collateral token

### View Functions
- `getSupportedCollateral()` - Get list of supported collateral
- `isCollateralSupported(address token)` - Check if token is supported
- `getCollateralValue(address token, uint256 amount)` - Get USD value of collateral

### User Functions
- `depositCollateral(uint256 amount)` - Deposit default collateral (USDC)
- `depositCollateral(address token, uint256 amount)` - Deposit specific collateral

## Example Usage

### Frontend Integration
```javascript
class TorqueEngine {
  constructor(engineAddress, signer) {
    this.engine = new ethers.Contract(engineAddress, ABI, signer);
  }

  async depositUSDC(amount) {
    return await this.engine.depositCollateral(amount);
  }

  async depositUSDT(amount) {
    const USDT = "0xdAC17F958D2ee523a2206206994597C13D831ec7";
    return await this.engine.depositCollateral(USDT, amount);
  }

  async depositETH(amount) {
    const WETH = "0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2";
    return await this.engine.depositCollateral(WETH, amount);
  }

  async getSupportedCollateral() {
    return await this.engine.getSupportedCollateral();
  }
}
```

### Collateral Selection UI
```javascript
const CollateralSelector = () => {
  const [selectedCollateral, setSelectedCollateral] = useState(USDC_ADDRESS);
  const [amount, setAmount] = useState(0);
  const [supportedTokens, setSupportedTokens] = useState([]);

  useEffect(() => {
    loadSupportedCollateral();
  }, []);

  const loadSupportedCollateral = async () => {
    const tokens = await engine.getSupportedCollateral();
    setSupportedTokens(tokens);
  };

  const handleDeposit = async () => {
    if (selectedCollateral === USDC_ADDRESS) {
      await engine.depositCollateral(amount);
    } else {
      await engine.depositCollateral(selectedCollateral, amount);
    }
  };

  return (
    <div>
      <select onChange={(e) => setSelectedCollateral(e.target.value)}>
        {supportedTokens.map(token => (
          <option key={token} value={token}>
            {getTokenSymbol(token)}
          </option>
        ))}
      </select>
      <input 
        type="number" 
        value={amount} 
        onChange={(e) => setAmount(e.target.value)}
        placeholder="Amount"
      />
      <button onClick={handleDeposit}>Deposit</button>
    </div>
  );
};
```

## Benefits

### For Users
- **Flexibility**: Use any supported asset as collateral
- **Convenience**: No need to swap assets before depositing
- **Efficiency**: Avoid additional transaction costs from swapping

### For Protocol
- **Liquidity**: Access to more diverse collateral pools
- **Stability**: Reduced dependency on single collateral type
- **Growth**: Attract users with different asset preferences

## Security Considerations

1. **Price Feed Security**: All price feeds must be from trusted sources (Chainlink)
2. **Collateral Validation**: Only whitelisted tokens can be added as collateral
3. **Owner Controls**: Only contract owner can add/remove collateral tokens
4. **Decimal Handling**: Proper decimal conversion for accurate value calculation

## Network-Specific Addresses

### Mainnet
- USDT: `0xdAC17F958D2ee523a2206206994597C13D831ec7`
- WETH: `0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2`
- WBTC: `0x2260FAC5E5542a773Aa44fBCfeDf7C193bc2C599`

### Testnet (Sepolia)
- USDT: `0x7169D38820dfd117C3FA1f22a697dBA58d90BA06`
- WETH: `0xfFf9976782d46CC05630D1f6eBAb18b2324d6B14`
- WBTC: `0x2260FAC5E5542a773Aa44fBCfeDf7C193bc2C599`

## Troubleshooting

### Common Issues
1. **"Collateral token not supported"** - Token not added to engine
2. **"Invalid price feed"** - Price feed address incorrect or down
3. **"Transfer failed"** - Insufficient allowance or balance

### Solutions
1. Check if token is supported: `await engine.isCollateralSupported(token)`
2. Verify price feed: Check Chainlink documentation
3. Approve tokens: `await token.approve(engine.address, amount)` 