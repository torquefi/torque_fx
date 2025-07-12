export type CollateralToken = {
  symbol: string;
  name: string;
  contracts: { [chain: string]: string };
  priceFeeds: { [chain: string]: string };
};

export const collateralTokens: CollateralToken[] = [
  {
    symbol: "USDC",
    name: "USD Coin",
    contracts: {
      ethereum: "0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48",
      ethereumSepolia: "0x1c7D4B196Cb0C7B01d743Fbc6116a902379C7238",
      arbitrum: "0xaf88d065e77c8cC2239327C5EDb3A432268e5831",
      arbitrumSepolia: "0x75faf114eafb1BDbe2F0316DF893fd58CE46AA4d",
      optimism: "0x0b2C639c533813f4Aa9D7837CAf62653d097Ff85",
      optimismSepolia: "0x5fd84259d66Cd46123540766Be93DFE6D43130D7",
      polygon: "0x3c499c542cEF5E3811e1192ce70d8cC03d5c3359",
      avalanche: "0xB97EF9Ef8734C71904D8002F8b6Bc66Dd9c48a6E",
      base: "0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913",
      baseSepolia: "0x036CbD53842c5426634e7929541eC2318f3dCF7e",
      sonic: "0x29219dd400f2Bf60E5a23d13Be72B486D4038894",
      abstract: "0x84A71ccD554Cc1b02749b35d22F684CC8ec987e1",
      abstractTestnet: "0xe4C7fBB0a626ed208021ccabA6Be1566905E2d",
      bsc: "0x8AC76a51cc950d9822D68b83fE1Ad97B32Cd580d"
    },
    priceFeeds: {
      ethereum: "0x8fFfFfd4AfB6115b954Bd326cbe7B4BA576818f6",
      arbitrum: "0x50834F3163758fcC1Df9973b6e91f0F0F0434aD3",
      polygon: "0xfE4A8cc5b5B2366C1B58Bea3858e81843581b2F7",
      optimism: "0x16a9FA2FDa030272Ce99B29CF780dFA30361E0f3",
      sonic: "0x55bCa887199d5520B3Ce285D41e6dC10C08716C9",
      avalanche: "0x97FE42a7E96640D932bbc0e1580c73E705A8EB73",
      base: "0xd30e2101a97dcbAeBCBC04F14C3f624E67A35165",
      bsc: "0x90c069C4538adAc136E051052E14c1cD799C41B7"
    }
  },
  {
    symbol: "USDT",
    name: "Tether",
    contracts: {
      ethereum: "0xdAC17F958D2ee523a2206206994597C13D831ec7",
      arbitrum: "0xFd086bC7CD5C481DCC9C85ebE478A1C0b69FCbb9",
      polygon: "0xc2132D05D31c914a87C6611C10748AEb04B58e8F",
      avalanche: "0x9702230a8ea53601f5cd2dc00fdbc13d4df4a8c7",
      base: "0xfde4C96c8593536E31F229EA8f37b2ADa2699bb2",
      sonic: "0x6047828dc181963ba44974801FF68e538dA5eaF9",
      abstract: "0x0709F39376dEEe2A2dfC94A58EdEb2Eb9DF012bD",
      optimism: "0x94b008aA00579c1307B0EF2c499aD98a8ce58e58"
    },
    priceFeeds: {
      ethereum: "0x3E7d1eAB13ad0104d2750B8863b489D65364e32D",
      arbitrum: "0x3f3f5dF88dC9F13eac63DF89EC16ef6e7E25DdE7",
      polygon: "0x0A6513e40db6EB1b165753AD52E80663aeA50545",
      avalanche: "0xEBE676ee90Fe1112671f19b6B7459bC678B67e8a",
      base: "0xf19d560eB8d2ADf07BD6D13ed03e1D11215721F9",
      optimism: "0xECef79E109e997bCA29c1c0897ec9d7b03647F5E",
      sonic: "0x76F4C040A792aFB7F6dBadC7e30ca3EEa140D216"
    }
  },
  {
    symbol: "USDS",
    name: "Sky USD",
    contracts: {
      ethereum: "0xdC035D45d973E3EC169d2276DDab16f1e407384F",
      arbitrum: "0x6491c05A82219b8D1479057361ff1654749b876b",
      base: "0x820C137fa70C8691f0e44Dc420a5e53c168921Dc"
    },
    priceFeeds: {
      ethereum: "0xfF30586cD0F29eD462364C7e81375FC0C71219b1",
      arbitrum: "0x37833E5b3fbbEd4D613a3e0C354eF91A42B81eeB",
      base: "0x2330aaE3bca5F05169d5f4597964D44522F62930"
    }
  },
  {
    symbol: "PYUSD",
    name: "PayPal USD",
    contracts: {
      ethereum: "0x6c3ea9036406852006290770BEdFcAbA0e23A0e8"
    },
    priceFeeds: {
      ethereum: "0x8f1dF6D7F2db73eECE86a18b4381F4707b918FB1"
    }
  },
  {
    symbol: "WYST",
    name: "Wyoming Stable",
    contracts: {
      wyoming: "0x..."
    },
    priceFeeds: {
      wyoming: "0x..."
    }
  },
  {
    symbol: "GHO",
    name: "Aave GHO",
    contracts: {
      ethereum: "0x40D16FC0246aD3160Ccc09B8D0D3A2cD28aE6C2f"
    },
    priceFeeds: {
      ethereum: "0x3f12643D3f6f874d39C2a4c9f2Cd6f2DbAC877FC"
    }
  },
  {
    symbol: "cbBTC",
    name: "Coinbase Bitcoin",
    contracts: {
      ethereum: "0x...",
      base: "0x..."
    },
    priceFeeds: {
      ethereum: "0x...",
      base: "0x..."
    }
  },
  {
    symbol: "cbETH",
    name: "Coinbase Ether",
    contracts: {
      ethereum: "0x...",
      base: "0x..."
    },
    priceFeeds: {
      ethereum: "0x...",
      base: "0x..."
    }
  },
  {
    symbol: "WETH",
    name: "Wrapped Ether",
    contracts: {
      ethereum: "0x...",
      abstract: "0x3439153EB7AF838Ad19d56E1571FBD09333C2809",
      abstractTestnet: "0x9EDCde0257F2386Ce177C3a7FCdd97787F0D84"
    },
    priceFeeds: {
      ethereum: "0x5f4eC3Df9cbd43714FE2740f5E3616155c5b8419",
      abstract: "0x..."
    }
  },
  {
    symbol: "WBTC",
    name: "Wrapped Bitcoin",
    contracts: {
      ethereum: "0x...",
      base: "0x..."
    },
    priceFeeds: {
      ethereum: "0x...",
      base: "0x..."
    }
  },
  {
    symbol: "weETH",
    name: "Ether.fi ETH",
    contracts: {
      ethereum: "0x...",
      arbitrum: "0x...",
      bsc: "0x...",
      base: "0x..."
    },
    priceFeeds: {
      ethereum: "0x...",
      arbitrum: "0x20bAe7e1De9c596f5F7615aeaa1342Ba99294e12",
      bsc: "0xF37Be32598E9851f785acA86c2162e7C1A8466dd",
      base: "0x35e9D7001819Ea3B39Da906aE6b06A62cfe2c181"
    }
  },
  {
    symbol: "rsETH",
    name: "Kelp DAO ETH",
    contracts: {
      ethereum: "0x..."
    },
    priceFeeds: {
      ethereum: "0x..."
    }
  },
  {
    symbol: "stETH",
    name: "Lido ETH",
    contracts: {
      ethereum: "0x...",
      arbitrum: "0x..."
    },
    priceFeeds: {
      ethereum: "0x...",
      arbitrum: "0x..."
    }
  },
  {
    symbol: "mETH",
    name: "Mantle ETH",
    contracts: {
      mantle: "0x..."
    },
    priceFeeds: {
      mantle: "0x..."
    }
  },
  {
    symbol: "stBTC",
    name: "Babylon BTC",
    contracts: {
      babylon: "0x..."
    },
    priceFeeds: {
      babylon: "0x..."
    }
  },
  {
    symbol: "vBTC",
    name: "Corn BTC",
    contracts: {
      cornchain: "0x..."
    },
    priceFeeds: {
      cornchain: "0x..."
    }
  },
  {
    symbol: "LINK",
    name: "Chainlink",
    contracts: {
      ethereum: "0x514910771AF9Ca656af840dff83E8264EcF986CA",
      arbitrum: "0xf97f4df75117a78c1A5a0DBb814Af92458539FB4",
      avalanche: "0x5947BB275c521040051D82396192181b413227A3",
      base: "0x88Fb150BDc53A65fe94Dea0c9BA0a6dAf8C6e196",
      bsc: "0x404460C6A5EdE2D891e8297795264fDe62ADBB75",
      optimism: "0x350a791Bfc2C21F9Ed5d10980Dad2e2638ffa7f6",
      polygon: "0x53E0bca35eC356BD5ddDFebbD1Fc0fD03FaBad39",
      sonic: "0x71052BAe71C25C78E37fD12E5ff1101A71d9018F"
    },
    priceFeeds: {
      ethereum: "0x2c1d072e956AFFC0D435Cb7AC38EF18d24d9127c",
      arbitrum: "0x86E53CF1B870786351Da77A57575e79CB55812CB",
      avalanche: "0x49ccd9ca821EfEab2b98c60dC60F518E765EDe9a",
      base: "0x17CAb8FE31E32f08326e5E27412894e49B0f9D65",
      bsc: "0xca236E327F629f9Fc2c30A4E95775EbF0B89fac8",
      optimism: "0xCc232dcFAAE6354cE191Bd574108c1aD03f86450",
      polygon: "0xd9FFdb71EbE7496cC440152d43986Aae0AB76665",
      sonic: "0x26e450ca14D7bF598C89f212010c691434486119"
    }
  },
  {
    symbol: "AAVE",
    name: "Aave",
    contracts: {
      ethereum: "0x7Fc66500c84A76Ad7e9c93437bFc5Ac33E2DDaE9"
    },
    priceFeeds: {
      ethereum: "0xbd7F896e60B650C01caf2d7279a1148189A68884"
    }
  },
  {
    symbol: "COMP",
    name: "Compound",
    contracts: {
      ethereum: "0xc00e94Cb662C3520282E6f5717214004A7f26888"
    },
    priceFeeds: {
      ethereum: "0xdbd020CAeF83eFd542f4De03e3cF0C28A4428bd5"
    }
  }
];
