// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.28;

import "../TorqueGateway.sol";

interface ITorqueGateway {
    function getPaymentSession(bytes32 sessionId) external view returns (TorqueGateway.PaymentSession memory);
    function getMerchantConfig(address merchant) external view returns (TorqueGateway.GatewayConfig memory);
    function getMerchantBalance(address merchant) external view returns (uint256);
    function createPaymentSession(
        address customer,
        uint256 amount,
        address currency,
        string calldata redirectUrl,
        bytes calldata metadata
    ) external returns (bytes32 sessionId);
    function processPaymentSession(
        bytes32 sessionId,
        bytes calldata signature
    ) external;
    function withdrawBalance(uint256 amount) external;
} 