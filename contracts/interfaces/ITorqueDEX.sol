// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.28;

interface ITorqueDEX {
    function depositLiquidity(address token, uint256 amount) external;
    function withdrawLiquidity(address token, uint256 amount) external;
    function openPosition(
        address user,
        address baseToken,
        address quoteToken,
        uint256 baseAmount,
        uint256 leverage
    ) external returns (uint256 positionId);
    function closePosition(uint256 positionId) external;
    function getPosition(uint256 positionId) external view returns (
        address user,
        address baseToken,
        address quoteToken,
        uint256 baseAmount,
        uint256 leverage,
        uint256 entryPrice,
        uint256 currentPrice
    );
    function swap(address tokenIn, uint256 amountIn, uint256 accountId) external returns (uint256 amountOut);
    function getPrice(address baseToken, address quoteToken) external view returns (uint256 price);
} 