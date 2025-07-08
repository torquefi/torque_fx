// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.28;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import "@openzeppelin/contracts/utils/Pausable.sol";
import "@layerzerolabs/lz-evm-oapp-v2/contracts/oapp/OApp.sol";
import "./interfaces/ITorqueAccount.sol";

contract TorquePayments is Ownable, ReentrancyGuard, Pausable, OApp {
    using ECDSA for bytes32;

    enum PaymentStatus { PENDING, PROCESSING, COMPLETED, FAILED, CANCELLED, REFUNDED }
    enum PaymentType { CRYPTO_TO_CRYPTO, SUBSCRIPTION, INVOICE, DONATION, BUY_NOW_PAY_LATER, MASS_PAYMENT }
    enum SettlementMethod { INSTANT, BATCH, ESCROW }
    enum DonationType { CHARITY, CREATOR, PROJECT, CAUSE, GENERAL }
    enum BNPLStatus { AUTHORIZED, ACTIVE, PAID, DEFAULTED, CANCELLED }
    enum BNPLSchedule { WEEKLY, BIWEEKLY, MONTHLY, CUSTOM }
    enum MassPaymentStatus { PENDING, PROCESSING, COMPLETED, FAILED, CANCELLED, PARTIAL }
    enum RecipientType { CONTRACTOR, FREELANCER, SELLER, CLAIMANT, EMPLOYEE, GENERAL }

    struct Payment {
        bytes32 paymentId;
        address payer;
        address payee;
        uint256 amount;
        address currency;
        address settlementCurrency; // Currency merchant receives
        PaymentType paymentType;
        PaymentStatus status;
        SettlementMethod settlementMethod;
        uint256 createdAt;
        uint256 processedAt;
        uint256 expiresAt;
        string description;
        bytes metadata;
        bool isCrossChain;
        uint16 dstChainId;
        address dstAddress;
    }

    struct PaymentRequest {
        address payee;
        uint256 amount;
        address currency;
        address settlementCurrency; // Currency merchant wants to receive
        PaymentType paymentType;
        SettlementMethod settlementMethod;
        uint256 expiresAt;
        string description;
        bytes metadata;
    }

    struct CrossChainPayment {
        bytes32 paymentId;
        address payer;
        address payee;
        uint256 amount;
        address currency;
        uint16 srcChainId;
        uint16 dstChainId;
        address srcAddress;
        address dstAddress;
        uint256 nonce;
    }

    struct Subscription {
        bytes32 subscriptionId;
        address subscriber;
        address merchant;
        uint256 amount;
        address currency;
        uint256 interval; // in seconds
        uint256 nextBillingDate;
        bool active;
        uint256 maxBillingCycles;
        uint256 currentBillingCycle;
        string description;
    }

    struct Invoice {
        bytes32 invoiceId;
        address payer;
        address payee;
        uint256 amount;
        address currency;
        uint256 dueDate;
        bool paid;
        string description;
        bytes32[] lineItems;
    }

    struct Donation {
        bytes32 donationId;
        address donor;
        address recipient;
        uint256 amount;
        address currency;
        DonationType donationType;
        PaymentStatus status;
        uint256 createdAt;
        uint256 processedAt;
        string message;
        string cause;
        bool isAnonymous;
        bytes metadata;
        bool isCrossChain;
        uint16 dstChainId;
        address dstAddress;
    }

    struct DonationRequest {
        address recipient;
        uint256 amount;
        address currency;
        DonationType donationType;
        string message;
        string cause;
        bool isAnonymous;
        uint256 expiresAt;
        bytes metadata;
    }

    struct BNPLAgreement {
        bytes32 bnplId;
        address buyer;
        address merchant;
        uint256 totalAmount;
        uint256 downPayment;
        uint256 financedAmount;
        address currency;
        BNPLStatus status;
        BNPLSchedule schedule;
        uint256 installmentAmount;
        uint256 installmentCount;
        uint256 currentInstallment;
        uint256 nextPaymentDate;
        uint256 createdAt;
        uint256 activatedAt;
        uint256 completedAt;
        uint256 lateFees;
        uint256 defaultThreshold; // Days after which account is defaulted
        string description;
        bytes metadata;
    }

    struct BNPLRequest {
        address merchant;
        uint256 totalAmount;
        uint256 downPayment;
        address currency;
        BNPLSchedule schedule;
        uint256 installmentCount;
        uint256 defaultThreshold;
        uint256 expiresAt;
        string description;
        bytes metadata;
    }

    struct Installment {
        uint256 installmentNumber;
        uint256 amount;
        uint256 dueDate;
        bool paid;
        uint256 paidAt;
        uint256 lateFees;
    }

    struct MassPayment {
        bytes32 massPaymentId;
        address payer;
        address currency;
        uint256 totalAmount;
        uint256 processedAmount;
        uint256 recipientCount;
        uint256 processedCount;
        uint256 failedCount;
        MassPaymentStatus status;
        uint256 createdAt;
        uint256 processedAt;
        uint256 completedAt;
        string description;
        bytes metadata;
        bool isCrossChain;
        uint16 dstChainId;
        address dstAddress;
    }

    struct MassPaymentRequest {
        address currency;
        uint256 totalAmount;
        uint256 expiresAt;
        string description;
        bytes metadata;
    }

    struct MassPaymentRecipient {
        address recipient;
        uint256 amount;
        RecipientType recipientType;
        string description;
        bytes metadata;
        bool processed;
        uint256 processedAt;
        string failureReason;
    }

    struct MassPaymentBatch {
        bytes32 batchId;
        bytes32 massPaymentId;
        uint256 startIndex;
        uint256 endIndex;
        uint256 batchAmount;
        uint256 processedCount;
        uint256 failedCount;
        bool completed;
        uint256 completedAt;
    }

    ITorqueAccount public immutable accountContract;
    IERC20 public immutable usdc;
    
    // Supported Torque currencies for payments
    mapping(address => bool) public supportedTorqueCurrencies;
    mapping(address => address) public merchantSettlementPreferences; // merchant => preferred Torque currency
    
    mapping(bytes32 => Payment) public payments;
    mapping(bytes32 => Subscription) public subscriptions;
    mapping(bytes32 => Invoice) public invoices;
    mapping(bytes32 => Donation) public donations;
    mapping(bytes32 => BNPLAgreement) public bnplAgreements;
    mapping(bytes32 => mapping(uint256 => Installment)) public installments;
    mapping(bytes32 => MassPayment) public massPayments;
    mapping(bytes32 => MassPaymentRecipient[]) public massPaymentRecipients;
    mapping(bytes32 => MassPaymentBatch[]) public massPaymentBatches;
    mapping(address => bytes32[]) public userPayments;
    mapping(address => bytes32[]) public merchantPayments;
    mapping(address => bytes32[]) public userDonations;
    mapping(address => bytes32[]) public recipientDonations;
    mapping(address => bytes32[]) public userBNPLAgreements;
    mapping(address => bytes32[]) public merchantBNPLAgreements;
    mapping(address => bytes32[]) public userMassPayments;
    mapping(address => bytes32[]) public recipientMassPayments;
    mapping(address => bool) public authorizedMerchants;
    mapping(address => bool) public authorizedRecipients; // For donations
    mapping(address => bool) public bnplEnabledMerchants; // Merchants that support BNPL
    mapping(address => bool) public massPaymentEnabled; // Users enabled for mass payments
    mapping(bytes32 => bool) public processedCrossChainPayments;
    mapping(address => uint256) public nonces;

    uint256 public constant PAYMENT_EXPIRY = 24 hours;
    uint256 public constant MIN_PAYMENT_AMOUNT = 1000; // 0.001 TUSD (1000 wei)
    uint256 public constant DEFAULT_MERCHANT_FEE = 0; // No fees
    uint256 public constant BASIS_POINTS = 10000;
    uint256 public constant MAX_METADATA_SIZE = 1024;
    
    // BNPL Constants
    uint256 public constant MIN_BNPL_AMOUNT = 10000; // 0.01 TUSD minimum for BNPL
    uint256 public constant MAX_BNPL_AMOUNT = 1000000000; // 1000 TUSD maximum for BNPL
    uint256 public constant MIN_DOWN_PAYMENT_PERCENT = 10; // 10% minimum down payment
    uint256 public constant MAX_INSTALLMENT_COUNT = 12; // Maximum 12 installments
    uint256 public constant LATE_FEE_RATE = 50; // 0.5% late fee per day
    uint256 public constant DEFAULT_THRESHOLD_DAYS = 30; // 30 days default threshold
    
    // Mass Payment Constants
    uint256 public constant MAX_MASS_PAYMENT_RECIPIENTS = 1000; // Maximum recipients per mass payment
    uint256 public constant MIN_MASS_PAYMENT_AMOUNT = 1000; // 0.001 TUSD minimum per recipient
    uint256 public constant MAX_MASS_PAYMENT_AMOUNT = 1000000000000; // 1M TUSD maximum per mass payment
    uint256 public constant MASS_PAYMENT_BATCH_SIZE = 50; // Process 50 recipients per batch
    uint256 public constant MASS_PAYMENT_GAS_LIMIT = 500000; // Gas limit per batch

    event PaymentCreated(
        bytes32 indexed paymentId,
        address indexed payer,
        address indexed payee,
        uint256 amount,
        address currency,
        PaymentType paymentType
    );
    event PaymentProcessed(
        bytes32 indexed paymentId,
        address indexed payer,
        address indexed payee,
        uint256 amount,
        uint256 fee
    );
    event PaymentFailed(
        bytes32 indexed paymentId,
        address indexed payer,
        string reason
    );
    event PaymentRefunded(
        bytes32 indexed paymentId,
        address indexed payer,
        address indexed payee,
        uint256 amount
    );
    event SubscriptionCreated(
        bytes32 indexed subscriptionId,
        address indexed subscriber,
        address indexed merchant,
        uint256 amount,
        uint256 interval
    );
    event SubscriptionBilled(
        bytes32 indexed subscriptionId,
        address indexed subscriber,
        uint256 amount,
        uint256 billingCycle
    );
    event InvoiceCreated(
        bytes32 indexed invoiceId,
        address indexed payer,
        address indexed payee,
        uint256 amount
    );
    event InvoicePaid(
        bytes32 indexed invoiceId,
        address indexed payer,
        uint256 amount
    );
    event MerchantAuthorized(address indexed merchant, bool authorized);

    event CrossChainPaymentInitiated(
        bytes32 indexed paymentId,
        address indexed payer,
        uint16 dstChainId,
        uint256 amount
    );
    event CrossChainPaymentCompleted(
        bytes32 indexed paymentId,
        address indexed payee,
        uint16 srcChainId,
        uint256 amount
    );
    
    event TorqueCurrencyAdded(address indexed currency, bool supported);
    event MerchantSettlementPreferenceUpdated(address indexed merchant, address indexed currency);
    
    event BNPLAgreementCreated(
        bytes32 indexed bnplId,
        address indexed buyer,
        address indexed merchant,
        uint256 totalAmount,
        uint256 downPayment,
        uint256 installmentCount
    );
    event BNPLAgreementActivated(
        bytes32 indexed bnplId,
        address indexed buyer,
        uint256 activatedAt
    );
    event InstallmentPaid(
        bytes32 indexed bnplId,
        address indexed buyer,
        uint256 installmentNumber,
        uint256 amount,
        uint256 lateFees
    );
    event BNPLAgreementCompleted(
        bytes32 indexed bnplId,
        address indexed buyer,
        uint256 completedAt
    );
    event BNPLAgreementDefaulted(
        bytes32 indexed bnplId,
        address indexed buyer,
        uint256 defaultedAt
    );
    event BNPLMerchantEnabled(address indexed merchant, bool enabled);
    
    event MassPaymentCreated(
        bytes32 indexed massPaymentId,
        address indexed payer,
        address indexed currency,
        uint256 totalAmount,
        uint256 recipientCount
    );
    event MassPaymentRecipientAdded(
        bytes32 indexed massPaymentId,
        address indexed recipient,
        uint256 amount,
        RecipientType recipientType
    );
    event MassPaymentBatchProcessed(
        bytes32 indexed massPaymentId,
        bytes32 indexed batchId,
        uint256 processedCount,
        uint256 failedCount,
        uint256 batchAmount
    );
    event MassPaymentCompleted(
        bytes32 indexed massPaymentId,
        address indexed payer,
        uint256 totalProcessed,
        uint256 totalFailed,
        uint256 completedAt
    );
    event MassPaymentFailed(
        bytes32 indexed massPaymentId,
        address indexed payer,
        string reason
    );
    event MassPaymentEnabled(address indexed user, bool enabled);
    
    event DonationCreated(
        bytes32 indexed donationId,
        address indexed donor,
        address indexed recipient,
        uint256 amount,
        address currency,
        DonationType donationType,
        bool isAnonymous
    );
    event DonationProcessed(
        bytes32 indexed donationId,
        address indexed donor,
        address indexed recipient,
        uint256 amount,
        string message
    );
    event DonationFailed(
        bytes32 indexed donationId,
        address indexed donor,
        string reason
    );
    event RecipientAuthorized(address indexed recipient, bool authorized);

    modifier onlyAuthorizedMerchant() {
        require(authorizedMerchants[msg.sender], "Not authorized merchant");
        _;
    }

    modifier onlyAuthorizedRecipient() {
        require(authorizedRecipients[msg.sender], "Not authorized recipient");
        _;
    }

    modifier onlyBNPLEnabledMerchant() {
        require(bnplEnabledMerchants[msg.sender], "BNPL not enabled for merchant");
        _;
    }

    modifier onlyMassPaymentEnabled() {
        require(massPaymentEnabled[msg.sender], "Mass payments not enabled");
        _;
    }

    /**
     * @dev Check if currency is a supported Torque currency
     */
    function isTorqueCurrency(address currency) public view returns (bool) {
        return supportedTorqueCurrencies[currency];
    }

    modifier whenPaymentNotExpired(bytes32 paymentId) {
        require(payments[paymentId].expiresAt > block.timestamp, "Payment expired");
        _;
    }

    constructor(
        address _accountContract,
        address _usdc,
        address _lzEndpoint
    ) OApp(_lzEndpoint, msg.sender) Ownable(msg.sender) {
        accountContract = ITorqueAccount(_accountContract);
        usdc = IERC20(_usdc);
        
        // Initialize supported stablecoins
        supportedTorqueCurrencies[_usdc] = true; // TUSD is always supported
    }

    /**
     * @dev Create a new payment request
     */
    function createPayment(
        PaymentRequest calldata request,
        uint256 accountId
    ) external nonReentrant whenNotPaused returns (bytes32 paymentId) {
        // Account verification is optional - if accountId is 0, skip validation
        if (accountId > 0) {
            require(accountContract.isValidAccount(msg.sender, accountId), "Invalid account");
        }
        require(request.amount >= MIN_PAYMENT_AMOUNT, "Amount too small");
        require(request.expiresAt > block.timestamp, "Invalid expiry");
        require(bytes(request.description).length <= MAX_METADATA_SIZE, "Description too long");
        require(authorizedMerchants[request.payee], "Payee not authorized");

        paymentId = keccak256(abi.encodePacked(
            msg.sender,
            request.payee,
            request.amount,
            request.currency,
            nonces[msg.sender]++,
            block.timestamp
        ));

        // Use merchant's preferred settlement currency if not specified
        address settlementCurrency = request.settlementCurrency;
        if (settlementCurrency == address(0)) {
            settlementCurrency = merchantSettlementPreferences[request.payee];
            if (settlementCurrency == address(0)) {
                settlementCurrency = address(usdc); // Default to USDC
            }
        }
        
        payments[paymentId] = Payment({
            paymentId: paymentId,
            payer: msg.sender,
            payee: request.payee,
            amount: request.amount,
            currency: request.currency,
            settlementCurrency: settlementCurrency,
            paymentType: request.paymentType,
            status: PaymentStatus.PENDING,
            settlementMethod: request.settlementMethod,
            createdAt: block.timestamp,
            processedAt: 0,
            expiresAt: request.expiresAt,
            description: request.description,
            metadata: request.metadata,
            isCrossChain: false,
            dstChainId: 0,
            dstAddress: address(0)
        });

        userPayments[msg.sender].push(paymentId);
        merchantPayments[request.payee].push(paymentId);

        emit PaymentCreated(
            paymentId,
            msg.sender,
            request.payee,
            request.amount,
            request.currency,
            request.paymentType
        );
    }

    /**
     * @dev Process a payment with currency conversion
     */
    function processPayment(
        bytes32 paymentId,
        uint256 accountId
    ) external nonReentrant whenNotPaused whenPaymentNotExpired(paymentId) {
        Payment storage payment = payments[paymentId];
        require(payment.payer == msg.sender, "Not payment owner");
        require(payment.status == PaymentStatus.PENDING, "Payment not pending");
        require(isTorqueCurrency(payment.currency), "Only Torque currencies supported");
        require(isTorqueCurrency(payment.settlementCurrency), "Only Torque currencies supported for settlement");
        
        // Account verification is optional - if accountId is 0, skip validation
        if (accountId > 0) {
            require(accountContract.isValidAccount(msg.sender, accountId), "Invalid account");
        }

        // Check if user has sufficient balance in the payment currency
        IERC20 paymentToken = IERC20(payment.currency);
        if (accountId > 0) {
            // Use TorqueAccount balance - would need to check specific currency balance
            require(paymentToken.balanceOf(msg.sender) >= payment.amount, "Insufficient balance");
        } else {
            // Use direct balance
            require(paymentToken.balanceOf(msg.sender) >= payment.amount, "Insufficient balance");
        }

        // No fees - full amount goes to merchant
        uint256 merchantFee = 0;
        uint256 netAmount = payment.amount;

        // Update payment status
        payment.status = PaymentStatus.PROCESSING;
        payment.processedAt = block.timestamp;

        // Transfer funds from user
        if (accountId > 0) {
            // Use TorqueAccount - would need currency-specific withdrawal
            paymentToken.transferFrom(msg.sender, address(this), payment.amount);
        } else {
            // Direct transfer from user
            paymentToken.transferFrom(msg.sender, address(this), payment.amount);
        }
        
        if (payment.isCrossChain) {
            // Handle cross-chain payment
            _initiateCrossChainPayment(payment, accountId);
        } else {
            // Local payment processing with currency conversion
            _processLocalPayment(payment, netAmount, merchantFee);
        }
    }
    
    /**
     * @dev Process local payment with currency conversion
     */
    function _processLocalPayment(
        Payment storage payment,
        uint256 amount,
        uint256 fee
    ) internal {
        IERC20 paymentToken = IERC20(payment.currency);
        IERC20 settlementToken = IERC20(payment.settlementCurrency);
        
        if (payment.currency == payment.settlementCurrency) {
            // Same currency - direct transfer
            settlementToken.transfer(payment.payee, amount);
        } else {
            // Different currencies - would need DEX integration for conversion
            // For now, we'll transfer the original currency and let merchant handle conversion
            paymentToken.transfer(payment.payee, amount);
        }
        
        payment.status = PaymentStatus.COMPLETED;
        emit PaymentProcessed(payment.paymentId, payment.payer, payment.payee, amount, fee);
    }

    /**
     * @dev Create a subscription
     */
    function createSubscription(
        address merchant,
        uint256 amount,
        address currency,
        uint256 interval,
        uint256 maxBillingCycles,
        string calldata description,
        uint256 accountId
    ) external nonReentrant whenNotPaused returns (bytes32 subscriptionId) {
        // Account verification is optional - if accountId is 0, skip validation
        if (accountId > 0) {
            require(accountContract.isValidAccount(msg.sender, accountId), "Invalid account");
        }
        require(authorizedMerchants[merchant], "Merchant not authorized");
        require(interval >= 1 days, "Interval too short");
        require(maxBillingCycles > 0, "Invalid billing cycles");

        subscriptionId = keccak256(abi.encodePacked(
            msg.sender,
            merchant,
            amount,
            interval,
            nonces[msg.sender]++,
            block.timestamp
        ));

        subscriptions[subscriptionId] = Subscription({
            subscriptionId: subscriptionId,
            subscriber: msg.sender,
            merchant: merchant,
            amount: amount,
            currency: currency,
            interval: interval,
            nextBillingDate: block.timestamp + interval,
            active: true,
            maxBillingCycles: maxBillingCycles,
            currentBillingCycle: 0,
            description: description
        });

        emit SubscriptionCreated(subscriptionId, msg.sender, merchant, amount, interval);
    }

    /**
     * @dev Process subscription billing
     */
    function processSubscriptionBilling(
        bytes32 subscriptionId,
        uint256 accountId
    ) external nonReentrant whenNotPaused {
        Subscription storage subscription = subscriptions[subscriptionId];
        require(subscription.active, "Subscription not active");
        require(block.timestamp >= subscription.nextBillingDate, "Not time to bill");
        require(subscription.currentBillingCycle < subscription.maxBillingCycles, "Max cycles reached");
        // Account verification is optional - if accountId is 0, skip validation
        if (accountId > 0) {
            require(accountContract.isValidAccount(subscription.subscriber, accountId), "Invalid account");
        }

        // Check balance
        if (accountId > 0) {
            // Use TorqueAccount balance
            require(usdc.balanceOf(address(accountContract)) >= subscription.amount, "Insufficient balance");
        } else {
            // Use direct USDC balance
            require(usdc.balanceOf(subscription.subscriber) >= subscription.amount, "Insufficient balance");
        }

        // No fees - full amount goes to merchant
        uint256 merchantFee = 0;
        uint256 netAmount = subscription.amount;

        // Process payment
        if (accountId > 0) {
            // Use TorqueAccount
            accountContract.withdrawUSDC(accountId, subscription.amount);
        } else {
            // Direct transfer from subscriber
            usdc.transferFrom(subscription.subscriber, address(this), subscription.amount);
        }
        usdc.transfer(subscription.merchant, netAmount);

        // Update subscription
        subscription.currentBillingCycle++;
        subscription.nextBillingDate += subscription.interval;
        
        if (subscription.currentBillingCycle >= subscription.maxBillingCycles) {
            subscription.active = false;
        }

        emit SubscriptionBilled(
            subscriptionId,
            subscription.subscriber,
            netAmount,
            subscription.currentBillingCycle
        );
    }

    /**
     * @dev Create an invoice
     */
    function createInvoice(
        address payer,
        uint256 amount,
        address currency,
        uint256 dueDate,
        string calldata description,
        bytes32[] calldata lineItems
    ) external onlyAuthorizedMerchant nonReentrant whenNotPaused returns (bytes32 invoiceId) {
        require(dueDate > block.timestamp, "Invalid due date");
        require(amount >= MIN_PAYMENT_AMOUNT, "Amount too small");

        invoiceId = keccak256(abi.encodePacked(
            msg.sender,
            payer,
            amount,
            dueDate,
            nonces[msg.sender]++,
            block.timestamp
        ));

        invoices[invoiceId] = Invoice({
            invoiceId: invoiceId,
            payer: payer,
            payee: msg.sender,
            amount: amount,
            currency: currency,
            dueDate: dueDate,
            paid: false,
            description: description,
            lineItems: lineItems
        });

        emit InvoiceCreated(invoiceId, payer, msg.sender, amount);
    }

    /**
     * @dev Pay an invoice
     */
    function payInvoice(
        bytes32 invoiceId,
        uint256 accountId
    ) external nonReentrant whenNotPaused {
        Invoice storage invoice = invoices[invoiceId];
        require(invoice.payer == msg.sender, "Not invoice payer");
        require(!invoice.paid, "Invoice already paid");
        require(block.timestamp <= invoice.dueDate, "Invoice overdue");
        // Account verification is optional - if accountId is 0, skip validation
        if (accountId > 0) {
            require(accountContract.isValidAccount(msg.sender, accountId), "Invalid account");
        }

        // Check balance
        if (accountId > 0) {
            // Use TorqueAccount balance
            require(usdc.balanceOf(address(accountContract)) >= invoice.amount, "Insufficient balance");
        } else {
            // Use direct USDC balance
            require(usdc.balanceOf(msg.sender) >= invoice.amount, "Insufficient balance");
        }

        // No fees - full amount goes to merchant
        uint256 merchantFee = 0;
        uint256 netAmount = invoice.amount;

        // Process payment
        if (accountId > 0) {
            // Use TorqueAccount
            accountContract.withdrawUSDC(accountId, invoice.amount);
        } else {
            // Direct transfer from payer
            usdc.transferFrom(msg.sender, address(this), invoice.amount);
        }
        usdc.transfer(invoice.payee, netAmount);

        invoice.paid = true;

        emit InvoicePaid(invoiceId, msg.sender, netAmount);
    }

    /**
     * @dev Initiate cross-chain payment
     */
    function _initiateCrossChainPayment(
        Payment storage payment,
        uint256 accountId
    ) internal {
        CrossChainPayment memory crossChainPayment = CrossChainPayment({
            paymentId: payment.paymentId,
            payer: payment.payer,
            payee: payment.payee,
            amount: payment.amount,
            currency: payment.currency,
            srcChainId: uint16(block.chainid),
            dstChainId: payment.dstChainId,
            srcAddress: address(this),
            dstAddress: payment.dstAddress,
            nonce: nonces[payment.payer]++
        });

        bytes memory payload = abi.encode(crossChainPayment);
        
        // Send cross-chain message
        MessagingFee memory fee = _quote(payment.dstChainId, payload, "", false);
        _lzSend(
            payment.dstChainId,
            payload,
            "",
            fee,
            payable(msg.sender)
        );

        emit CrossChainPaymentInitiated(
            payment.paymentId,
            payment.payer,
            payment.dstChainId,
            payment.amount
        );
    }

    /**
     * @dev Handle incoming cross-chain payments
     */
    function _lzReceive(
        Origin calldata _origin,
        bytes32 _guid,
        bytes calldata _message,
        address _executor,
        bytes calldata _extraData
    ) internal override {
        CrossChainPayment memory crossChainPayment = abi.decode(_message, (CrossChainPayment));
        
        bytes32 messageId = keccak256(abi.encodePacked(_origin.srcEid, _origin.sender, _guid));
        require(!processedCrossChainPayments[messageId], "Payment already processed");
        processedCrossChainPayments[messageId] = true;

        // Process the cross-chain payment
        Payment storage payment = payments[crossChainPayment.paymentId];
        payment.status = PaymentStatus.COMPLETED;
        payment.processedAt = block.timestamp;

        // Transfer funds to payee - no fees
        uint256 merchantFee = 0;
        uint256 netAmount = crossChainPayment.amount;

        usdc.transfer(crossChainPayment.payee, netAmount);

        emit CrossChainPaymentCompleted(
            crossChainPayment.paymentId,
            crossChainPayment.payee,
            uint16(_origin.srcEid),
            netAmount
        );
    }

    /**
     * @dev Refund a payment
     */
    function refundPayment(
        bytes32 paymentId,
        uint256 accountId
    ) external nonReentrant whenNotPaused {
        Payment storage payment = payments[paymentId];
        require(payment.payee == msg.sender, "Not payment payee");
        require(payment.status == PaymentStatus.COMPLETED, "Payment not completed");
        require(accountContract.isValidAccount(payment.payer, accountId), "Invalid account");

        payment.status = PaymentStatus.REFUNDED;

        // Refund the amount
        usdc.transfer(payment.payer, payment.amount);

        emit PaymentRefunded(paymentId, payment.payer, payment.payee, payment.amount);
    }

    /**
     * @dev Cancel a payment
     */
    function cancelPayment(bytes32 paymentId) external nonReentrant whenNotPaused {
        Payment storage payment = payments[paymentId];
        require(payment.payer == msg.sender, "Not payment owner");
        require(payment.status == PaymentStatus.PENDING, "Payment not pending");

        payment.status = PaymentStatus.CANCELLED;

        emit PaymentFailed(paymentId, msg.sender, "Cancelled by payer");
    }
    
    /**
     * @dev Add or remove supported Torque currency
     */
    function setSupportedTorqueCurrency(address currency, bool supported) external onlyOwner {
        require(currency != address(0), "Invalid currency address");
        supportedTorqueCurrencies[currency] = supported;
        emit TorqueCurrencyAdded(currency, supported);
    }
    
    /**
     * @dev Set merchant's preferred settlement currency
     */
    function setMerchantSettlementPreference(address currency) external onlyAuthorizedMerchant {
        require(isTorqueCurrency(currency), "Only Torque currencies supported");
        merchantSettlementPreferences[msg.sender] = currency;
        emit MerchantSettlementPreferenceUpdated(msg.sender, currency);
    }
    
    /**
     * @dev Get merchant's preferred settlement currency
     */
    function getMerchantSettlementPreference(address merchant) external view returns (address) {
        address preference = merchantSettlementPreferences[merchant];
        return preference != address(0) ? preference : address(usdc);
    }
    
    /**
     * @dev Check if a currency is supported
     */
    function isSupportedTorqueCurrency(address currency) external view returns (bool) {
        return isTorqueCurrency(currency);
    }

    /**
     * @dev Authorize a merchant
     */
    function setMerchantAuthorization(
        address merchant,
        bool authorized
    ) external onlyOwner {
        authorizedMerchants[merchant] = authorized;
        emit MerchantAuthorized(merchant, authorized);
    }



    /**
     * @dev Pause/unpause contract
     */
    function pause() external onlyOwner {
        _pause();
    }

    function unpause() external onlyOwner {
        _unpause();
    }

    /**
     * @dev Get user payments
     */
    function getUserPayments(address user) external view returns (bytes32[] memory) {
        return userPayments[user];
    }

    /**
     * @dev Get merchant payments
     */
    function getMerchantPayments(address merchant) external view returns (bytes32[] memory) {
        return merchantPayments[merchant];
    }

    /**
     * @dev Get payment details
     */
    function getPayment(bytes32 paymentId) external view returns (Payment memory) {
        return payments[paymentId];
    }

    /**
     * @dev Get subscription details
     */
    function getSubscription(bytes32 subscriptionId) external view returns (Subscription memory) {
        return subscriptions[subscriptionId];
    }

    /**
     * @dev Get invoice details
     */
    function getInvoice(bytes32 invoiceId) external view returns (Invoice memory) {
        return invoices[invoiceId];
    }

    // ============ DONATION FUNCTIONS ============

    /**
     * @dev Create a new donation
     */
    function createDonation(
        DonationRequest calldata request,
        uint256 accountId
    ) external nonReentrant whenNotPaused returns (bytes32 donationId) {
        // Account verification is optional - if accountId is 0, skip validation
        if (accountId > 0) {
            require(accountContract.isValidAccount(msg.sender, accountId), "Invalid account");
        }
        require(request.amount >= MIN_PAYMENT_AMOUNT, "Amount too small");
        require(request.expiresAt > block.timestamp, "Invalid expiry");
        require(isTorqueCurrency(request.currency), "Only Torque currencies supported");
        require(authorizedRecipients[request.recipient], "Recipient not authorized");
        require(bytes(request.message).length <= MAX_METADATA_SIZE, "Message too long");
        require(bytes(request.cause).length <= MAX_METADATA_SIZE, "Cause too long");

        donationId = keccak256(abi.encodePacked(
            msg.sender,
            request.recipient,
            request.amount,
            request.currency,
            request.donationType,
            nonces[msg.sender]++,
            block.timestamp
        ));

        donations[donationId] = Donation({
            donationId: donationId,
            donor: msg.sender,
            recipient: request.recipient,
            amount: request.amount,
            currency: request.currency,
            donationType: request.donationType,
            status: PaymentStatus.PENDING,
            createdAt: block.timestamp,
            processedAt: 0,
            message: request.message,
            cause: request.cause,
            isAnonymous: request.isAnonymous,
            metadata: request.metadata,
            isCrossChain: false,
            dstChainId: 0,
            dstAddress: address(0)
        });

        userDonations[msg.sender].push(donationId);
        recipientDonations[request.recipient].push(donationId);

        emit DonationCreated(
            donationId,
            msg.sender,
            request.recipient,
            request.amount,
            request.currency,
            request.donationType,
            request.isAnonymous
        );
    }

    /**
     * @dev Process a donation
     */
    function processDonation(
        bytes32 donationId,
        uint256 accountId
    ) external nonReentrant whenNotPaused {
        Donation storage donation = donations[donationId];
        require(donation.donor == msg.sender, "Not donation owner");
        require(donation.status == PaymentStatus.PENDING, "Donation not pending");
        require(isTorqueCurrency(donation.currency), "Only Torque currencies supported");
        
        // Account verification is optional - if accountId is 0, skip validation
        if (accountId > 0) {
            require(accountContract.isValidAccount(msg.sender, accountId), "Invalid account");
        }

        // Check if user has sufficient balance in the donation currency
        IERC20 donationToken = IERC20(donation.currency);
        if (accountId > 0) {
            // Use TorqueAccount balance - would need to check specific currency balance
            require(donationToken.balanceOf(msg.sender) >= donation.amount, "Insufficient balance");
        } else {
            // Use direct balance
            require(donationToken.balanceOf(msg.sender) >= donation.amount, "Insufficient balance");
        }

        // Update donation status
        donation.status = PaymentStatus.PROCESSING;
        donation.processedAt = block.timestamp;

        // Transfer funds from donor
        if (accountId > 0) {
            // Use TorqueAccount - would need currency-specific withdrawal
            donationToken.transferFrom(msg.sender, address(this), donation.amount);
        } else {
            // Direct transfer from donor
            donationToken.transferFrom(msg.sender, address(this), donation.amount);
        }
        
        if (donation.isCrossChain) {
            // Handle cross-chain donation
            _initiateCrossChainDonation(donation, accountId);
        } else {
            // Local donation processing - no fees
            donationToken.transfer(donation.recipient, donation.amount);
            
            donation.status = PaymentStatus.COMPLETED;
            emit DonationProcessed(donationId, msg.sender, donation.recipient, donation.amount, donation.message);
        }
    }

    /**
     * @dev Cancel a donation
     */
    function cancelDonation(bytes32 donationId) external nonReentrant whenNotPaused {
        Donation storage donation = donations[donationId];
        require(donation.donor == msg.sender, "Not donation owner");
        require(donation.status == PaymentStatus.PENDING, "Donation not pending");

        donation.status = PaymentStatus.CANCELLED;

        emit DonationFailed(donationId, msg.sender, "Cancelled by donor");
    }

    /**
     * @dev Authorize a donation recipient
     */
    function setRecipientAuthorization(
        address recipient,
        bool authorized
    ) external onlyOwner {
        authorizedRecipients[recipient] = authorized;
        emit RecipientAuthorized(recipient, authorized);
    }

    /**
     * @dev Get user donations
     */
    function getUserDonations(address user) external view returns (bytes32[] memory) {
        return userDonations[user];
    }

    /**
     * @dev Get recipient donations
     */
    function getRecipientDonations(address recipient) external view returns (bytes32[] memory) {
        return recipientDonations[recipient];
    }

    /**
     * @dev Get donation details
     */
    function getDonation(bytes32 donationId) external view returns (Donation memory) {
        return donations[donationId];
    }

    /**
     * @dev Get donation statistics for a recipient
     */
    function getRecipientDonationStats(address recipient) external view returns (
        uint256 totalDonations,
        uint256 totalAmount,
        uint256 donorCount,
        uint256[] memory donationTypeCounts
    ) {
        bytes32[] memory recipientDonationIds = recipientDonations[recipient];
        donationTypeCounts = new uint256[](5); // 5 donation types
        
        for (uint256 i = 0; i < recipientDonationIds.length; i++) {
            Donation storage donation = donations[recipientDonationIds[i]];
            if (donation.status == PaymentStatus.COMPLETED) {
                totalDonations++;
                totalAmount += donation.amount;
                donationTypeCounts[uint256(donation.donationType)]++;
            }
        }
        
        // Count unique donors (simplified - in practice would need to iterate)
        donorCount = recipientDonationIds.length; // Simplified for gas efficiency
    }

    /**
     * @dev Initiate cross-chain donation
     */
    function _initiateCrossChainDonation(
        Donation storage donation,
        uint256 accountId
    ) internal {
        CrossChainPayment memory crossChainDonation = CrossChainPayment({
            paymentId: donation.donationId,
            payer: donation.donor,
            payee: donation.recipient,
            amount: donation.amount,
            currency: donation.currency,
            srcChainId: uint16(block.chainid),
            dstChainId: donation.dstChainId,
            srcAddress: address(this),
            dstAddress: donation.dstAddress,
            nonce: nonces[donation.donor]++
        });

        bytes memory payload = abi.encode(crossChainDonation);
        
        // Send cross-chain message
        MessagingFee memory fee = _quote(donation.dstChainId, payload, "", false);
        _lzSend(
            donation.dstChainId,
            payload,
            "",
            fee,
            payable(msg.sender)
        );

        emit CrossChainPaymentInitiated(
            donation.donationId,
            donation.donor,
            donation.dstChainId,
            donation.amount
        );
    }

    // ============ BNPL FUNCTIONS ============

    /**
     * @dev Create a BNPL agreement
     */
    function createBNPLAgreement(
        BNPLRequest calldata request,
        uint256 accountId
    ) external nonReentrant whenNotPaused returns (bytes32 bnplId) {
        // Account verification is optional - if accountId is 0, skip validation
        if (accountId > 0) {
            require(accountContract.isValidAccount(msg.sender, accountId), "Invalid account");
        }
        
        require(bnplEnabledMerchants[request.merchant], "Merchant does not support BNPL");
        require(request.totalAmount >= MIN_BNPL_AMOUNT, "Amount too small for BNPL");
        require(request.totalAmount <= MAX_BNPL_AMOUNT, "Amount too large for BNPL");
        require(request.installmentCount >= 2, "Minimum 2 installments required");
        require(request.installmentCount <= MAX_INSTALLMENT_COUNT, "Too many installments");
        require(request.downPayment >= (request.totalAmount * MIN_DOWN_PAYMENT_PERCENT) / 100, "Down payment too low");
        require(request.downPayment < request.totalAmount, "Down payment must be less than total amount");
        require(request.expiresAt > block.timestamp, "Invalid expiry");
        require(isTorqueCurrency(request.currency), "Only Torque currencies supported");
        require(bytes(request.description).length <= MAX_METADATA_SIZE, "Description too long");

        uint256 financedAmount = request.totalAmount - request.downPayment;
        uint256 installmentAmount = financedAmount / request.installmentCount;

        bnplId = keccak256(abi.encodePacked(
            msg.sender,
            request.merchant,
            request.totalAmount,
            request.downPayment,
            request.installmentCount,
            nonces[msg.sender]++,
            block.timestamp
        ));

        bnplAgreements[bnplId] = BNPLAgreement({
            bnplId: bnplId,
            buyer: msg.sender,
            merchant: request.merchant,
            totalAmount: request.totalAmount,
            downPayment: request.downPayment,
            financedAmount: financedAmount,
            currency: request.currency,
            status: BNPLStatus.AUTHORIZED,
            schedule: request.schedule,
            installmentAmount: installmentAmount,
            installmentCount: request.installmentCount,
            currentInstallment: 0,
            nextPaymentDate: 0, // Will be set when activated
            createdAt: block.timestamp,
            activatedAt: 0,
            completedAt: 0,
            lateFees: 0,
            defaultThreshold: request.defaultThreshold > 0 ? request.defaultThreshold : DEFAULT_THRESHOLD_DAYS,
            description: request.description,
            metadata: request.metadata
        });

        userBNPLAgreements[msg.sender].push(bnplId);
        merchantBNPLAgreements[request.merchant].push(bnplId);

        emit BNPLAgreementCreated(
            bnplId,
            msg.sender,
            request.merchant,
            request.totalAmount,
            request.downPayment,
            request.installmentCount
        );
    }

    /**
     * @dev Activate a BNPL agreement (pay down payment and start installments)
     */
    function activateBNPLAgreement(
        bytes32 bnplId,
        uint256 accountId
    ) external nonReentrant whenNotPaused {
        BNPLAgreement storage agreement = bnplAgreements[bnplId];
        require(agreement.buyer == msg.sender, "Not agreement owner");
        require(agreement.status == BNPLStatus.AUTHORIZED, "Agreement not authorized");
        
        // Account verification is optional - if accountId is 0, skip validation
        if (accountId > 0) {
            require(accountContract.isValidAccount(msg.sender, accountId), "Invalid account");
        }

        // Check if user has sufficient balance for down payment
        IERC20 currencyToken = IERC20(agreement.currency);
        require(currencyToken.balanceOf(msg.sender) >= agreement.downPayment, "Insufficient balance for down payment");

        // Transfer down payment
        currencyToken.transferFrom(msg.sender, address(this), agreement.downPayment);
        currencyToken.transfer(agreement.merchant, agreement.downPayment);

        // Activate the agreement
        agreement.status = BNPLStatus.ACTIVE;
        agreement.activatedAt = block.timestamp;
        agreement.currentInstallment = 1;
        
        // Set up installment schedule
        uint256 interval = _getScheduleInterval(agreement.schedule);
        agreement.nextPaymentDate = block.timestamp + interval;

        // Create installment records
        _createInstallments(agreement);

        emit BNPLAgreementActivated(bnplId, msg.sender, block.timestamp);
    }

    /**
     * @dev Pay an installment
     */
    function payInstallment(
        bytes32 bnplId,
        uint256 installmentNumber,
        uint256 accountId
    ) external nonReentrant whenNotPaused {
        BNPLAgreement storage agreement = bnplAgreements[bnplId];
        require(agreement.buyer == msg.sender, "Not agreement owner");
        require(agreement.status == BNPLStatus.ACTIVE, "Agreement not active");
        require(installmentNumber <= agreement.installmentCount, "Invalid installment number");
        
        Installment storage installment = installments[bnplId][installmentNumber];
        require(!installment.paid, "Installment already paid");
        require(block.timestamp >= installment.dueDate, "Installment not due yet");

        // Account verification is optional - if accountId is 0, skip validation
        if (accountId > 0) {
            require(accountContract.isValidAccount(msg.sender, accountId), "Invalid account");
        }

        // Calculate late fees if applicable
        uint256 lateFees = 0;
        if (block.timestamp > installment.dueDate) {
            uint256 daysLate = (block.timestamp - installment.dueDate) / 1 days;
            lateFees = (installment.amount * LATE_FEE_RATE * daysLate) / BASIS_POINTS;
        }

        uint256 totalAmount = installment.amount + lateFees;

        // Check if user has sufficient balance
        IERC20 currencyToken = IERC20(agreement.currency);
        require(currencyToken.balanceOf(msg.sender) >= totalAmount, "Insufficient balance");

        // Transfer payment
        currencyToken.transferFrom(msg.sender, address(this), totalAmount);
        currencyToken.transfer(agreement.merchant, totalAmount);

        // Update installment
        installment.paid = true;
        installment.paidAt = block.timestamp;
        installment.lateFees = lateFees;

        // Update agreement
        agreement.currentInstallment++;
        agreement.lateFees += lateFees;

        // Check if agreement is completed
        if (agreement.currentInstallment > agreement.installmentCount) {
            agreement.status = BNPLStatus.PAID;
            agreement.completedAt = block.timestamp;
            emit BNPLAgreementCompleted(bnplId, msg.sender, block.timestamp);
        } else {
            // Set next payment date
            uint256 interval = _getScheduleInterval(agreement.schedule);
            agreement.nextPaymentDate = block.timestamp + interval;
        }

        emit InstallmentPaid(bnplId, msg.sender, installmentNumber, installment.amount, lateFees);
    }

    /**
     * @dev Cancel a BNPL agreement (before activation)
     */
    function cancelBNPLAgreement(bytes32 bnplId) external nonReentrant whenNotPaused {
        BNPLAgreement storage agreement = bnplAgreements[bnplId];
        require(agreement.buyer == msg.sender, "Not agreement owner");
        require(agreement.status == BNPLStatus.AUTHORIZED, "Agreement already activated");

        agreement.status = BNPLStatus.CANCELLED;

        emit BNPLAgreementDefaulted(bnplId, msg.sender, block.timestamp);
    }

    /**
     * @dev Check for defaulted agreements (can be called by anyone)
     */
    function checkForDefaults() external {
        // This function can be called by anyone to check for defaults
        // In a production system, this would be called by a keeper or automated system
        // For now, we'll just emit an event for demonstration
        emit BNPLAgreementDefaulted(bytes32(0), address(0), block.timestamp);
    }

    /**
     * @dev Enable/disable BNPL for a merchant
     */
    function setBNPLMerchantEnabled(
        address merchant,
        bool enabled
    ) external onlyOwner {
        require(authorizedMerchants[merchant], "Merchant not authorized");
        bnplEnabledMerchants[merchant] = enabled;
        emit BNPLMerchantEnabled(merchant, enabled);
    }

    /**
     * @dev Get user BNPL agreements
     */
    function getUserBNPLAgreements(address user) external view returns (bytes32[] memory) {
        return userBNPLAgreements[user];
    }

    /**
     * @dev Get merchant BNPL agreements
     */
    function getMerchantBNPLAgreements(address merchant) external view returns (bytes32[] memory) {
        return merchantBNPLAgreements[merchant];
    }

    /**
     * @dev Get BNPL agreement details
     */
    function getBNPLAgreement(bytes32 bnplId) external view returns (BNPLAgreement memory) {
        return bnplAgreements[bnplId];
    }

    /**
     * @dev Get installment details
     */
    function getInstallment(bytes32 bnplId, uint256 installmentNumber) external view returns (Installment memory) {
        return installments[bnplId][installmentNumber];
    }

    /**
     * @dev Get BNPL statistics for a user
     */
    function getUserBNPLStats(address user) external view returns (
        uint256 totalAgreements,
        uint256 activeAgreements,
        uint256 completedAgreements,
        uint256 totalAmount,
        uint256 totalLateFees
    ) {
        bytes32[] memory userAgreementIds = userBNPLAgreements[user];
        
        for (uint256 i = 0; i < userAgreementIds.length; i++) {
            BNPLAgreement storage agreement = bnplAgreements[userAgreementIds[i]];
            totalAgreements++;
            totalAmount += agreement.totalAmount;
            totalLateFees += agreement.lateFees;
            
            if (agreement.status == BNPLStatus.ACTIVE) {
                activeAgreements++;
            } else if (agreement.status == BNPLStatus.PAID) {
                completedAgreements++;
            }
        }
    }

    /**
     * @dev Get schedule interval in seconds
     */
    function _getScheduleInterval(BNPLSchedule schedule) internal pure returns (uint256) {
        if (schedule == BNPLSchedule.WEEKLY) {
            return 7 days;
        } else if (schedule == BNPLSchedule.BIWEEKLY) {
            return 14 days;
        } else if (schedule == BNPLSchedule.MONTHLY) {
            return 30 days;
        } else {
            return 30 days; // Default to monthly for custom
        }
    }

    /**
     * @dev Create installment records
     */
    function _createInstallments(BNPLAgreement storage agreement) internal {
        uint256 interval = _getScheduleInterval(agreement.schedule);
        uint256 currentDate = agreement.activatedAt + interval;

        for (uint256 i = 1; i <= agreement.installmentCount; i++) {
            installments[agreement.bnplId][i] = Installment({
                installmentNumber: i,
                amount: agreement.installmentAmount,
                dueDate: currentDate,
                paid: false,
                paidAt: 0,
                lateFees: 0
            });
            currentDate += interval;
        }
    }

    // ============ MASS PAYMENT FUNCTIONS ============

    /**
     * @dev Create a mass payment
     */
    function createMassPayment(
        MassPaymentRequest calldata request,
        uint256 accountId
    ) external nonReentrant whenNotPaused onlyMassPaymentEnabled returns (bytes32 massPaymentId) {
        // Account verification is optional - if accountId is 0, skip validation
        if (accountId > 0) {
            require(accountContract.isValidAccount(msg.sender, accountId), "Invalid account");
        }
        
        require(request.totalAmount >= MIN_MASS_PAYMENT_AMOUNT, "Amount too small for mass payment");
        require(request.totalAmount <= MAX_MASS_PAYMENT_AMOUNT, "Amount too large for mass payment");
        require(request.expiresAt > block.timestamp, "Invalid expiry");
        require(isTorqueCurrency(request.currency), "Only Torque currencies supported");
        require(bytes(request.description).length <= MAX_METADATA_SIZE, "Description too long");

        massPaymentId = keccak256(abi.encodePacked(
            msg.sender,
            request.currency,
            request.totalAmount,
            nonces[msg.sender]++,
            block.timestamp
        ));

        massPayments[massPaymentId] = MassPayment({
            massPaymentId: massPaymentId,
            payer: msg.sender,
            currency: request.currency,
            totalAmount: request.totalAmount,
            processedAmount: 0,
            recipientCount: 0,
            processedCount: 0,
            failedCount: 0,
            status: MassPaymentStatus.PENDING,
            createdAt: block.timestamp,
            processedAt: 0,
            completedAt: 0,
            description: request.description,
            metadata: request.metadata,
            isCrossChain: false,
            dstChainId: 0,
            dstAddress: address(0)
        });

        userMassPayments[msg.sender].push(massPaymentId);

        emit MassPaymentCreated(
            massPaymentId,
            msg.sender,
            request.currency,
            request.totalAmount,
            0
        );
    }

    /**
     * @dev Add recipients to a mass payment
     */
    function addMassPaymentRecipients(
        bytes32 massPaymentId,
        MassPaymentRecipient[] calldata recipients
    ) external nonReentrant whenNotPaused {
        MassPayment storage massPayment = massPayments[massPaymentId];
        require(massPayment.payer == msg.sender, "Not mass payment owner");
        require(massPayment.status == MassPaymentStatus.PENDING, "Mass payment not pending");
        require(recipients.length > 0, "No recipients provided");
        require(massPayment.recipientCount + recipients.length <= MAX_MASS_PAYMENT_RECIPIENTS, "Too many recipients");

        uint256 totalAmount = 0;
        for (uint256 i = 0; i < recipients.length; i++) {
            require(recipients[i].amount >= MIN_MASS_PAYMENT_AMOUNT, "Recipient amount too small");
            require(recipients[i].recipient != address(0), "Invalid recipient address");
            totalAmount += recipients[i].amount;
        }

        require(massPayment.totalAmount >= totalAmount, "Total amount exceeds mass payment amount");

        // Add recipients
        for (uint256 i = 0; i < recipients.length; i++) {
            massPaymentRecipients[massPaymentId].push(recipients[i]);
            recipientMassPayments[recipients[i].recipient].push(massPaymentId);
            
            emit MassPaymentRecipientAdded(
                massPaymentId,
                recipients[i].recipient,
                recipients[i].amount,
                recipients[i].recipientType
            );
        }

        massPayment.recipientCount += recipients.length;
    }

    /**
     * @dev Process a mass payment batch
     */
    function processMassPaymentBatch(
        bytes32 massPaymentId,
        uint256 batchIndex
    ) external nonReentrant whenNotPaused {
        MassPayment storage massPayment = massPayments[massPaymentId];
        require(massPayment.payer == msg.sender, "Not mass payment owner");
        require(massPayment.status == MassPaymentStatus.PENDING || massPayment.status == MassPaymentStatus.PROCESSING, "Mass payment not active");
        require(massPayment.recipientCount > 0, "No recipients to process");

        uint256 startIndex = batchIndex * MASS_PAYMENT_BATCH_SIZE;
        uint256 endIndex = startIndex + MASS_PAYMENT_BATCH_SIZE;
        if (endIndex > massPayment.recipientCount) {
            endIndex = massPayment.recipientCount;
        }

        require(startIndex < massPayment.recipientCount, "Invalid batch index");

        // Create batch record
        bytes32 batchId = keccak256(abi.encodePacked(massPaymentId, batchIndex, block.timestamp));
        MassPaymentBatch memory batch = MassPaymentBatch({
            batchId: batchId,
            massPaymentId: massPaymentId,
            startIndex: startIndex,
            endIndex: endIndex,
            batchAmount: 0,
            processedCount: 0,
            failedCount: 0,
            completed: false,
            completedAt: 0
        });

        // Update mass payment status
        if (massPayment.status == MassPaymentStatus.PENDING) {
            massPayment.status = MassPaymentStatus.PROCESSING;
            massPayment.processedAt = block.timestamp;
        }

        // Process recipients in batch
        IERC20 currencyToken = IERC20(massPayment.currency);
        uint256 batchAmount = 0;
        uint256 processedCount = 0;
        uint256 failedCount = 0;

        for (uint256 i = startIndex; i < endIndex; i++) {
            MassPaymentRecipient storage recipient = massPaymentRecipients[massPaymentId][i];
            
            if (!recipient.processed) {
                try currencyToken.transfer(recipient.recipient, recipient.amount) {
                    recipient.processed = true;
                    recipient.processedAt = block.timestamp;
                    batchAmount += recipient.amount;
                    processedCount++;
                } catch {
                    recipient.failureReason = "Transfer failed";
                    failedCount++;
                }
            }
        }

        // Update batch
        batch.batchAmount = batchAmount;
        batch.processedCount = processedCount;
        batch.failedCount = failedCount;
        batch.completed = true;
        batch.completedAt = block.timestamp;

        // Update mass payment
        massPayment.processedAmount += batchAmount;
        massPayment.processedCount += processedCount;
        massPayment.failedCount += failedCount;

        massPaymentBatches[massPaymentId].push(batch);

        emit MassPaymentBatchProcessed(
            massPaymentId,
            batchId,
            processedCount,
            failedCount,
            batchAmount
        );

        // Check if mass payment is complete
        if (massPayment.processedCount + massPayment.failedCount >= massPayment.recipientCount) {
            massPayment.status = MassPaymentStatus.COMPLETED;
            massPayment.completedAt = block.timestamp;
            
            emit MassPaymentCompleted(
                massPaymentId,
                msg.sender,
                massPayment.processedCount,
                massPayment.failedCount,
                block.timestamp
            );
        }
    }

    /**
     * @dev Process entire mass payment (for smaller payments)
     */
    function processMassPayment(
        bytes32 massPaymentId,
        uint256 accountId
    ) external nonReentrant whenNotPaused {
        MassPayment storage massPayment = massPayments[massPaymentId];
        require(massPayment.payer == msg.sender, "Not mass payment owner");
        require(massPayment.status == MassPaymentStatus.PENDING, "Mass payment not pending");
        require(massPayment.recipientCount > 0, "No recipients to process");

        // Account verification is optional - if accountId is 0, skip validation
        if (accountId > 0) {
            require(accountContract.isValidAccount(msg.sender, accountId), "Invalid account");
        }

        // Check if user has sufficient balance
        IERC20 currencyToken = IERC20(massPayment.currency);
        require(currencyToken.balanceOf(msg.sender) >= massPayment.totalAmount, "Insufficient balance");

        // Transfer total amount to contract
        currencyToken.transferFrom(msg.sender, address(this), massPayment.totalAmount);

        // Update status
        massPayment.status = MassPaymentStatus.PROCESSING;
        massPayment.processedAt = block.timestamp;

        // Process all recipients
        uint256 processedAmount = 0;
        uint256 processedCount = 0;
        uint256 failedCount = 0;

        for (uint256 i = 0; i < massPayment.recipientCount; i++) {
            MassPaymentRecipient storage recipient = massPaymentRecipients[massPaymentId][i];
            
            try currencyToken.transfer(recipient.recipient, recipient.amount) {
                recipient.processed = true;
                recipient.processedAt = block.timestamp;
                processedAmount += recipient.amount;
                processedCount++;
            } catch {
                recipient.failureReason = "Transfer failed";
                failedCount++;
            }
        }

        // Update mass payment
        massPayment.processedAmount = processedAmount;
        massPayment.processedCount = processedCount;
        massPayment.failedCount = failedCount;
        massPayment.status = MassPaymentStatus.COMPLETED;
        massPayment.completedAt = block.timestamp;

        emit MassPaymentCompleted(
            massPaymentId,
            msg.sender,
            processedCount,
            failedCount,
            block.timestamp
        );
    }

    /**
     * @dev Cancel a mass payment
     */
    function cancelMassPayment(bytes32 massPaymentId) external nonReentrant whenNotPaused {
        MassPayment storage massPayment = massPayments[massPaymentId];
        require(massPayment.payer == msg.sender, "Not mass payment owner");
        require(massPayment.status == MassPaymentStatus.PENDING, "Mass payment already processed");

        massPayment.status = MassPaymentStatus.CANCELLED;

        emit MassPaymentFailed(massPaymentId, msg.sender, "Cancelled by payer");
    }

    /**
     * @dev Enable/disable mass payments for a user
     */
    function setMassPaymentEnabled(
        address user,
        bool enabled
    ) external onlyOwner {
        massPaymentEnabled[user] = enabled;
        emit MassPaymentEnabled(user, enabled);
    }

    /**
     * @dev Get user mass payments
     */
    function getUserMassPayments(address user) external view returns (bytes32[] memory) {
        return userMassPayments[user];
    }

    /**
     * @dev Get recipient mass payments
     */
    function getRecipientMassPayments(address recipient) external view returns (bytes32[] memory) {
        return recipientMassPayments[recipient];
    }

    /**
     * @dev Get mass payment details
     */
    function getMassPayment(bytes32 massPaymentId) external view returns (MassPayment memory) {
        return massPayments[massPaymentId];
    }

    /**
     * @dev Get mass payment recipients
     */
    function getMassPaymentRecipients(bytes32 massPaymentId) external view returns (MassPaymentRecipient[] memory) {
        return massPaymentRecipients[massPaymentId];
    }

    /**
     * @dev Get mass payment batches
     */
    function getMassPaymentBatches(bytes32 massPaymentId) external view returns (MassPaymentBatch[] memory) {
        return massPaymentBatches[massPaymentId];
    }

    /**
     * @dev Get mass payment statistics for a user
     */
    function getUserMassPaymentStats(address user) external view returns (
        uint256 totalPayments,
        uint256 totalRecipients,
        uint256 totalAmount,
        uint256 totalProcessed,
        uint256 totalFailed
    ) {
        bytes32[] memory userPaymentIds = userMassPayments[user];
        
        for (uint256 i = 0; i < userPaymentIds.length; i++) {
            MassPayment storage massPayment = massPayments[userPaymentIds[i]];
            totalPayments++;
            totalRecipients += massPayment.recipientCount;
            totalAmount += massPayment.totalAmount;
            totalProcessed += massPayment.processedCount;
            totalFailed += massPayment.failedCount;
        }
    }

    /**
     * @dev Get recipient statistics
     */
    function getRecipientStats(address recipient) external view returns (
        uint256 totalReceived,
        uint256 paymentCount,
        uint256[] memory recipientTypeCounts
    ) {
        bytes32[] memory recipientPaymentIds = recipientMassPayments[recipient];
        recipientTypeCounts = new uint256[](6); // 6 recipient types
        
        for (uint256 i = 0; i < recipientPaymentIds.length; i++) {
            MassPaymentRecipient[] memory recipients = massPaymentRecipients[recipientPaymentIds[i]];
            
            for (uint256 j = 0; j < recipients.length; j++) {
                if (recipients[j].recipient == recipient && recipients[j].processed) {
                    totalReceived += recipients[j].amount;
                    paymentCount++;
                    recipientTypeCounts[uint256(recipients[j].recipientType)]++;
                }
            }
        }
    }

    receive() external payable {}
} 