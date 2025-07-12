// Export all configuration modules
export * from './chains';
export * from './collateral';
export * from './contracts';
export * from './utils';

// Re-export commonly used types and constants
export type { ChainConfig } from './chains';
export type { CollateralToken } from './collateral';
export type { ContractAddresses, DeploymentConfig } from './contracts';

// Export commonly used constants
export { CHAINS, MAINNET_CHAINS, TESTNET_CHAINS } from './chains';
export { collateralTokens } from './collateral';
export { 
  MAINNET_DEPLOYMENTS, 
  TESTNET_DEPLOYMENTS, 
  ALL_DEPLOYMENTS 
} from './contracts';

// Export utility functions
export {
  getChainById,
  getChainByName,
  getChainByNetwork,
} from './chains';

export {
  getDeploymentByChainId,
  getDeploymentByNetwork,
  getDeployedNetworks,
  getMainnetDeployments,
  getTestnetDeployments,
  updateDeployment,
  getContractAddress,
  getEngineAddress,
  getCurrencyAddress,
} from './contracts'; 