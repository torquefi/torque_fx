// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.30;

interface ITorqueDEX {
    function swap(
        address baseToken,
        address quoteToken,
        address tokenIn,
        uint256 amountIn,
        uint256 minAmountOut
    ) external returns (uint256 amountOut);
    
    function getPrice(address baseToken, address quoteToken) external view returns (uint256 price);
    
    function addLiquidity(
        address baseToken,
        address quoteToken,
        uint256 amount0,
        uint256 amount1,
        int256 lowerTick,
        int256 upperTick
    ) external returns (uint256 liquidity);
    
    function removeLiquidity(
        address baseToken,
        address quoteToken,
        uint256 liquidity,
        uint256 rangeIndex
    ) external returns (uint256 amount0, uint256 amount1);
} 