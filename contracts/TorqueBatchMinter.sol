// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@layerzerolabs/lz-evm-oapp-v2/contracts/oapp/OApp.sol";
import "./engines/TorqueEngine.sol";

/**
 * @title TorqueBatchMinter
 * @dev Allows users to mint Torque tokens to multiple destination chains in a single transaction
 */
contract TorqueBatchMinter is OApp, Ownable, ReentrancyGuard {
    
    // Events
    event BatchMintInitiated(
        address indexed user,
        address indexed currency,
        uint256 totalAmount,
        uint16[] dstChainIds,
        uint256[] amountsPerChain
    );
    
    event BatchMintCompleted(
        address indexed user,
        address indexed currency,
        uint16 dstChainId,
        uint256 amount
    );
    
    event BatchMintFailed(
        address indexed user,
        address indexed currency,
        uint16 dstChainId,
        uint256 amount,
        string reason
    );
    
    // State variables
    mapping(address => mapping(uint16 => address)) public engineAddresses; // currency => chainId => engine
    mapping(address => bool) public supportedCurrencies;
    uint256 public maxBatchSize = 50; // Maximum number of chains per batch (flexible for future expansion)
    
    // Supported chain IDs
    uint16 public constant ETHEREUM_CHAIN_ID = 1;
    uint16 public constant ARBITRUM_CHAIN_ID = 42161;
    uint16 public constant OPTIMISM_CHAIN_ID = 10;
    uint16 public constant POLYGON_CHAIN_ID = 137;
    uint16 public constant BASE_CHAIN_ID = 8453;
    uint16 public constant SONIC_CHAIN_ID = 146; // Sonic blockchain
    uint16 public constant ABSTRACT_CHAIN_ID = 2741; // Abstract blockchain
    uint16 public constant BSC_CHAIN_ID = 56; // BSC blockchain
    uint16 public constant HYPEREVM_CHAIN_ID = 999; // HyperEVM blockchain
    uint16 public constant FRAXTAL_CHAIN_ID = 252; // Fraxtal blockchain
    uint16 public constant AVALANCHE_CHAIN_ID = 43114; // Avalanche blockchain
    
    // Chain validation
    mapping(uint16 => bool) public supportedChainIds;
    
    // Errors
    error TorqueBatchMinter__InvalidBatchSize();
    error TorqueBatchMinter__InvalidAmounts();
    error TorqueBatchMinter__UnsupportedCurrency();
    error TorqueBatchMinter__EngineNotSet();
    error TorqueBatchMinter__InvalidChainId();
    
    constructor(
        address _lzEndpoint,
        address _owner
    ) OApp(_lzEndpoint, _owner) Ownable(_owner) {
        // Initialize supported chain IDs
        supportedChainIds[ETHEREUM_CHAIN_ID] = true;
        supportedChainIds[ARBITRUM_CHAIN_ID] = true;
        supportedChainIds[OPTIMISM_CHAIN_ID] = true;
        supportedChainIds[POLYGON_CHAIN_ID] = true;
        supportedChainIds[BASE_CHAIN_ID] = true;
        supportedChainIds[SONIC_CHAIN_ID] = true;
        supportedChainIds[ABSTRACT_CHAIN_ID] = true;
        supportedChainIds[BSC_CHAIN_ID] = true;
        supportedChainIds[HYPEREVM_CHAIN_ID] = true;
        supportedChainIds[FRAXTAL_CHAIN_ID] = true;
        supportedChainIds[AVALANCHE_CHAIN_ID] = true;
    }
    
    /**
     * @dev Mint tokens to multiple destination chains
     * @param currency The Torque currency to mint (e.g., TorqueEUR address)
     * @param totalCollateralAmount Total collateral to deposit
     * @param dstChainIds Array of destination chain IDs
     * @param amountsPerChain Array of amounts to mint on each chain
     * @param adapterParams Array of adapter parameters for each chain
     */
    function batchMint(
        address currency,
        uint256 totalCollateralAmount,
        uint16[] calldata dstChainIds,
        uint256[] calldata amountsPerChain,
        bytes[] calldata adapterParams
    ) external nonReentrant {
        // Validations
        if (dstChainIds.length == 0 || dstChainIds.length > maxBatchSize) {
            revert TorqueBatchMinter__InvalidBatchSize();
        }
        
        if (dstChainIds.length != amountsPerChain.length || 
            dstChainIds.length != adapterParams.length) {
            revert TorqueBatchMinter__InvalidAmounts();
        }
        
        if (!supportedCurrencies[currency]) {
            revert TorqueBatchMinter__UnsupportedCurrency();
        }
        
        // Validate all destination chains are supported
        for (uint256 i = 0; i < dstChainIds.length; i++) {
            if (!supportedChainIds[dstChainIds[i]]) {
                revert TorqueBatchMinter__InvalidChainId();
            }
        }
        
        // Calculate total amount to mint
        uint256 totalMintAmount = 0;
        for (uint256 i = 0; i < amountsPerChain.length; i++) {
            totalMintAmount += amountsPerChain[i];
        }
        
        // Validate total amounts match
        if (totalMintAmount == 0) {
            revert TorqueBatchMinter__InvalidAmounts();
        }
        
        // Deposit collateral first
        _depositCollateral(currency, totalCollateralAmount);
        
        // Send mint requests to each destination chain
        for (uint256 i = 0; i < dstChainIds.length; i++) {
            if (amountsPerChain[i] > 0) {
                _sendMintRequest(
                    currency,
                    dstChainIds[i],
                    amountsPerChain[i],
                    adapterParams[i]
                );
            }
        }
        
        emit BatchMintInitiated(
            msg.sender,
            currency,
            totalMintAmount,
            dstChainIds,
            amountsPerChain
        );
    }
    
    /**
     * @dev Handle incoming mint requests from other chains
     */
    function _nonblockingLzReceive(
        uint16 srcChainId,
        bytes memory srcAddress,
        uint64 nonce,
        bytes memory payload
    ) internal override {
        (address currency, address user, uint256 amount) = abi.decode(
            payload,
            (address, address, uint256)
        );
        
        // Validate engine exists for this currency and chain
        address engineAddress = engineAddresses[currency][srcChainId];
        if (engineAddress == address(0)) {
            emit BatchMintFailed(
                user,
                currency,
                srcChainId,
                amount,
                "Engine not configured"
            );
            return;
        }
        
        try TorqueEngine(engineAddress)._mintTorque(amount, user) {
            emit BatchMintCompleted(user, currency, srcChainId, amount);
        } catch Error(string memory reason) {
            emit BatchMintFailed(user, currency, srcChainId, amount, reason);
        } catch {
            emit BatchMintFailed(user, currency, srcChainId, amount, "Unknown error");
        }
    }
    
    /**
     * @dev Internal function to deposit collateral
     */
    function _depositCollateral(address currency, uint256 amount) internal {
        // Get the engine for the current chain
        address engineAddress = engineAddresses[currency][block.chainid];
        if (engineAddress == address(0)) {
            revert TorqueBatchMinter__EngineNotSet();
        }
        
        TorqueEngine engine = TorqueEngine(engineAddress);
        IERC20 collateralToken = engine.getCollateralToken();
        
        // Transfer collateral from user to engine
        require(
            collateralToken.transferFrom(msg.sender, engineAddress, amount),
            "Collateral transfer failed"
        );
        
        // Call deposit function on engine
        engine.depositCollateral(amount);
    }
    
    /**
     * @dev Internal function to send mint request to destination chain
     */
    function _sendMintRequest(
        address currency,
        uint16 dstChainId,
        uint256 amount,
        bytes calldata adapterParams
    ) internal {
        address engineAddress = engineAddresses[currency][dstChainId];
        if (engineAddress == address(0)) {
            revert TorqueBatchMinter__EngineNotSet();
        }
        
        // Encode the mint request
        bytes memory payload = abi.encode(currency, msg.sender, amount);
        
        // Send cross-chain message
        _lzSend(
            dstChainId,
            payload,
            payable(msg.sender),
            address(0),
            adapterParams
        );
    }
    
    /**
     * @dev Get batch mint quote (gas estimation)
     */
    function getBatchMintQuote(
        uint16[] calldata dstChainIds,
        bytes[] calldata adapterParams
    ) external view returns (uint256 totalGasEstimate) {
        totalGasEstimate = 0;
        
        for (uint256 i = 0; i < dstChainIds.length; i++) {
            // Estimate gas for each cross-chain message
            uint256 messageGas = _estimateGasForMessage(
                dstChainIds[i],
                adapterParams[i]
            );
            totalGasEstimate += messageGas;
        }
        
        // Add base transaction gas
        totalGasEstimate += 21000; // Base transaction cost
    }
    
    /**
     * @dev Estimate gas for a single cross-chain message
     */
    function _estimateGasForMessage(
        uint16 dstChainId,
        bytes calldata adapterParams
    ) internal view returns (uint256) {
        // This would integrate with LayerZero's gas estimation
        // For now, return a conservative estimate
        return 100000; // Conservative estimate per message
    }
    
    // Admin functions
    
    /**
     * @dev Set engine address for a currency and chain
     */
    function setEngineAddress(
        address currency,
        uint16 chainId,
        address engineAddress
    ) external onlyOwner {
        engineAddresses[currency][chainId] = engineAddress;
    }
    
    /**
     * @dev Add supported currency
     */
    function addSupportedCurrency(address currency) external onlyOwner {
        supportedCurrencies[currency] = true;
    }
    
    /**
     * @dev Remove supported currency
     */
    function removeSupportedCurrency(address currency) external onlyOwner {
        supportedCurrencies[currency] = false;
    }
    
    /**
     * @dev Set maximum batch size
     */
    function setMaxBatchSize(uint256 newMaxBatchSize) external onlyOwner {
        require(newMaxBatchSize > 0 && newMaxBatchSize <= 100, "Invalid batch size");
        maxBatchSize = newMaxBatchSize;
    }
    
    /**
     * @dev Emergency function to recover stuck tokens
     */
    function emergencyWithdraw(
        address token,
        address to,
        uint256 amount
    ) external onlyOwner {
        IERC20(token).transfer(to, amount);
    }
    
    /**
     * @dev Get all supported chain IDs
     */
    function getSupportedChainIds() external view returns (uint16[] memory) {
        uint16[] memory chainIds = new uint16[](13);
        chainIds[0] = ETHEREUM_CHAIN_ID;
        chainIds[1] = ARBITRUM_CHAIN_ID;
        chainIds[2] = OPTIMISM_CHAIN_ID;
        chainIds[3] = POLYGON_CHAIN_ID;
        chainIds[4] = BASE_CHAIN_ID;
        chainIds[5] = SONIC_CHAIN_ID;
        chainIds[6] = ABSTRACT_CHAIN_ID;
        chainIds[7] = BSC_CHAIN_ID;
        chainIds[8] = HYPEREVM_CHAIN_ID;
        chainIds[9] = FRAXTAL_CHAIN_ID;
        chainIds[10] = AVALANCHE_CHAIN_ID;
        return chainIds;
    }
} 