// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.28;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/Pausable.sol";
import "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import "./TorquePayments.sol";
import "./interfaces/ITorquePayments.sol";
import "./interfaces/ITorqueAccount.sol";

contract TorqueGateway is Ownable, ReentrancyGuard, Pausable {
    using ECDSA for bytes32;

    struct GatewayConfig {
        uint256 minAmount;
        uint256 maxAmount;
        uint256 defaultFee;
        bool allowCrossChain;
        bool requireAccountVerification;
        uint256 paymentTimeout;
    }

    struct PaymentSession {
        bytes32 sessionId;
        address merchant;
        address customer;
        uint256 amount;
        address currency;
        uint256 expiresAt;
        bool completed;
        bytes32 paymentId;
        string redirectUrl;
    }

    struct WebhookConfig {
        string url;
        bytes32 secret;
        bool enabled;
    }

    ITorquePayments public immutable paymentsContract;
    ITorqueAccount public immutable accountContract;
    IERC20 public immutable usdc;

    mapping(address => GatewayConfig) public merchantConfigs;
    mapping(bytes32 => PaymentSession) public paymentSessions;
    mapping(address => WebhookConfig) public webhookConfigs;
    mapping(address => uint256) public merchantBalances;
    mapping(address => uint256) public sessionCounts;
    mapping(bytes32 => bool) public usedNonces;

    uint256 public constant SESSION_TIMEOUT = 30 minutes;
    uint256 public constant MAX_REDIRECT_URL_LENGTH = 256;
    uint256 public constant DEFAULT_GATEWAY_FEE = 10; // 0.1%
    uint256 public constant BASIS_POINTS = 10000;

    event PaymentSessionCreated(
        bytes32 indexed sessionId,
        address indexed merchant,
        address indexed customer,
        uint256 amount,
        string redirectUrl
    );
    event PaymentSessionCompleted(
        bytes32 indexed sessionId,
        bytes32 indexed paymentId,
        address indexed customer,
        uint256 amount
    );
    event PaymentSessionExpired(
        bytes32 indexed sessionId,
        address indexed merchant
    );
    event WebhookTriggered(
        bytes32 indexed sessionId,
        address indexed merchant,
        string url,
        bool success
    );
    event MerchantConfigUpdated(
        address indexed merchant,
        uint256 minAmount,
        uint256 fee
    );

    constructor(address _paymentsContract, address _accountContract, address _usdc) Ownable(msg.sender) {
        paymentsContract = ITorquePayments(_paymentsContract);
        accountContract = ITorqueAccount(_accountContract);
        usdc = IERC20(_usdc);
    }

    /**
     * @dev Create a payment session for a customer
     */
    function createPaymentSession(
        address customer,
        uint256 amount,
        address currency,
        string calldata redirectUrl,
        bytes calldata metadata
    ) external nonReentrant returns (bytes32 sessionId) {
        GatewayConfig storage config = merchantConfigs[msg.sender];
        require(config.minAmount > 0, "Merchant not configured");
        require(amount >= config.minAmount, "Amount below minimum");
        require(bytes(redirectUrl).length <= MAX_REDIRECT_URL_LENGTH, "URL too long");

        sessionId = keccak256(abi.encodePacked(
            msg.sender,
            customer,
            amount,
            currency,
            sessionCounts[msg.sender]++,
            block.timestamp
        ));

        paymentSessions[sessionId] = PaymentSession({
            sessionId: sessionId,
            merchant: msg.sender,
            customer: customer,
            amount: amount,
            currency: currency,
            expiresAt: block.timestamp + SESSION_TIMEOUT,
            completed: false,
            paymentId: bytes32(0),
            redirectUrl: redirectUrl
        });

        emit PaymentSessionCreated(sessionId, msg.sender, customer, amount, redirectUrl);
    }

    /**
     * @dev Process a payment session
     */
    function processPaymentSession(
        bytes32 sessionId,
        uint256 accountId,
        bytes calldata signature
    ) external nonReentrant {
        PaymentSession storage session = paymentSessions[sessionId];
        require(session.customer == msg.sender, "Not session customer");
        require(!session.completed, "Session already completed");
        require(block.timestamp <= session.expiresAt, "Session expired");

        // Verify signature for payment authorization
        bytes32 messageHash = keccak256(abi.encodePacked(
            sessionId,
            session.amount,
            session.currency,
            session.merchant,
            msg.sender
        ));
        bytes32 ethSignedMessageHash = messageHash.toEthSignedMessageHash();
        address signer = ethSignedMessageHash.recover(signature);
        require(signer == session.customer, "Invalid signature");

        // Verify account if required (optional for merchants)
        if (merchantConfigs[session.merchant].requireAccountVerification) {
            require(accountId > 0, "Account ID required");
            require(accountContract.isValidAccount(msg.sender, accountId), "Invalid account");
            // Additional account verification can be added here
            // e.g., check account age, transaction history, etc.
        }
        // If no account verification required, any address can pay (accountId can be 0)

        // Create payment request
        TorquePayments.PaymentRequest memory request = TorquePayments.PaymentRequest({
            payee: session.merchant,
            amount: session.amount,
            currency: session.currency,
            settlementCurrency: session.currency,
            paymentType: TorquePayments.PaymentType.CRYPTO_TO_CRYPTO,
            settlementMethod: TorquePayments.SettlementMethod.INSTANT,
            expiresAt: block.timestamp + SESSION_TIMEOUT,
            description: "Gateway payment",
            metadata: ""
        });

        // Create and process payment (use accountId 0 if not required)
        uint256 paymentAccountId = merchantConfigs[session.merchant].requireAccountVerification ? accountId : 0;
        bytes32 paymentId = paymentsContract.createPayment(request, paymentAccountId);
        paymentsContract.processPayment(paymentId, paymentAccountId);

        // Update session
        session.completed = true;
        session.paymentId = paymentId;

        // Update merchant balance - no fees
        merchantBalances[session.merchant] += session.amount;

        emit PaymentSessionCompleted(sessionId, paymentId, msg.sender, session.amount);

        // Trigger webhook if configured
        _triggerWebhook(session);
    }



    /**
     * @dev Withdraw merchant balance
     */
    function withdrawBalance(uint256 amount) external nonReentrant {
        require(merchantBalances[msg.sender] >= amount, "Insufficient balance");
        
        merchantBalances[msg.sender] -= amount;
        usdc.transfer(msg.sender, amount);
    }

    /**
     * @dev Set merchant configuration
     */
    function setMerchantConfig(
        uint256 minAmount,
        uint256 fee,
        bool allowCrossChain,
        bool requireAccountVerification
    ) external {
        require(minAmount >= 1000, "Min amount too low"); // At least 0.001 USDC
        require(fee <= 500, "Fee too high"); // Max 5%

        merchantConfigs[msg.sender] = GatewayConfig({
            minAmount: minAmount,
            maxAmount: type(uint256).max, // No maximum limit
            defaultFee: fee,
            allowCrossChain: allowCrossChain,
            requireAccountVerification: requireAccountVerification,
            paymentTimeout: SESSION_TIMEOUT
        });

        emit MerchantConfigUpdated(msg.sender, minAmount, fee);
    }

    /**
     * @dev Set webhook configuration
     */
    function setWebhookConfig(
        string calldata url,
        bytes32 secret
    ) external {
        webhookConfigs[msg.sender] = WebhookConfig({
            url: url,
            secret: secret,
            enabled: true
        });
    }

    /**
     * @dev Clean up expired sessions
     */
    function cleanupExpiredSessions(bytes32[] calldata sessionIds) external {
        for (uint256 i = 0; i < sessionIds.length; i++) {
            PaymentSession storage session = paymentSessions[sessionIds[i]];
            if (session.merchant == msg.sender && 
                !session.completed && 
                block.timestamp > session.expiresAt) {
                
                session.completed = true;
                emit PaymentSessionExpired(sessionIds[i], msg.sender);
            }
        }
    }

    /**
     * @dev Get payment session details
     */
    function getPaymentSession(bytes32 sessionId) external view returns (PaymentSession memory) {
        return paymentSessions[sessionId];
    }

    /**
     * @dev Get merchant configuration
     */
    function getMerchantConfig(address merchant) external view returns (GatewayConfig memory) {
        return merchantConfigs[merchant];
    }

    /**
     * @dev Get merchant balance
     */
    function getMerchantBalance(address merchant) external view returns (uint256) {
        return merchantBalances[merchant];
    }

    /**
     * @dev Check if session is valid
     */
    function isSessionValid(bytes32 sessionId) external view returns (bool) {
        PaymentSession storage session = paymentSessions[sessionId];
        return session.customer != address(0) && 
               !session.completed && 
               block.timestamp <= session.expiresAt;
    }

    /**
     * @dev Trigger webhook for payment completion
     */
    function _triggerWebhook(PaymentSession storage session) internal {
        WebhookConfig storage webhook = webhookConfigs[session.merchant];
        if (!webhook.enabled) return;

        // In production, this would make an HTTP call to the webhook URL
        // For now, we'll just emit an event that can be picked up by off-chain services
        emit WebhookTriggered(session.sessionId, session.merchant, webhook.url, true);
    }



    /**
     * @dev Emergency pause
     */
    function pause() external onlyOwner {
        _pause();
    }

    /**
     * @dev Emergency unpause
     */
    function unpause() external onlyOwner {
        _unpause();
    }
} 