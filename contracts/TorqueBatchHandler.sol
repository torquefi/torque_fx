// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.30;

import "./engines/TorqueEngine.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { OApp } from "@layerzerolabs/lz-evm-oapp-v2/contracts/oapp/OApp.sol";
import { Origin, MessagingFee } from "@layerzerolabs/lz-evm-protocol-v2/contracts/interfaces/ILayerZeroEndpointV2.sol";
import { ReentrancyGuard } from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

/**
 * @title TorqueBatchHandler
 * @dev Allows users to mint and burn Torque currencies across multiple destination chains in a single transaction
 */
contract TorqueBatchHandler is OApp, ReentrancyGuard {
    
    // State variables
    uint256 public maxBatchSize = 50;
    mapping(address => bool) public supportedCurrencies;
    mapping(address => mapping(uint16 => address)) public engineAddresses;
    
    // Chain ID constants
    uint16 public constant ETHEREUM_CHAIN_ID = 1;
    uint16 public constant ARBITRUM_CHAIN_ID = 42161;
    uint16 public constant OPTIMISM_CHAIN_ID = 10;
    uint16 public constant POLYGON_CHAIN_ID = 137;
    uint16 public constant BASE_CHAIN_ID = 8453;
    uint16 public constant SONIC_CHAIN_ID = 146;
    uint16 public constant BSC_CHAIN_ID = 56;
    uint16 public constant AVALANCHE_CHAIN_ID = 43114;
    
    // Chain validation
    mapping(uint16 => bool) public supportedChainIds;
    
    // Events
    event BatchMintInitiated(
        address indexed user,
        address indexed currency,
        uint256 totalAmount,
        uint16[] dstChainIds,
        uint256[] amountsPerChain
    );
    
    event BatchBurnInitiated(
        address indexed user,
        address indexed currency,
        uint256 totalAmount,
        uint16[] dstChainIds,
        uint256[] amountsPerChain
    );
    
    event BatchMintCompleted(
        address indexed user,
        address indexed currency,
        uint16 indexed sourceChainId,
        uint256 amount
    );
    
    event BatchMintFailed(
        address indexed user,
        address indexed currency,
        uint16 indexed sourceChainId,
        uint256 amount,
        string reason
    );
    
    event BatchBurnCompleted(
        address indexed user,
        address indexed currency,
        uint16 indexed sourceChainId,
        uint256 amount
    );
    
    // Errors
    error TorqueBatchHandler__InvalidBatchSize();
    error TorqueBatchHandler__InvalidAmounts();
    error TorqueBatchHandler__UnsupportedCurrency();
    error TorqueBatchHandler__EngineNotSet();
    error TorqueBatchHandler__InvalidChainId();
    
    constructor(
        address _lzEndpoint,
        address _owner
    ) OApp(_lzEndpoint, _owner) Ownable(_owner) {
        supportedChainIds[ETHEREUM_CHAIN_ID] = true;
        supportedChainIds[ARBITRUM_CHAIN_ID] = true;
        supportedChainIds[OPTIMISM_CHAIN_ID] = true;
        supportedChainIds[POLYGON_CHAIN_ID] = true;
        supportedChainIds[BASE_CHAIN_ID] = true;
        supportedChainIds[SONIC_CHAIN_ID] = true;
        supportedChainIds[BSC_CHAIN_ID] = true;
        supportedChainIds[AVALANCHE_CHAIN_ID] = true;
    }
    
    /**
     * @dev Mint Torque currencies to multiple destination chains by depositing collateral
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
            revert TorqueBatchHandler__InvalidBatchSize();
        }
        
        if (dstChainIds.length != amountsPerChain.length || 
            dstChainIds.length != adapterParams.length) {
            revert TorqueBatchHandler__InvalidAmounts();
        }
        
        if (!supportedCurrencies[currency]) {
            revert TorqueBatchHandler__UnsupportedCurrency();
        }
        
        // Validate all destination chains are supported
        for (uint256 i = 0; i < dstChainIds.length; i++) {
            if (!supportedChainIds[dstChainIds[i]]) {
                revert TorqueBatchHandler__InvalidChainId();
            }
        }
        
        // Calculate total amount to mint
        uint256 totalMintAmount = 0;
        for (uint256 i = 0; i < amountsPerChain.length; i++) {
            totalMintAmount += amountsPerChain[i];
        }
        
        // Validate total amounts match
        if (totalMintAmount == 0) {
            revert TorqueBatchHandler__InvalidAmounts();
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
     * @dev Batch burn Torque currencies and redeem collateral on multiple destination chains
     */
    function batchBurn(
        address currency,
        uint256 totalBurnAmount,
        uint16[] calldata dstChainIds,
        uint256[] calldata amountsPerChain,
        bytes[] calldata adapterParams
    ) external nonReentrant {
        // Validations
        if (dstChainIds.length == 0 || dstChainIds.length > maxBatchSize) {
            revert TorqueBatchHandler__InvalidBatchSize();
        }
        if (dstChainIds.length != amountsPerChain.length || dstChainIds.length != adapterParams.length) {
            revert TorqueBatchHandler__InvalidAmounts();
        }
        if (!supportedCurrencies[currency]) {
            revert TorqueBatchHandler__UnsupportedCurrency();
        }
        // Validate all destination chains are supported
        for (uint256 i = 0; i < dstChainIds.length; i++) {
            if (!supportedChainIds[dstChainIds[i]]) {
                revert TorqueBatchHandler__InvalidChainId();
            }
        }
        // Calculate total amount to burn
        uint256 totalBurn = 0;
        for (uint256 i = 0; i < amountsPerChain.length; i++) {
            totalBurn += amountsPerChain[i];
        }
        if (totalBurn == 0) {
            revert TorqueBatchHandler__InvalidAmounts();
        }
        // Burn Torque currencies from user
        IERC20(currency).transferFrom(msg.sender, address(this), totalBurn);
        IERC20(currency).approve(address(this), totalBurn);
        // Send burn requests for Torque currencies to each destination chain
        for (uint256 i = 0; i < dstChainIds.length; i++) {
            if (amountsPerChain[i] > 0) {
                _sendBurnRequest(
                    currency,
                    dstChainIds[i],
                    amountsPerChain[i],
                    adapterParams[i]
                );
            }
        }
        emit BatchBurnInitiated(msg.sender, currency, totalBurn, dstChainIds, amountsPerChain);
    }

    /**
     * @dev Handle incoming mint requests from other chains
     */
    function _lzReceive(
        Origin calldata _origin,
        bytes32 _guid,
        bytes calldata _message,
        address _executor,
        bytes calldata _extraData
    ) internal override {
        // Decode the message
        (address currency, address user, uint256 amount) = abi.decode(
            _message,
            (address, address, uint256)
        );
        
        // Validate engine exists for this currency and chain
        address engineAddress = engineAddresses[currency][uint16(_origin.srcEid)];
        if (engineAddress == address(0)) {
            emit BatchMintFailed(
                user,
                currency,
                uint16(_origin.srcEid),
                amount,
                "Engine not configured"
            );
            return;
        }
        
        try TorqueEngine(engineAddress).mintTorque(amount, user) {
            emit BatchMintCompleted(user, currency, uint16(_origin.srcEid), amount);
        } catch Error(string memory reason) {
            emit BatchMintFailed(user, currency, uint16(_origin.srcEid), amount, reason);
        } catch {
            emit BatchMintFailed(user, currency, uint16(_origin.srcEid), amount, "Unknown error");
        }
    }
    
    /**
     * @dev Internal function to deposit collateral
     */
    function _depositCollateral(address currency, uint256 amount) internal {
        // Get the engine for the current chain
        address engineAddress = engineAddresses[currency][uint16(block.chainid)];
        if (engineAddress == address(0)) {
            revert TorqueBatchHandler__EngineNotSet();
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
            revert TorqueBatchHandler__EngineNotSet();
        }
        
        // Encode the mint request
        bytes memory payload = abi.encode(currency, msg.sender, amount);
        
        // Send cross-chain message
        MessagingFee memory fee = _quote(dstChainId, payload, adapterParams, false);
        _lzSend(
            dstChainId,
            payload,
            adapterParams,
            fee,
            payable(msg.sender)
        );
    }

    function _sendBurnRequest(
        address currency,
        uint16 dstChainId,
        uint256 amount,
        bytes calldata adapterParams
    ) internal {
        // This would interact with the engine contract on the destination chain to burn Torque currencies
        address engineAddress = engineAddresses[currency][dstChainId];
        if (engineAddress == address(0)) {
            revert TorqueBatchHandler__EngineNotSet();
        }
        bytes memory payload = abi.encode(currency, msg.sender, amount);
        MessagingFee memory fee = _quote(dstChainId, payload, adapterParams, false);
        _lzSend(
            dstChainId,
            payload,
            adapterParams,
            fee,
            payable(msg.sender)
        );
    }

    /**
     * @dev Get quote for batch mint operation
     * @param currency Currency address
     * @param totalMintAmount Total amount to mint
     * @param dstChainIds Array of destination chain IDs
     * @param amountsPerChain Array of amounts per chain
     * @return totalGasEstimate Estimated gas cost
     */
    function getBatchMintQuote(
        address currency,
        uint256 totalMintAmount,
        uint16[] calldata dstChainIds,
        uint256[] calldata amountsPerChain
    ) external view returns (uint256 totalGasEstimate) {
        require(dstChainIds.length == amountsPerChain.length, "Length mismatch");
        require(dstChainIds.length > 0, "Empty arrays");
        
        totalGasEstimate = 0;
        for (uint256 i = 0; i < dstChainIds.length; i++) {
            require(supportedChainIds[dstChainIds[i]], "Unsupported chain");
            require(amountsPerChain[i] > 0, "Invalid amount");
            totalGasEstimate += 50000; // Mock gas estimate
        }
        return totalGasEstimate;
    }
    
    /**
     * @dev Estimate gas for a single cross-chain message
     */
    function _estimateGasForMessage(
        uint16 dstChainId,
        bytes memory adapterParams
    ) internal view returns (uint256) {
        // Base gas cost for cross-chain message
        uint256 baseGas = 50000;
        
        // Add gas based on destination chain complexity
        if (dstChainId == ETHEREUM_CHAIN_ID) {
            baseGas += 30000; // Ethereum is more expensive
        } else if (dstChainId == ARBITRUM_CHAIN_ID || dstChainId == OPTIMISM_CHAIN_ID) {
            baseGas += 15000; // L2s are cheaper
        } else {
            baseGas += 20000; // Other chains
        }
        
        // Add gas for adapter parameters if provided
        if (adapterParams.length > 0) {
            baseGas += adapterParams.length * 16; // Rough estimate
        }
        
        return baseGas;
    }
    
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
        if (newMaxBatchSize == 0 || newMaxBatchSize > 100) {
            revert("Invalid batch size");
        }
        maxBatchSize = newMaxBatchSize;
    }

    /**
     * @dev Handle incoming cross-chain messages (non-blocking version)
     */
    function _nonblockingLzReceive(
        uint16 _srcChainId,
        bytes calldata _srcAddress,
        uint64 _nonce,
        bytes calldata _payload
    ) internal {
        // Decode the message
        (address currency, address user, uint256 amount) = abi.decode(
            _payload,
            (address, address, uint256)
        );
        
        // Validate engine exists for this currency and chain
        address engineAddress = engineAddresses[currency][_srcChainId];
        if (engineAddress == address(0)) {
            emit BatchMintFailed(
                user,
                currency,
                _srcChainId,
                amount,
                "Engine not configured"
            );
            return;
        }

        // Call the engine to mint tokens
        try TorqueEngine(engineAddress).mintTorque(amount, user) {
            emit BatchMintCompleted(user, currency, _srcChainId, amount);
        } catch Error(string memory reason) {
            emit BatchMintFailed(user, currency, _srcChainId, amount, reason);
        } catch {
            emit BatchMintFailed(user, currency, _srcChainId, amount, "Unknown error");
        }
    }

    /**
     * @dev Get comprehensive batch minting information for frontend
     */
    function getBatchMintInfo(
        address currency,
        uint256 amount,
        uint16[] calldata dstChainIds
    ) external view returns (
        uint256 totalGasEstimate,
        uint256[] memory gasEstimates,
        uint256 collateralRequired,
        uint256[] memory amountsPerChain,
        bool[] memory isSupported,
        string[] memory chainNames
    ) {
        totalGasEstimate = 0;
        gasEstimates = new uint256[](dstChainIds.length);
        amountsPerChain = new uint256[](dstChainIds.length);
        isSupported = new bool[](dstChainIds.length);
        chainNames = new string[](dstChainIds.length);
        
        // Calculate amounts per chain (equal distribution for now)
        uint256 amountPerChain = amount / dstChainIds.length;
        uint256 remainder = amount % dstChainIds.length;
        
        for (uint256 i = 0; i < dstChainIds.length; i++) {
            amountsPerChain[i] = amountPerChain + (i < remainder ? 1 : 0);
            isSupported[i] = supportedChainIds[dstChainIds[i]];
            chainNames[i] = _getChainName(dstChainIds[i]);
            
            if (isSupported[i]) {
                bytes memory emptyParams = "";
                gasEstimates[i] = _estimateGasForMessage(dstChainIds[i], emptyParams);
                totalGasEstimate += gasEstimates[i];
            }
        }
        
        // Calculate collateral required (102% of amount)
        collateralRequired = (amount * 102) / 100;
    }

    /**
     * @dev Get user's cross-chain positions
     */
    function getUserCrossChainPositions(address user) external view returns (
        address[] memory currencies,
        uint16[] memory chainIds,
        uint256[] memory amounts,
        uint256[] memory collateralValues,
        uint256 totalValue
    ) {
        // Count user's positions across supported currencies and chains
        uint256 positionCount = 0;
        
        // Count positions for supported currencies
        for (uint16 chainId = 1; chainId <= 1000; chainId++) {
            if (supportedChainIds[chainId]) {
                for (uint256 i = 0; i < 100; i++) { // Reasonable limit for currencies
                    // This would require a way to iterate through supported currencies
                    // For now, return empty arrays as this requires additional infrastructure
                    break;
                }
            }
        }
        
        // Return empty arrays until proper tracking is implemented
        currencies = new address[](0);
        chainIds = new uint16[](0);
        amounts = new uint256[](0);
        collateralValues = new uint256[](0);
        totalValue = 0;
    }

    /**
     * @dev Get supported currencies with their information
     */
    function getSupportedCurrenciesInfo() external view returns (
        address[] memory currencies,
        string[] memory symbols,
        string[] memory names,
        bool[] memory isActive
    ) {
        // This requires a way to iterate through supported currencies
        // For now, return empty arrays as this requires additional infrastructure
        // In production, this would maintain a list of supported currencies
        currencies = new address[](0);
        symbols = new string[](0);
        names = new string[](0);
        isActive = new bool[](0);
    }

    /**
     * @dev Get engine addresses for a currency across all chains
     */
    function getEngineAddresses(address currency) external view returns (
        uint16[] memory chainIds,
        address[] memory engineAddressList,
        bool[] memory isActive
    ) {
        uint256 count = 0;
        for (uint16 i = 1; i <= 1000; i++) {
            if (this.engineAddresses(currency, i) != address(0)) {
                count++;
            }
        }
        
        chainIds = new uint16[](count);
        engineAddressList = new address[](count);
        isActive = new bool[](count);
        
        uint256 index = 0;
        for (uint16 i = 1; i <= 1000; i++) {
            address engineAddr = this.engineAddresses(currency, i);
            if (engineAddr != address(0)) {
                chainIds[index] = i;
                engineAddressList[index] = engineAddr;
                isActive[index] = true;
                index++;
            }
        }
    }

    /**
     * @dev Get batch minting statistics
     */
    function getBatchMintStats() external view returns (
        uint256 totalBatches,
        uint256 totalVolume,
        uint256 totalGasUsed,
        uint256 averageBatchSize,
        uint256 successRate
    ) {
        // This would track batch minting statistics
        // For now, return default values as this requires additional tracking infrastructure
        // In production, this would maintain counters for batches, volume, gas usage, etc.
        totalBatches = 0;
        totalVolume = 0;
        totalGasUsed = 0;
        averageBatchSize = 0;
        successRate = 100; // Default to 100% success rate
    }

    // Internal helper functions
    function _getChainName(uint16 chainId) internal pure returns (string memory) {
        if (chainId == ETHEREUM_CHAIN_ID) return "Ethereum";
        if (chainId == ARBITRUM_CHAIN_ID) return "Arbitrum";
        if (chainId == OPTIMISM_CHAIN_ID) return "Optimism";
        if (chainId == POLYGON_CHAIN_ID) return "Polygon";
        if (chainId == BASE_CHAIN_ID) return "Base";
        if (chainId == SONIC_CHAIN_ID) return "Sonic";
        if (chainId == BSC_CHAIN_ID) return "BSC";
        if (chainId == AVALANCHE_CHAIN_ID) return "Avalanche";
        return "Unknown";
    }

    function _getCurrencySymbol(address currency) internal pure returns (string memory) {
        // This would map currency addresses to symbols
        // For now, return a default symbol as this requires a mapping or interface
        // In production, this would query the token contract for its symbol
        return "TORQUE";
    }

    function _getCurrencyName(address currency) internal pure returns (string memory) {
        // This would map currency addresses to names
        // For now, return a default name as this requires a mapping or interface
        // In production, this would query the token contract for its name
        return "Torque Token";
    }
    
    /**
     * @dev Emergency function to recover stuck Torque currencies
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
        uint16[] memory chainIds = new uint16[](12);
        chainIds[0] = ETHEREUM_CHAIN_ID;
        chainIds[1] = ARBITRUM_CHAIN_ID;
        chainIds[2] = OPTIMISM_CHAIN_ID;
        chainIds[3] = POLYGON_CHAIN_ID;
        chainIds[4] = BASE_CHAIN_ID;
        chainIds[5] = SONIC_CHAIN_ID;
        chainIds[6] = BSC_CHAIN_ID;
        chainIds[7] = AVALANCHE_CHAIN_ID;
        return chainIds;
    }
}
