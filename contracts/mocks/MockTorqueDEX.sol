// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/**
 * @title MockTorqueDEX
 * @dev Simplified mock implementation of TorqueDEX for testing
 */
contract MockTorqueDEX is Ownable {
    mapping(bytes32 => uint256) public poolLiquidity;
    mapping(uint16 => bool) public supportedChainIds;
    mapping(uint16 => address) public dexAddresses;
    
    // State variables for fee management
    address private _feeRecipient = address(0x123);
    uint256 private _feeBps = 10;

    // Events
    event LiquidityAdded(address indexed user, address baseToken, address quoteToken, uint256 amount0, uint256 amount1, uint256 liquidity);
    event LiquidityRemoved(address indexed user, address baseToken, address quoteToken, uint256 liquidity, uint256 amount0, uint256 amount1);
    event Swap(address indexed user, address baseToken, address quoteToken, address tokenIn, uint256 amountIn, uint256 amountOut);

    constructor() Ownable(msg.sender) {
        // Initialize supported chains
        supportedChainIds[1] = true;      // Ethereum
        supportedChainIds[42161] = true;  // Arbitrum
        supportedChainIds[10] = true;     // Optimism
        supportedChainIds[137] = true;    // Polygon
        supportedChainIds[8453] = true;   // Base
        supportedChainIds[146] = true;    // Sonic
        supportedChainIds[56] = true;     // BSC
        supportedChainIds[43114] = true;  // Avalanche
    }

    function swap(
        address baseToken,
        address quoteToken,
        address tokenIn,
        uint256 amountIn,
        uint256 minAmountOut
    ) external returns (uint256 amountOut) {
        amountOut = minAmountOut;
        emit Swap(msg.sender, baseToken, quoteToken, tokenIn, amountIn, amountOut);
        return amountOut;
    }

    function getPrice(address baseToken, address quoteToken) external pure returns (uint256 price) {
        require(baseToken != address(0), "Invalid base token");
        require(quoteToken != address(0), "Invalid quote token");
        // Additional validation: reject addresses that are not in a valid range
        require(baseToken > address(0x1000), "Invalid base token");
        require(quoteToken > address(0x1000), "Invalid quote token");
        return 1000000; // $1.00 with 6 decimals
    }

    function addLiquidity(
        address baseToken,
        address quoteToken,
        uint256 amount0,
        uint256 amount1,
        int256 lowerTick,
        int256 upperTick
    ) external returns (uint256 liquidity) {
        liquidity = amount0 + amount1;
        emit LiquidityAdded(msg.sender, baseToken, quoteToken, amount0, amount1, liquidity);
        return liquidity;
    }

    function removeLiquidity(
        address baseToken,
        address quoteToken,
        uint256 liquidity,
        uint256 rangeIndex
    ) external returns (uint256 amount0, uint256 amount1) {
        amount0 = liquidity / 2;
        amount1 = liquidity / 2;
        emit LiquidityRemoved(msg.sender, baseToken, quoteToken, liquidity, amount0, amount1);
        return (amount0, amount1);
    }

    // Simplified liquidity functions for testing
    function addLiquidity(
        uint256 amount0,
        uint256 amount1,
        int256 lowerTick,
        int256 upperTick
    ) external returns (uint256 liquidity) {
        liquidity = amount0 + amount1;
        emit LiquidityAdded(msg.sender, address(0), address(0), amount0, amount1, liquidity);
        return liquidity;
    }

    function removeLiquidity(uint256 liquidity) external returns (uint256 amount0, uint256 amount1) {
        amount0 = liquidity / 2;
        amount1 = liquidity / 2;
        emit LiquidityRemoved(msg.sender, address(0), address(0), liquidity, amount0, amount1);
        return (amount0, amount1);
    }

    function setDEXAddress(uint16 chainId, address dexAddress) external onlyOwner {
        require(supportedChainIds[chainId], "Unsupported chain");
        dexAddresses[chainId] = dexAddress;
    }

    function getDEXAddress(uint16 chainId) external view returns (address) {
        return dexAddresses[chainId];
    }

    function isSupportedChain(uint16 chainId) external view returns (bool) {
        return supportedChainIds[chainId];
    }

    function getCrossChainLiquidity(address user, uint16 chainId) external pure returns (uint256) {
        return 0; // Mock implementation
    }

    function getTotalCrossChainLiquidity(address user) external pure returns (uint256) {
        return 0; // Mock implementation
    }

    function getCrossChainLiquidityQuote(
        uint16[] calldata dstChainIds,
        bytes[] calldata adapterParams
    ) external pure returns (uint256 totalGasEstimate) {
        require(dstChainIds.length == adapterParams.length, "Array length mismatch");
        totalGasEstimate = dstChainIds.length * 50000; // Mock implementation
        return totalGasEstimate;
    }

    function emergencyWithdraw(address token, address to, uint256 amount) external onlyOwner {
        IERC20(token).transfer(to, amount);
    }

    function setFee(address baseToken, address quoteToken, uint256 newFeeBps) external onlyOwner {
        // Mock implementation - do nothing
    }

    function setFeeRecipient(address baseToken, address quoteToken, address newFeeRecipient) external onlyOwner {
        // Mock implementation - do nothing
    }

    // Simplified fee functions for testing
    function setFee(uint256 newFeeBps) external onlyOwner {
        require(newFeeBps <= 30, "Max 0.3%");
        _feeBps = newFeeBps;
    }

    function setFeeRecipient(address newFeeRecipient) external onlyOwner {
        require(newFeeRecipient != address(0), "Invalid fee recipient");
        _feeRecipient = newFeeRecipient;
    }

    function feeBps() external view returns (uint256) {
        return _feeBps;
    }

    function feeRecipient() external view returns (address) {
        return _feeRecipient;
    }

    function totalLiquidity() external view returns (uint256) {
        return 1000000; // Mock total liquidity (static for simplicity)
    }

    function lpToken() external pure returns (address) {
        return address(0x123); // Mock LP token address (non-zero for testing)
    }
} 