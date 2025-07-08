// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.28;

interface ITorqueAccount {
    function userAccounts(address user, uint256 accountId) external view returns (
        uint256 leverage,
        bool exists,
        bool active,
        string memory username,
        address referrer
    );
    function isValidAccount(address user, uint256 accountId) external view returns (bool);
    function getLeverage(address user, uint256 accountId) external view returns (uint256);
    function accountCount(address user) external view returns (uint256);
    function createAccount(uint256 leverage, string calldata username, address referrer) external returns (uint256 accountId);
    function updateAccount(uint256 accountId, uint256 leverage) external;
    function disableAccount(uint256 accountId) external;
    function depositETH(uint256 accountId) external payable;
    function depositUSDC(uint256 accountId, uint256 amount) external;
    function withdrawETH(uint256 accountId, uint256 amount) external;
    function withdrawUSDC(uint256 accountId, uint256 amount) external;
    function ethBalances(address user, uint256 accountId) external view returns (uint256);
    function usdcBalances(address user, uint256 accountId) external view returns (uint256);
    function openPosition(
        uint256 accountId,
        uint256 positionId,
        address baseToken,
        address quoteToken,
        uint256 collateral,
        uint256 positionSize,
        uint256 entryPrice,
        bool isLong
    ) external;
    function closePosition(
        uint256 accountId,
        uint256 positionId,
        int256 pnl
    ) external;
} 