// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.28;

import "../TorquePayments.sol";

interface ITorquePayments {
    // Core payment functions
    function createPayment(
        TorquePayments.PaymentRequest calldata request
    ) external returns (bytes32 paymentId);
    
    function processPayment(
        bytes32 paymentId
    ) external;
    
    // View functions
    function getPayment(bytes32 paymentId) external view returns (TorquePayments.Payment memory);
    function getSubscription(bytes32 subscriptionId) external view returns (TorquePayments.Subscription memory);
    function getInvoice(bytes32 invoiceId) external view returns (TorquePayments.Invoice memory);
    function getUserPayments(address user) external view returns (bytes32[] memory);
    function getMerchantPayments(address merchant) external view returns (bytes32[] memory);
} 