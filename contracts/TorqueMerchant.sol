// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.28;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "./TorquePayments.sol";
import "./interfaces/ITorquePayments.sol";
import "./interfaces/ITorqueGateway.sol";

contract TorqueMerchant is Ownable, ReentrancyGuard {
    struct MerchantStats {
        uint256 totalPayments;
        uint256 totalVolume;
        uint256 totalFees;
        uint256 activeSubscriptions;
        uint256 pendingInvoices;
        uint256 successfulPayments;
        uint256 failedPayments;
        uint256 refundedPayments;
        uint256 lastPaymentTime;
        uint256 averagePaymentAmount;
    }

    struct PaymentAnalytics {
        uint256 dailyVolume;
        uint256 weeklyVolume;
        uint256 monthlyVolume;
        uint256 dailyCount;
        uint256 weeklyCount;
        uint256 monthlyCount;
        uint256 conversionRate;
        uint256 averageSessionTime;
    }

    struct RevenueReport {
        uint256 grossRevenue;
        uint256 netRevenue;
        uint256 totalFees;
        uint256 refunds;
        uint256 chargebacks;
        uint256 periodStart;
        uint256 periodEnd;
    }

    struct CustomerInsights {
        address customer;
        uint256 totalSpent;
        uint256 paymentCount;
        uint256 lastPaymentTime;
        uint256 averagePaymentAmount;
        bool isReturning;
        uint256 subscriptionCount;
    }

    struct Dispute {
        bytes32 disputeId;
        bytes32 paymentId;
        address customer;
        address merchant;
        uint256 amount;
        string reason;
        uint256 createdAt;
        bool resolved;
        address resolver;
        string resolution;
    }

    ITorquePayments public immutable paymentsContract;
    ITorqueGateway public immutable gatewayContract;

    mapping(address => MerchantStats) public merchantStats;
    mapping(address => PaymentAnalytics) public paymentAnalytics;
    mapping(address => mapping(uint256 => RevenueReport)) public revenueReports; // merchant => period => report
    mapping(address => mapping(address => CustomerInsights)) public customerInsights;
    mapping(bytes32 => Dispute) public disputes;
    mapping(address => bytes32[]) public merchantDisputes;
    mapping(address => bool) public authorizedAnalytics;

    uint256 public constant REPORTING_PERIOD = 30 days;
    uint256 public constant DISPUTE_TIMEOUT = 7 days;
    uint256 public constant MAX_DISPUTE_REASON_LENGTH = 500;

    event MerchantStatsUpdated(
        address indexed merchant,
        uint256 totalPayments,
        uint256 totalVolume,
        uint256 totalFees
    );
    event RevenueReportGenerated(
        address indexed merchant,
        uint256 period,
        uint256 grossRevenue,
        uint256 netRevenue
    );
    event CustomerInsightsUpdated(
        address indexed merchant,
        address indexed customer,
        uint256 totalSpent,
        uint256 paymentCount
    );
    event DisputeCreated(
        bytes32 indexed disputeId,
        bytes32 indexed paymentId,
        address indexed customer,
        string reason
    );
    event DisputeResolved(
        bytes32 indexed disputeId,
        address indexed resolver,
        string resolution
    );
    event AnalyticsAuthorized(address indexed merchant, bool authorized);

    constructor(
        address _paymentsContract,
        address _gatewayContract
    ) Ownable(msg.sender) {
        paymentsContract = ITorquePayments(_paymentsContract);
        gatewayContract = ITorqueGateway(_gatewayContract);
    }

    /**
     * @dev Update merchant statistics
     */
    function updateMerchantStats(address merchant) external {
        require(authorizedAnalytics[merchant] || msg.sender == owner(), "Not authorized");
        
        bytes32[] memory paymentIds = paymentsContract.getMerchantPayments(merchant);
        
        MerchantStats storage stats = merchantStats[merchant];
        uint256 totalVolume = 0;
        uint256 totalFees = 0;
        uint256 successfulPayments = 0;
        uint256 failedPayments = 0;
        uint256 refundedPayments = 0;
        uint256 lastPaymentTime = 0;

        for (uint256 i = 0; i < paymentIds.length; i++) {
            TorquePayments.Payment memory payment = paymentsContract.getPayment(paymentIds[i]);
            
            if (payment.payee == merchant) {
                totalVolume += payment.amount;
                
                if (payment.status == TorquePayments.PaymentStatus.COMPLETED) {
                    successfulPayments++;
                    lastPaymentTime = payment.processedAt;
                } else if (payment.status == TorquePayments.PaymentStatus.FAILED) {
                    failedPayments++;
                } else if (payment.status == TorquePayments.PaymentStatus.REFUNDED) {
                    refundedPayments++;
                }
            }
        }

        // Calculate fees (simplified calculation)
        totalFees = (totalVolume * 25) / 10000; // 0.25% fee

        stats.totalPayments = paymentIds.length;
        stats.totalVolume = totalVolume;
        stats.totalFees = totalFees;
        stats.successfulPayments = successfulPayments;
        stats.failedPayments = failedPayments;
        stats.refundedPayments = refundedPayments;
        stats.lastPaymentTime = lastPaymentTime;
        stats.averagePaymentAmount = successfulPayments > 0 ? totalVolume / successfulPayments : 0;

        emit MerchantStatsUpdated(merchant, stats.totalPayments, stats.totalVolume, stats.totalFees);
    }

    /**
     * @dev Generate revenue report for a period
     */
    function generateRevenueReport(
        address merchant,
        uint256 periodStart,
        uint256 periodEnd
    ) external returns (uint256 reportId) {
        require(authorizedAnalytics[merchant] || msg.sender == owner(), "Not authorized");
        require(periodStart < periodEnd, "Invalid period");
        require(periodEnd <= block.timestamp, "Future period");

        reportId = uint256(keccak256(abi.encodePacked(merchant, periodStart, periodEnd)));
        
        bytes32[] memory paymentIds = paymentsContract.getMerchantPayments(merchant);
        
        uint256 grossRevenue = 0;
        uint256 totalFees = 0;
        uint256 refunds = 0;
        uint256 chargebacks = 0;

        for (uint256 i = 0; i < paymentIds.length; i++) {
            TorquePayments.Payment memory payment = paymentsContract.getPayment(paymentIds[i]);
            
            if (payment.payee == merchant && 
                payment.processedAt >= periodStart && 
                payment.processedAt <= periodEnd) {
                
                if (payment.status == TorquePayments.PaymentStatus.COMPLETED) {
                    grossRevenue += payment.amount;
                    totalFees += (payment.amount * 25) / 10000; // 0.25% fee
                } else if (payment.status == TorquePayments.PaymentStatus.REFUNDED) {
                    refunds += payment.amount;
                }
            }
        }

        uint256 netRevenue = grossRevenue - totalFees - refunds - chargebacks;

        revenueReports[merchant][reportId] = RevenueReport({
            grossRevenue: grossRevenue,
            netRevenue: netRevenue,
            totalFees: totalFees,
            refunds: refunds,
            chargebacks: chargebacks,
            periodStart: periodStart,
            periodEnd: periodEnd
        });

        emit RevenueReportGenerated(merchant, reportId, grossRevenue, netRevenue);
    }

    /**
     * @dev Update customer insights
     */
    function updateCustomerInsights(
        address merchant,
        address customer
    ) external {
        require(authorizedAnalytics[merchant] || msg.sender == owner(), "Not authorized");
        
        bytes32[] memory paymentIds = paymentsContract.getUserPayments(customer);
        
        uint256 totalSpent = 0;
        uint256 paymentCount = 0;
        uint256 lastPaymentTime = 0;
        uint256 subscriptionCount = 0;

        for (uint256 i = 0; i < paymentIds.length; i++) {
            TorquePayments.Payment memory payment = paymentsContract.getPayment(paymentIds[i]);
            
            if (payment.payee == merchant && 
                payment.status == TorquePayments.PaymentStatus.COMPLETED) {
                
                totalSpent += payment.amount;
                paymentCount++;
                
                if (payment.processedAt > lastPaymentTime) {
                    lastPaymentTime = payment.processedAt;
                }

                if (payment.paymentType == TorquePayments.PaymentType.SUBSCRIPTION) {
                    subscriptionCount++;
                }
            }
        }

        bool isReturning = paymentCount > 1;
        uint256 averagePaymentAmount = paymentCount > 0 ? totalSpent / paymentCount : 0;

        customerInsights[merchant][customer] = CustomerInsights({
            customer: customer,
            totalSpent: totalSpent,
            paymentCount: paymentCount,
            lastPaymentTime: lastPaymentTime,
            averagePaymentAmount: averagePaymentAmount,
            isReturning: isReturning,
            subscriptionCount: subscriptionCount
        });

        emit CustomerInsightsUpdated(merchant, customer, totalSpent, paymentCount);
    }

    /**
     * @dev Create a payment dispute
     */
    function createDispute(
        bytes32 paymentId,
        string calldata reason
    ) external nonReentrant {
        require(bytes(reason).length <= MAX_DISPUTE_REASON_LENGTH, "Reason too long");
        
        TorquePayments.Payment memory payment = paymentsContract.getPayment(paymentId);
        require(payment.payer == msg.sender, "Not payment payer");
        require(payment.status == TorquePayments.PaymentStatus.COMPLETED, "Payment not completed");
        require(block.timestamp <= payment.processedAt + DISPUTE_TIMEOUT, "Dispute timeout");

        bytes32 disputeId = keccak256(abi.encodePacked(paymentId, msg.sender, block.timestamp));

        disputes[disputeId] = Dispute({
            disputeId: disputeId,
            paymentId: paymentId,
            customer: msg.sender,
            merchant: payment.payee,
            amount: payment.amount,
            reason: reason,
            createdAt: block.timestamp,
            resolved: false,
            resolver: address(0),
            resolution: ""
        });

        merchantDisputes[payment.payee].push(disputeId);

        emit DisputeCreated(disputeId, paymentId, msg.sender, reason);
    }

    /**
     * @dev Resolve a dispute
     */
    function resolveDispute(
        bytes32 disputeId,
        string calldata resolution
    ) external onlyOwner {
        Dispute storage dispute = disputes[disputeId];
        require(!dispute.resolved, "Dispute already resolved");

        dispute.resolved = true;
        dispute.resolver = msg.sender;
        dispute.resolution = resolution;

        emit DisputeResolved(disputeId, msg.sender, resolution);
    }

    /**
     * @dev Get merchant analytics
     */
    function getMerchantAnalytics(
        address merchant,
        uint256 daysBack
    ) external view returns (PaymentAnalytics memory) {
        require(authorizedAnalytics[merchant] || msg.sender == owner(), "Not authorized");
        require(daysBack > 0 && daysBack <= 365, "Invalid days back");
        
        bytes32[] memory paymentIds = paymentsContract.getMerchantPayments(merchant);
        
        uint256 dailyVolume = 0;
        uint256 weeklyVolume = 0;
        uint256 monthlyVolume = 0;
        uint256 dailyCount = 0;
        uint256 weeklyCount = 0;
        uint256 monthlyCount = 0;
        uint256 totalSessions = 0;
        uint256 totalSessionTime = 0;

        uint256 dayAgo = block.timestamp - 1 days;
        uint256 weekAgo = block.timestamp - 7 days;
        uint256 monthAgo = block.timestamp - 30 days;
        uint256 customPeriodAgo = block.timestamp - (daysBack * 1 days);

        for (uint256 i = 0; i < paymentIds.length; i++) {
            TorquePayments.Payment memory payment = paymentsContract.getPayment(paymentIds[i]);
            
            if (payment.payee == merchant && 
                payment.status == TorquePayments.PaymentStatus.COMPLETED) {
                
                if (payment.processedAt >= dayAgo) {
                    dailyVolume += payment.amount;
                    dailyCount++;
                }
                if (payment.processedAt >= weekAgo) {
                    weeklyVolume += payment.amount;
                    weeklyCount++;
                }
                if (payment.processedAt >= monthAgo) {
                    monthlyVolume += payment.amount;
                    monthlyCount++;
                }
                
                // Use daysBack parameter for custom period analytics
                if (payment.processedAt >= customPeriodAgo) {
                    totalSessions++;
                    // For demo purposes, using a simple session time calculation
                    totalSessionTime += 300; // 5 minutes average session time
                }
            }
        }

        uint256 conversionRate = totalSessions > 0 ? (dailyCount * 100) / totalSessions : 0;
        uint256 averageSessionTime = totalSessions > 0 ? totalSessionTime / totalSessions : 0;

        return PaymentAnalytics({
            dailyVolume: dailyVolume,
            weeklyVolume: weeklyVolume,
            monthlyVolume: monthlyVolume,
            dailyCount: dailyCount,
            weeklyCount: weeklyCount,
            monthlyCount: monthlyCount,
            conversionRate: conversionRate,
            averageSessionTime: averageSessionTime
        });
    }

    /**
     * @dev Get customer insights for a merchant
     */
    function getCustomerInsights(
        address merchant,
        address customer
    ) external view returns (CustomerInsights memory) {
        return customerInsights[merchant][customer];
    }

    /**
     * @dev Get merchant disputes
     */
    function getMerchantDisputes(address merchant) external view returns (bytes32[] memory) {
        return merchantDisputes[merchant];
    }

    /**
     * @dev Get dispute details
     */
    function getDispute(bytes32 disputeId) external view returns (Dispute memory) {
        return disputes[disputeId];
    }

    /**
     * @dev Get revenue report
     */
    function getRevenueReport(
        address merchant,
        uint256 reportId
    ) external view returns (RevenueReport memory) {
        return revenueReports[merchant][reportId];
    }

    /**
     * @dev Authorize analytics access
     */
    function setAnalyticsAuthorization(
        address merchant,
        bool authorized
    ) external onlyOwner {
        authorizedAnalytics[merchant] = authorized;
        emit AnalyticsAuthorized(merchant, authorized);
    }

    /**
     * @dev Get merchant statistics
     */
    function getMerchantStats(address merchant) external view returns (MerchantStats memory) {
        return merchantStats[merchant];
    }

    /**
     * @dev Check if merchant has analytics access
     */
    function hasAnalyticsAccess(address merchant) external view returns (bool) {
        return authorizedAnalytics[merchant];
    }
}
