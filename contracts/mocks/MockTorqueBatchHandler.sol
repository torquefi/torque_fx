// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/**
 * @title MockTorqueBatchHandler
 * @dev Simplified mock version of TorqueBatchHandler for testing without LayerZero
 */
contract MockTorqueBatchHandler is Ownable, ReentrancyGuard {
    mapping(address => bool) public supportedCurrencies;
    mapping(uint16 => bool) public supportedChainIds;
    uint256 public maxBatchSize = 50;

    // Custom errors
    error TorqueBatchHandler__InvalidBatchSize();
    error TorqueBatchHandler__InvalidAmounts();
    error TorqueBatchHandler__UnsupportedCurrency();
    error TorqueBatchHandler__InvalidChainId();

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

    constructor(address _owner) Ownable(_owner) {
        // Initialize supported chain IDs
        supportedChainIds[1] = true;      // Ethereum
        supportedChainIds[42161] = true;  // Arbitrum
        supportedChainIds[10] = true;     // Optimism
        supportedChainIds[137] = true;    // Polygon
        supportedChainIds[8453] = true;   // Base
        supportedChainIds[146] = true;    // Sonic
        supportedChainIds[56] = true;     // BSC
        supportedChainIds[43114] = true;  // Avalanche
    }

    function addSupportedCurrency(address currency) external onlyOwner {
        supportedCurrencies[currency] = true;
    }

    function removeSupportedCurrency(address currency) external onlyOwner {
        supportedCurrencies[currency] = false;
    }

    function setMaxBatchSize(uint256 newMaxBatchSize) external onlyOwner {
        if (newMaxBatchSize == 0 || newMaxBatchSize > 100) {
            revert("Invalid batch size");
        }
        maxBatchSize = newMaxBatchSize;
    }

    function batchMint(
        address currency,
        uint256 totalCollateralAmount,
        uint16[] calldata dstChainIds,
        uint256[] calldata amountsPerChain,
        bytes[] calldata adapterParams
    ) external nonReentrant {
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

        // Mock implementation - just emit event
        emit BatchMintInitiated(msg.sender, currency, totalMintAmount, dstChainIds, amountsPerChain);
    }

    function batchBurn(
        address currency,
        uint256 totalBurnAmount,
        uint16[] calldata dstChainIds,
        uint256[] calldata amountsPerChain,
        bytes[] calldata adapterParams
    ) external nonReentrant {
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

        // Mock implementation - just emit event
        emit BatchBurnInitiated(msg.sender, currency, totalBurnAmount, dstChainIds, amountsPerChain);
    }

    function _nonblockingLzReceive(
        uint16 _srcChainId,
        bytes calldata _srcAddress,
        uint64 _nonce,
        bytes calldata _payload
    ) external {
        // Mock implementation - decode and emit events
        (address currency, address user, uint256 amount) = abi.decode(
            _payload,
            (address, address, uint256)
        );
        
        // Check if currency is supported to simulate failure
        if (supportedCurrencies[currency]) {
            // Mock success case
            emit BatchMintCompleted(user, currency, _srcChainId, amount);
        } else {
            // Mock failure case
            emit BatchMintFailed(user, currency, _srcChainId, amount, "Engine not configured");
        }
    }

    function getBatchMintQuote(
        uint16[] calldata dstChainIds,
        bytes[] calldata adapterParams
    ) external pure returns (uint256 totalGasEstimate) {
        // Mock implementation - return fixed gas estimate
        totalGasEstimate = dstChainIds.length * 50000; // 50k gas per chain
        return totalGasEstimate;
    }

    function emergencyWithdraw(
        address token,
        address to,
        uint256 amount
    ) external onlyOwner {
        IERC20(token).transfer(to, amount);
    }

    function getSupportedChainIds() external view returns (uint16[] memory) {
        uint16[] memory chainIds = new uint16[](8);
        chainIds[0] = 1;      // Ethereum
        chainIds[1] = 42161;  // Arbitrum
        chainIds[2] = 10;     // Optimism
        chainIds[3] = 137;    // Polygon
        chainIds[4] = 8453;   // Base
        chainIds[5] = 146;    // Sonic
        chainIds[6] = 56;     // BSC
        chainIds[7] = 43114;  // Avalanche
        return chainIds;
    }
} 