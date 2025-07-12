import { 
  CHAINS, 
  ChainConfig, 
  MAINNET_CHAINS, 
  TESTNET_CHAINS 
} from './chains';
import { 
  COLLATERALS, 
  CollateralConfig, 
  STABLECOINS, 
  CRYPTO_COLLATERALS 
} from './collaterals';
import { 
  ALL_DEPLOYMENTS, 
  DeploymentConfig, 
  ContractAddresses 
} from './contracts';

/**
 * Configuration utility functions for Torque FX
 */

export interface NetworkInfo {
  chain: ChainConfig;
  deployment?: DeploymentConfig;
  supportedCollaterals: CollateralConfig[];
}

/**
 * Get comprehensive network information including chain config, deployment status, and supported collaterals
 */
export const getNetworkInfo = (network: string): NetworkInfo | undefined => {
  const chain = CHAINS[network];
  if (!chain) return undefined;

  const deployment = ALL_DEPLOYMENTS[network];
  const supportedCollaterals = getSupportedCollateralsForNetwork(network);

  return {
    chain,
    deployment,
    supportedCollaterals,
  };
};

/**
 * Get all networks with their comprehensive information
 */
export const getAllNetworksInfo = (): Record<string, NetworkInfo> => {
  const networks: Record<string, NetworkInfo> = {};
  
  Object.keys(CHAINS).forEach(network => {
    const info = getNetworkInfo(network);
    if (info) {
      networks[network] = info;
    }
  });

  return networks;
};

/**
 * Get supported collateral tokens for a specific network
 */
export const getSupportedCollateralsForNetwork = (network: string): CollateralConfig[] => {
  return Object.values(COLLATERALS).filter(
    collateral => 
      collateral.addresses[network] && 
      collateral.addresses[network] !== '0x0000000000000000000000000000000000000000'
  );
};

/**
 * Get all networks that support a specific collateral token
 */
export const getNetworksForCollateral = (symbol: string): string[] => {
  const collateral = COLLATERALS[symbol.toUpperCase()];
  if (!collateral) return [];

  return Object.keys(CHAINS).filter(network => 
    collateral.addresses[network] && 
    collateral.addresses[network] !== '0x0000000000000000000000000000000000000000'
  );
};

/**
 * Check if a network supports a specific collateral token
 */
export const isCollateralSupportedOnNetwork = (symbol: string, network: string): boolean => {
  const collateral = COLLATERALS[symbol.toUpperCase()];
  if (!collateral) return false;

  return !!(
    collateral.addresses[network] && 
    collateral.addresses[network] !== '0x0000000000000000000000000000000000000000'
  );
};

/**
 * Get all deployed networks
 */
export const getDeployedNetworks = (): string[] => {
  return Object.entries(ALL_DEPLOYMENTS)
    .filter(([, deployment]) => deployment.deployed)
    .map(([network]) => network);
};

/**
 * Get all networks that have Torque contracts deployed
 */
export const getNetworksWithDeployments = (): string[] => {
  return Object.keys(ALL_DEPLOYMENTS);
};

/**
 * Get networks grouped by deployment status
 */
export const getNetworksByDeploymentStatus = () => {
  const deployed: string[] = [];
  const notDeployed: string[] = [];

  Object.entries(ALL_DEPLOYMENTS).forEach(([network, deployment]) => {
    if (deployment.deployed) {
      deployed.push(network);
    } else {
      notDeployed.push(network);
    }
  });

  return { deployed, notDeployed };
};

/**
 * Get networks grouped by type (mainnet/testnet)
 */
export const getNetworksByType = () => {
  const mainnet = Object.keys(MAINNET_CHAINS);
  const testnet = Object.keys(TESTNET_CHAINS);

  return { mainnet, testnet };
};

/**
 * Get all available collateral symbols
 */
export const getAllCollateralSymbols = (): string[] => {
  return Object.keys(COLLATERALS);
};

/**
 * Get stablecoin symbols
 */
export const getStablecoinSymbols = (): string[] => {
  return [...STABLECOINS];
};

/**
 * Get crypto collateral symbols
 */
export const getCryptoCollateralSymbols = (): string[] => {
  return [...CRYPTO_COLLATERALS];
};

/**
 * Validate if a network is supported
 */
export const isNetworkSupported = (network: string): boolean => {
  return network in CHAINS;
};

/**
 * Validate if a collateral symbol is supported
 */
export const isCollateralSymbolSupported = (symbol: string): boolean => {
  return symbol.toUpperCase() in COLLATERALS;
};

/**
 * Get the native token symbol for a network
 */
export const getNativeTokenSymbol = (network: string): string => {
  const chain = CHAINS[network];
  return chain?.nativeCurrency.symbol || 'ETH';
};

/**
 * Get the native token decimals for a network
 */
export const getNativeTokenDecimals = (network: string): number => {
  const chain = CHAINS[network];
  return chain?.nativeCurrency.decimals || 18;
};

/**
 * Get RPC URLs for a network
 */
export const getRpcUrls = (network: string): string[] => {
  const chain = CHAINS[network];
  return chain?.rpcUrls.http || [];
};

/**
 * Get block explorer URL for a network
 */
export const getBlockExplorerUrl = (network: string): string => {
  const chain = CHAINS[network];
  return chain?.blockExplorers.url || '';
};

/**
 * Get block explorer API URL for a network
 */
export const getBlockExplorerApiUrl = (network: string): string => {
  const chain = CHAINS[network];
  return chain?.blockExplorers.apiUrl || '';
};

/**
 * Get LayerZero endpoint for a network
 */
export const getLayerZeroEndpoint = (network: string): string => {
  const chain = CHAINS[network];
  return chain?.layerZero.endpoint || '';
};

/**
 * Get LayerZero endpoint ID for a network
 */
export const getLayerZeroEndpointId = (network: string): number => {
  const chain = CHAINS[network];
  return chain?.layerZero.endpointId || 0;
};

/**
 * Format network name for display
 */
export const formatNetworkName = (network: string): string => {
  const chain = CHAINS[network];
  return chain?.name || network;
};

/**
 * Get network configuration summary
 */
export const getNetworkSummary = (network: string) => {
  const chain = CHAINS[network];
  const deployment = ALL_DEPLOYMENTS[network];
  const supportedCollaterals = getSupportedCollateralsForNetwork(network);

  return {
    name: chain?.name || network,
    chainId: chain?.id || 0,
    isTestnet: chain?.testnet || false,
    isDeployed: deployment?.deployed || false,
    nativeToken: chain?.nativeCurrency.symbol || 'ETH',
    supportedCollaterals: supportedCollaterals.map(c => c.symbol),
    rpcUrls: chain?.rpcUrls.http || [],
    blockExplorer: chain?.blockExplorers.url || '',
    layerZeroEndpoint: chain?.layerZero.endpoint || '',
  };
};

/**
 * Get all network summaries
 */
export const getAllNetworkSummaries = () => {
  const summaries: Record<string, ReturnType<typeof getNetworkSummary>> = {};
  
  Object.keys(CHAINS).forEach(network => {
    summaries[network] = getNetworkSummary(network);
  });

  return summaries;
};

/**
 * Filter networks by criteria
 */
export const filterNetworks = (criteria: {
  deployed?: boolean;
  testnet?: boolean;
  hasCollateral?: string;
  hasEngine?: string;
}) => {
  return Object.keys(CHAINS).filter(network => {
    const deployment = ALL_DEPLOYMENTS[network];
    const chain = CHAINS[network];

    if (criteria.deployed !== undefined && deployment?.deployed !== criteria.deployed) {
      return false;
    }

    if (criteria.testnet !== undefined && chain?.testnet !== criteria.testnet) {
      return false;
    }

    if (criteria.hasCollateral && !isCollateralSupportedOnNetwork(criteria.hasCollateral, network)) {
      return false;
    }

    if (criteria.hasEngine && deployment?.addresses.engines[criteria.hasEngine as keyof typeof deployment.addresses.engines] === '0x0000000000000000000000000000000000000000') {
      return false;
    }

    return true;
  });
}; 