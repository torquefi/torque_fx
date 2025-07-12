import { EndpointId } from '@layerzerolabs/lz-definitions';

export interface ChainConfig {
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

export const CHAINS: Record<string, ChainConfig> = {
  // Mainnet chains
  ethereum: {
    id: 1,
    name: 'Ethereum',
    network: 'ethereum',
    nativeCurrency: {
      name: 'Ether',
      symbol: 'ETH',
      decimals: 18,
    },
    rpcUrls: {
      http: ['https://eth.llamarpc.com', 'https://rpc.ankr.com/eth'],
    },
    blockExplorers: {
      name: 'Etherscan',
      url: 'https://etherscan.io',
      apiUrl: 'https://api.etherscan.io',
    },
    layerZero: {
      endpointId: EndpointId.ETHEREUM_MAINNET,
      endpoint: '0x1a44076050125825900e736c501f859c50fE728c',
    },
    testnet: false,
  },
  arbitrum: {
    id: 42161,
    name: 'Arbitrum One',
    network: 'arbitrum',
    nativeCurrency: {
      name: 'Ether',
      symbol: 'ETH',
      decimals: 18,
    },
    rpcUrls: {
      http: ['https://arb1.arbitrum.io/rpc', 'https://arbitrum.llamarpc.com'],
    },
    blockExplorers: {
      name: 'Arbiscan',
      url: 'https://arbiscan.io',
      apiUrl: 'https://api.arbiscan.io',
    },
    layerZero: {
      endpointId: EndpointId.ARBITRUM_MAINNET,
      endpoint: '0x1a44076050125825900e736c501f859c50fE728c',
    },
    testnet: false,
  },
  optimism: {
    id: 10,
    name: 'Optimism',
    network: 'optimism',
    nativeCurrency: {
      name: 'Ether',
      symbol: 'ETH',
      decimals: 18,
    },
    rpcUrls: {
      http: ['https://mainnet.optimism.io', 'https://optimism.llamarpc.com'],
    },
    blockExplorers: {
      name: 'Optimistic Etherscan',
      url: 'https://optimistic.etherscan.io',
      apiUrl: 'https://api-optimistic.etherscan.io',
    },
    layerZero: {
      endpointId: EndpointId.OPTIMISM_MAINNET,
      endpoint: '0x1a44076050125825900e736c501f859c50fE728c',
    },
    testnet: false,
  },
  polygon: {
    id: 137,
    name: 'Polygon',
    network: 'polygon',
    nativeCurrency: {
      name: 'MATIC',
      symbol: 'MATIC',
      decimals: 18,
    },
    rpcUrls: {
      http: ['https://polygon-rpc.com', 'https://polygon.llamarpc.com'],
    },
    blockExplorers: {
      name: 'PolygonScan',
      url: 'https://polygonscan.com',
      apiUrl: 'https://api.polygonscan.com',
    },
    layerZero: {
      endpointId: EndpointId.POLYGON_MAINNET,
      endpoint: '0x1a44076050125825900e736c501f859c50fE728c',
    },
    testnet: false,
  },
  base: {
    id: 8453,
    name: 'Base',
    network: 'base',
    nativeCurrency: {
      name: 'Ether',
      symbol: 'ETH',
      decimals: 18,
    },
    rpcUrls: {
      http: ['https://mainnet.base.org', 'https://base.llamarpc.com'],
    },
    blockExplorers: {
      name: 'BaseScan',
      url: 'https://basescan.org',
      apiUrl: 'https://api.basescan.org',
    },
    layerZero: {
      endpointId: EndpointId.BASE_MAINNET,
      endpoint: '0x1a44076050125825900e736c501f859c50fE728c',
    },
    testnet: false,
  },
  bsc: {
    id: 56,
    name: 'BNB Smart Chain',
    network: 'bsc',
    nativeCurrency: {
      name: 'BNB',
      symbol: 'BNB',
      decimals: 18,
    },
    rpcUrls: {
      http: ['https://bsc-dataseed1.binance.org', 'https://bsc.llamarpc.com'],
    },
    blockExplorers: {
      name: 'BscScan',
      url: 'https://bscscan.com',
      apiUrl: 'https://api.bscscan.com',
    },
    layerZero: {
      endpointId: EndpointId.BSC_MAINNET,
      endpoint: '0x1a44076050125825900e736c501f859c50fE728c',
    },
    testnet: false,
  },
  avalanche: {
    id: 43114,
    name: 'Avalanche C-Chain',
    network: 'avalanche',
    nativeCurrency: {
      name: 'Avalanche',
      symbol: 'AVAX',
      decimals: 18,
    },
    rpcUrls: {
      http: ['https://api.avax.network/ext/bc/C/rpc', 'https://avalanche.llamarpc.com'],
    },
    blockExplorers: {
      name: 'Snowtrace',
      url: 'https://snowtrace.io',
      apiUrl: 'https://api.snowtrace.io',
    },
    layerZero: {
      endpointId: EndpointId.AVALANCHE_MAINNET,
      endpoint: '0x1a44076050125825900e736c501f859c50fE728c',
    },
    testnet: false,
  },
  sonic: {
    id: 146,
    name: 'Sonic',
    network: 'sonic',
    nativeCurrency: {
      name: 'Sonic',
      symbol: 'SONIC',
      decimals: 18,
    },
    rpcUrls: {
      http: ['https://mainnet.sonic.game'],
    },
    blockExplorers: {
      name: 'Sonic Explorer',
      url: 'https://explorer.sonic.game',
      apiUrl: 'https://explorer.sonic.game/api',
    },
    layerZero: {
      endpointId: EndpointId.SONIC_MAINNET,
      endpoint: '0x6F475642a6e85809B1c36Fa62763669b1b48DD5B',
    },
    testnet: false,
  },
  abstract: {
    id: 2741,
    name: 'Abstract',
    network: 'abstract',
    nativeCurrency: {
      name: 'Abstract',
      symbol: 'ABS',
      decimals: 18,
    },
    rpcUrls: {
      http: ['https://rpc.abstract.money'],
    },
    blockExplorers: {
      name: 'Abstract Explorer',
      url: 'https://explorer.abstract.money',
      apiUrl: 'https://explorer.abstract.money/api',
    },
    layerZero: {
      endpointId: EndpointId.ABSTRACT_MAINNET,
      endpoint: '0x5c6cfF4b7C49805F8295Ff73C204ac83f3bC4AE7',
    },
    testnet: false,
  },
  hyperevm: {
    id: 999,
    name: 'HyperEVM',
    network: 'hyperevm',
    nativeCurrency: {
      name: 'Hyper',
      symbol: 'HYPER',
      decimals: 18,
    },
    rpcUrls: {
      http: ['https://rpc.hyperevm.com'],
    },
    blockExplorers: {
      name: 'HyperEVM Explorer',
      url: 'https://explorer.hyperevm.com',
      apiUrl: 'https://explorer.hyperevm.com/api',
    },
    layerZero: {
      endpointId: EndpointId.ETHEREUM_MAINNET, // Using Ethereum endpoint as fallback
      endpoint: '0x3A73033C0b1407574C76BdBAc67f126f6b4a9AA9',
    },
    testnet: false,
  },
  fraxtal: {
    id: 252,
    name: 'Fraxtal',
    network: 'fraxtal',
    nativeCurrency: {
      name: 'Ether',
      symbol: 'ETH',
      decimals: 18,
    },
    rpcUrls: {
      http: ['https://rpc.fraxtal.com'],
    },
    blockExplorers: {
      name: 'Fraxtal Explorer',
      url: 'https://explorer.fraxtal.com',
      apiUrl: 'https://explorer.fraxtal.com/api',
    },
    layerZero: {
      endpointId: EndpointId.FRAXTAL_MAINNET,
      endpoint: '0x1a44076050125825900e736c501f859c50fE728c',
    },
    testnet: false,
  },

  // Testnet chains
  sepolia: {
    id: 11155111,
    name: 'Sepolia',
    network: 'sepolia',
    nativeCurrency: {
      name: 'Sepolia Ether',
      symbol: 'ETH',
      decimals: 18,
    },
    rpcUrls: {
      http: ['https://rpc.sepolia.org', 'https://sepolia.llamarpc.com'],
    },
    blockExplorers: {
      name: 'Sepolia Etherscan',
      url: 'https://sepolia.etherscan.io',
      apiUrl: 'https://api-sepolia.etherscan.io',
    },
    layerZero: {
      endpointId: EndpointId.ETHEREUM_TESTNET,
      endpoint: '0x6EDCE65403992e310A62460808c4b910D972f10f',
    },
    testnet: true,
  },
  arbitrumSepolia: {
    id: 421614,
    name: 'Arbitrum Sepolia',
    network: 'arbitrum-sepolia',
    nativeCurrency: {
      name: 'Sepolia Ether',
      symbol: 'ETH',
      decimals: 18,
    },
    rpcUrls: {
      http: ['https://sepolia-rollup.arbitrum.io/rpc'],
    },
    blockExplorers: {
      name: 'Arbitrum Sepolia Arbiscan',
      url: 'https://sepolia.arbiscan.io',
      apiUrl: 'https://api-sepolia.arbiscan.io',
    },
    layerZero: {
      endpointId: EndpointId.ARBITRUM_TESTNET,
      endpoint: '0x6EDCE65403992e310A62460808c4b910D972f10f',
    },
    testnet: true,
  },
  optimismSepolia: {
    id: 11155420,
    name: 'Optimism Sepolia',
    network: 'optimism-sepolia',
    nativeCurrency: {
      name: 'Sepolia Ether',
      symbol: 'ETH',
      decimals: 18,
    },
    rpcUrls: {
      http: ['https://sepolia.optimism.io'],
    },
    blockExplorers: {
      name: 'Optimism Sepolia Etherscan',
      url: 'https://sepolia-optimistic.etherscan.io',
      apiUrl: 'https://api-sepolia-optimistic.etherscan.io',
    },
    layerZero: {
      endpointId: EndpointId.OPTIMISM_TESTNET,
      endpoint: '0x6EDCE65403992e310A62460808c4b910D972f10f',
    },
    testnet: true,
  },
  polygonMumbai: {
    id: 80001,
    name: 'Polygon Mumbai',
    network: 'polygon-mumbai',
    nativeCurrency: {
      name: 'MATIC',
      symbol: 'MATIC',
      decimals: 18,
    },
    rpcUrls: {
      http: ['https://rpc-mumbai.maticvigil.com'],
    },
    blockExplorers: {
      name: 'Mumbai PolygonScan',
      url: 'https://mumbai.polygonscan.com',
      apiUrl: 'https://api-testnet.polygonscan.com',
    },
    layerZero: {
      endpointId: EndpointId.POLYGON_TESTNET,
      endpoint: '0x6EDCE65403992e310A62460808c4b910D972f10f',
    },
    testnet: true,
  },
  baseGoerli: {
    id: 84531,
    name: 'Base Goerli',
    network: 'base-goerli',
    nativeCurrency: {
      name: 'Goerli Ether',
      symbol: 'ETH',
      decimals: 18,
    },
    rpcUrls: {
      http: ['https://goerli.base.org'],
    },
    blockExplorers: {
      name: 'Base Goerli BaseScan',
      url: 'https://goerli.basescan.org',
      apiUrl: 'https://api-goerli.basescan.org',
    },
    layerZero: {
      endpointId: EndpointId.BASE_TESTNET,
      endpoint: '0x6EDCE65403992e310A62460808c4b910D972f10f',
    },
    testnet: true,
  },
};

export const MAINNET_CHAINS = Object.entries(CHAINS)
  .filter(([, config]) => !config.testnet)
  .reduce((acc, [key, config]) => ({ ...acc, [key]: config }), {});

export const TESTNET_CHAINS = Object.entries(CHAINS)
  .filter(([, config]) => config.testnet)
  .reduce((acc, [key, config]) => ({ ...acc, [key]: config }), {});

export const getChainById = (chainId: number): ChainConfig | undefined => {
  return Object.values(CHAINS).find(chain => chain.id === chainId);
};

export const getChainByName = (name: string): ChainConfig | undefined => {
  return CHAINS[name.toLowerCase()];
};

export const getChainByNetwork = (network: string): ChainConfig | undefined => {
  return Object.values(CHAINS).find(chain => chain.network === network);
}; 