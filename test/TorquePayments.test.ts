import { expect } from "chai";
import { ethers } from "hardhat";
import { Contract, Signer } from "ethers";
import { TorquePayments, TorqueGateway, TorqueMerchant } from "../typechain-types";

describe("TorquePayments System", function () {
  let torquePayments: TorquePayments;
  let torqueGateway: TorqueGateway;
  let torqueMerchant: TorqueMerchant;
  let mockTorqueAccount: Contract;
  let mockUSDC: Contract;
  let mockLZEndpoint: Contract;
  
  let owner: Signer;
  let merchant: Signer;
  let customer: Signer;
  let customer2: Signer;
  let guardian: Signer;

  const PAYMENT_AMOUNT = ethers.parseUnits("100", 6); // 100 TUSD
  const SUBSCRIPTION_AMOUNT = ethers.parseUnits("10", 6); // 10 TUSD
  const INVOICE_AMOUNT = ethers.parseUnits("50", 6); // 50 TUSD

  beforeEach(async function () {
    [owner, merchant, customer, customer2, guardian] = await ethers.getSigners();

    // Deploy mock contracts
    const MockERC20 = await ethers.getContractFactory("MockERC20");
    mockUSDC = await MockERC20.deploy("Torque USD", "TUSD", 6);

    const MockTorqueAccount = await ethers.getContractFactory("MockTorqueAccount");
    mockTorqueAccount = await MockTorqueAccount.deploy(mockUSDC.getAddress());

    const MockLZEndpoint = await ethers.getContractFactory("MockLZEndpoint");
    mockLZEndpoint = await MockLZEndpoint.deploy();

    // Deploy payment contracts
    const TorquePayments = await ethers.getContractFactory("TorquePayments");
    torquePayments = await TorquePayments.deploy(
      await mockTorqueAccount.getAddress(),
      await mockUSDC.getAddress(),
      await mockLZEndpoint.getAddress()
    );

    const TorqueGateway = await ethers.getContractFactory("TorqueGateway");
    torqueGateway = await TorqueGateway.deploy(
      await torquePayments.getAddress(),
      await mockUSDC.getAddress()
    );

    const TorqueMerchant = await ethers.getContractFactory("TorqueMerchant");
    torqueMerchant = await TorqueMerchant.deploy(
      await torquePayments.getAddress(),
      await torqueGateway.getAddress()
    );

    // Setup initial state
    await mockUSDC.mint(await mockTorqueAccount.getAddress(), ethers.parseUnits("1000000", 6));
    await mockTorqueAccount.setValidAccount(await customer.getAddress(), 1, true);
    await mockTorqueAccount.setValidAccount(await customer2.getAddress(), 1, true);
    await mockTorqueAccount.setBalance(await customer.getAddress(), 1, PAYMENT_AMOUNT * 10n);
    await mockTorqueAccount.setBalance(await customer2.getAddress(), 1, PAYMENT_AMOUNT * 10n);

    // Authorize merchant
    await torquePayments.setMerchantAuthorization(await merchant.getAddress(), true);
    await torqueGateway.setMerchantConfig(
      await merchant.getAddress(),
      ethers.parseUnits("0.001", 6), // 0.001 TUSD minimum
      0, // 0% fee
      true, // allow cross-chain
      false // don't require account verification
    );
  });

  describe("TorquePayments", function () {
    it("Should create a payment successfully", async function () {
      const paymentRequest = {
        payee: await merchant.getAddress(),
        amount: PAYMENT_AMOUNT,
        currency: await mockUSDC.getAddress(),
        paymentType: 2, // CRYPTO_TO_CRYPTO
        settlementMethod: 0, // INSTANT
        expiresAt: Math.floor(Date.now() / 1000) + 3600,
        description: "Test payment",
        metadata: "0x"
      };

      const tx = await torquePayments.connect(customer).createPayment(paymentRequest, 1);
      const receipt = await tx.wait();
      
      const event = receipt?.logs.find(log => 
        log.topics[0] === torquePayments.interface.getEventTopic("PaymentCreated")
      );
      expect(event).to.not.be.undefined;
    });

    it("Should process a payment successfully", async function () {
      // Create payment first
      const paymentRequest = {
        payee: await merchant.getAddress(),
        amount: PAYMENT_AMOUNT,
        currency: await mockUSDC.getAddress(),
        paymentType: 2,
        settlementMethod: 0,
        expiresAt: Math.floor(Date.now() / 1000) + 3600,
        description: "Test payment",
        metadata: "0x"
      };

      const createTx = await torquePayments.connect(customer).createPayment(paymentRequest, 1);
      const createReceipt = await createTx.wait();
      
      const createEvent = createReceipt?.logs.find(log => 
        log.topics[0] === torquePayments.interface.getEventTopic("PaymentCreated")
      );
      const paymentId = createEvent?.topics[1];

      // Process payment
      const processTx = await torquePayments.connect(customer).processPayment(paymentId!, 1);
      const processReceipt = await processTx.wait();
      
      const processEvent = processReceipt?.logs.find(log => 
        log.topics[0] === torquePayments.interface.getEventTopic("PaymentProcessed")
      );
      expect(processEvent).to.not.be.undefined;

      // Check payment status
      const payment = await torquePayments.getPayment(paymentId!);
      expect(payment.status).to.equal(2); // COMPLETED
    });

    it("Should create and process subscription", async function () {
      const subscriptionTx = await torquePayments.connect(customer).createSubscription(
        await merchant.getAddress(),
        SUBSCRIPTION_AMOUNT,
        await mockUSDC.getAddress(),
        86400, // 1 day interval
        12, // 12 billing cycles
        "Test subscription",
        1
      );

      const receipt = await subscriptionTx.wait();
      const event = receipt?.logs.find(log => 
        log.topics[0] === torquePayments.interface.getEventTopic("SubscriptionCreated")
      );
      expect(event).to.not.be.undefined;

      const subscriptionId = event?.topics[1];
      const subscription = await torquePayments.getSubscription(subscriptionId!);
      expect(subscription.active).to.be.true;
    });

    it("Should create and pay invoice", async function () {
      const lineItems = [ethers.keccak256(ethers.toUtf8Bytes("item1"))];
      
      const invoiceTx = await torquePayments.connect(merchant).createInvoice(
        await customer.getAddress(),
        INVOICE_AMOUNT,
        await mockUSDC.getAddress(),
        Math.floor(Date.now() / 1000) + 86400, // Due in 1 day
        "Test invoice",
        lineItems
      );

      const createReceipt = await invoiceTx.wait();
      const createEvent = createReceipt?.logs.find(log => 
        log.topics[0] === torquePayments.interface.getEventTopic("InvoiceCreated")
      );
      const invoiceId = createEvent?.topics[1];

      // Pay invoice
      const payTx = await torquePayments.connect(customer).payInvoice(invoiceId!, 1);
      const payReceipt = await payTx.wait();
      
      const payEvent = payReceipt?.logs.find(log => 
        log.topics[0] === torquePayments.interface.getEventTopic("InvoicePaid")
      );
      expect(payEvent).to.not.be.undefined;

      const invoice = await torquePayments.getInvoice(invoiceId!);
      expect(invoice.paid).to.be.true;
    });

    it("Should refund a payment", async function () {
      // Create and process payment first
      const paymentRequest = {
        payee: await merchant.getAddress(),
        amount: PAYMENT_AMOUNT,
        currency: await mockUSDC.getAddress(),
        paymentType: 2,
        settlementMethod: 0,
        expiresAt: Math.floor(Date.now() / 1000) + 3600,
        description: "Test payment",
        metadata: "0x"
      };

      const createTx = await torquePayments.connect(customer).createPayment(paymentRequest, 1);
      const createReceipt = await createTx.wait();
      const paymentId = createReceipt?.logs.find(log => 
        log.topics[0] === torquePayments.interface.getEventTopic("PaymentCreated")
      )?.topics[1];

      await torquePayments.connect(customer).processPayment(paymentId!, 1);

      // Refund payment
      const refundTx = await torquePayments.connect(merchant).refundPayment(paymentId!, 1);
      const refundReceipt = await refundTx.wait();
      
      const refundEvent = refundReceipt?.logs.find(log => 
        log.topics[0] === torquePayments.interface.getEventTopic("PaymentRefunded")
      );
      expect(refundEvent).to.not.be.undefined;

      const payment = await torquePayments.getPayment(paymentId!);
      expect(payment.status).to.equal(5); // REFUNDED
    });
  });

  describe("TorqueGateway", function () {
    it("Should create payment session", async function () {
      const sessionTx = await torqueGateway.connect(merchant).createPaymentSession(
        await customer.getAddress(),
        PAYMENT_AMOUNT,
        await mockUSDC.getAddress(),
        "https://example.com/success",
        "0x"
      );

      const receipt = await sessionTx.wait();
      const event = receipt?.logs.find(log => 
        log.topics[0] === torqueGateway.interface.getEventTopic("PaymentSessionCreated")
      );
      expect(event).to.not.be.undefined;

      const sessionId = event?.topics[1];
      const session = await torqueGateway.getPaymentSession(sessionId!);
      expect(session.merchant).to.equal(await merchant.getAddress());
      expect(session.customer).to.equal(await customer.getAddress());
      expect(session.amount).to.equal(PAYMENT_AMOUNT);
    });

    it("Should process payment session", async function () {
      // Create session first
      const sessionTx = await torqueGateway.connect(merchant).createPaymentSession(
        await customer.getAddress(),
        PAYMENT_AMOUNT,
        await mockUSDC.getAddress(),
        "https://example.com/success",
        "0x"
      );

      const createReceipt = await sessionTx.wait();
      const sessionId = createReceipt?.logs.find(log => 
        log.topics[0] === torquePaymentGateway.interface.getEventTopic("PaymentSessionCreated")
      )?.topics[1];

      // Process session
      const processTx = await torquePaymentGateway.connect(customer).processPaymentSession(
        sessionId!,
        1,
        "0x" // Empty signature since KYC not required
      );

      const processReceipt = await processTx.wait();
      const processEvent = processReceipt?.logs.find(log => 
        log.topics[0] === torquePaymentGateway.interface.getEventTopic("PaymentSessionCompleted")
      );
      expect(processEvent).to.not.be.undefined;

      const session = await torquePaymentGateway.getPaymentSession(sessionId!);
      expect(session.completed).to.be.true;
    });

    it("Should handle merchant balance withdrawal", async function () {
      // First create and process a payment to generate balance
      const sessionTx = await torquePaymentGateway.connect(merchant).createPaymentSession(
        await customer.getAddress(),
        PAYMENT_AMOUNT,
        await mockUSDC.getAddress(),
        "https://example.com/success",
        "0x"
      );

      const createReceipt = await sessionTx.wait();
      const sessionId = createReceipt?.logs.find(log => 
        log.topics[0] === torquePaymentGateway.interface.getEventTopic("PaymentSessionCreated")
      )?.topics[1];

      await torquePaymentGateway.connect(customer).processPaymentSession(sessionId!, 1, "0x");

      // Check balance
      const balance = await torquePaymentGateway.getMerchantBalance(await merchant.getAddress());
      expect(balance).to.be.gt(0);

      // Withdraw balance
      const withdrawTx = await torquePaymentGateway.connect(merchant).withdrawBalance(balance);
      await expect(withdrawTx).to.not.be.reverted;

      const newBalance = await torquePaymentGateway.getMerchantBalance(await merchant.getAddress());
      expect(newBalance).to.equal(0);
    });
  });

  describe("TorqueMerchant", function () {
    it("Should update merchant statistics", async function () {
      // First authorize analytics
      await torqueMerchants.setAnalyticsAuthorization(await merchant.getAddress(), true);

      // Create and process a payment
      const paymentRequest = {
        payee: await merchant.getAddress(),
        amount: PAYMENT_AMOUNT,
        currency: await mockUSDC.getAddress(),
        paymentType: 2,
        settlementMethod: 0,
        expiresAt: Math.floor(Date.now() / 1000) + 3600,
        description: "Test payment",
        metadata: "0x"
      };

      await torquePayments.connect(customer).createPayment(paymentRequest, 1);
      const paymentId = await torquePayments.getUserPayments(await customer.getAddress());
      await torquePayments.connect(customer).processPayment(paymentId[0], 1);

      // Update stats
      const statsTx = await torqueMerchants.updateMerchantStats(await merchant.getAddress());
      await expect(statsTx).to.not.be.reverted;

      const stats = await torqueMerchants.getMerchantStats(await merchant.getAddress());
      expect(stats.totalPayments).to.be.gt(0);
      expect(stats.totalVolume).to.be.gt(0);
    });

    it("Should generate revenue report", async function () {
      await torqueMerchants.setAnalyticsAuthorization(await merchant.getAddress(), true);

      const periodStart = Math.floor(Date.now() / 1000) - 86400; // 1 day ago
      const periodEnd = Math.floor(Date.now() / 1000);

      const reportTx = await torqueMerchants.generateRevenueReport(
        await merchant.getAddress(),
        periodStart,
        periodEnd
      );

      const receipt = await reportTx.wait();
      const event = receipt?.logs.find(log => 
        log.topics[0] === torqueMerchants.interface.getEventTopic("RevenueReportGenerated")
      );
      expect(event).to.not.be.undefined;
    });

    it("Should create and resolve dispute", async function () {
      // Create and process a payment first
      const paymentRequest = {
        payee: await merchant.getAddress(),
        amount: PAYMENT_AMOUNT,
        currency: await mockUSDC.getAddress(),
        paymentType: 2,
        settlementMethod: 0,
        expiresAt: Math.floor(Date.now() / 1000) + 3600,
        description: "Test payment",
        metadata: "0x"
      };

      await torquePayments.connect(customer).createPayment(paymentRequest, 1);
      const paymentId = await torquePayments.getUserPayments(await customer.getAddress());
      await torquePayments.connect(customer).processPayment(paymentId[0], 1);

      // Create dispute
      const disputeTx = await torqueMerchants.connect(customer).createDispute(
        paymentId[0],
        "Test dispute reason"
      );

      const createReceipt = await disputeTx.wait();
      const createEvent = createReceipt?.logs.find(log => 
        log.topics[0] === torqueMerchants.interface.getEventTopic("DisputeCreated")
      );
      const disputeId = createEvent?.topics[1];

      // Resolve dispute
      const resolveTx = await torqueMerchants.connect(owner).resolveDispute(
        disputeId!,
        "Dispute resolved in favor of customer"
      );

      const resolveReceipt = await resolveTx.wait();
      const resolveEvent = resolveReceipt?.logs.find(log => 
        log.topics[0] === torqueMerchants.interface.getEventTopic("DisputeResolved")
      );
      expect(resolveEvent).to.not.be.undefined;

      const dispute = await torqueMerchants.getDispute(disputeId!);
      expect(dispute.resolved).to.be.true;
    });
  });

  describe("Integration Tests", function () {
    it("Should handle complete payment flow through all contracts", async function () {
      // 1. Create payment session via gateway
      const sessionTx = await torquePaymentGateway.connect(merchant).createPaymentSession(
        await customer.getAddress(),
        PAYMENT_AMOUNT,
        await mockUSDC.getAddress(),
        "https://example.com/success",
        "0x"
      );

      const sessionId = (await sessionTx.wait())?.logs.find(log => 
        log.topics[0] === torquePaymentGateway.interface.getEventTopic("PaymentSessionCreated")
      )?.topics[1];

      // 2. Process payment session
      await torquePaymentGateway.connect(customer).processPaymentSession(sessionId!, 1, "0x");

      // 3. Verify payment was created in TorquePayments
      const session = await torquePaymentGateway.getPaymentSession(sessionId!);
      expect(session.completed).to.be.true;
      expect(session.paymentId).to.not.equal(ethers.ZeroHash);

      // 4. Check payment details
      const payment = await torquePayments.getPayment(session.paymentId);
      expect(payment.status).to.equal(2); // COMPLETED
      expect(payment.payer).to.equal(await customer.getAddress());
      expect(payment.payee).to.equal(await merchant.getAddress());

      // 5. Update analytics
      await torqueMerchants.setAnalyticsAuthorization(await merchant.getAddress(), true);
      await torqueMerchants.updateMerchantStats(await merchant.getAddress());

      const stats = await torqueMerchants.getMerchantStats(await merchant.getAddress());
      expect(stats.totalPayments).to.be.gt(0);
      expect(stats.successfulPayments).to.be.gt(0);
    });

    it("Should handle subscription billing flow", async function () {
      // 1. Create subscription
      const subscriptionTx = await torquePayments.connect(customer).createSubscription(
        await merchant.getAddress(),
        SUBSCRIPTION_AMOUNT,
        await mockUSDC.getAddress(),
        60, // 1 minute interval for testing
        3, // 3 billing cycles
        "Test subscription",
        1
      );

      const subscriptionId = (await subscriptionTx.wait())?.logs.find(log => 
        log.topics[0] === torquePayments.interface.getEventTopic("SubscriptionCreated")
      )?.topics[1];

      // 2. Process billing (simulate time passing)
      await ethers.provider.send("evm_increaseTime", [61]); // Increase time by 61 seconds
      await ethers.provider.send("evm_mine", []);

      const billingTx = await torquePayments.connect(customer).processSubscriptionBilling(subscriptionId!, 1);
      await expect(billingTx).to.not.be.reverted;

      // 3. Check subscription status
      const subscription = await torquePayments.getSubscription(subscriptionId!);
      expect(subscription.currentBillingCycle).to.equal(1);
      expect(subscription.active).to.be.true;
    });
  });

  describe("Access Control", function () {
    it("Should only allow authorized merchants to create payments", async function () {
      const unauthorizedMerchant = customer2;
      
      const paymentRequest = {
        payee: await unauthorizedMerchant.getAddress(),
        amount: PAYMENT_AMOUNT,
        currency: await mockUSDC.getAddress(),
        paymentType: 2,
        settlementMethod: 0,
        expiresAt: Math.floor(Date.now() / 1000) + 3600,
        description: "Test payment",
        metadata: "0x"
      };

      await expect(
        torquePayments.connect(customer).createPayment(paymentRequest, 1)
      ).to.be.revertedWith("Payee not authorized");
    });

    it("Should only allow payment owner to process payment", async function () {
      const paymentRequest = {
        payee: await merchant.getAddress(),
        amount: PAYMENT_AMOUNT,
        currency: await mockUSDC.getAddress(),
        paymentType: 2,
        settlementMethod: 0,
        expiresAt: Math.floor(Date.now() / 1000) + 3600,
        description: "Test payment",
        metadata: "0x"
      };

      await torquePayments.connect(customer).createPayment(paymentRequest, 1);
      const paymentId = await torquePayments.getUserPayments(await customer.getAddress());

      await expect(
        torquePayments.connect(customer2).processPayment(paymentId[0], 1)
      ).to.be.revertedWith("Not payment owner");
    });

    it("Should only allow merchant to refund their payments", async function () {
      const paymentRequest = {
        payee: await merchant.getAddress(),
        amount: PAYMENT_AMOUNT,
        currency: await mockUSDC.getAddress(),
        paymentType: 2,
        settlementMethod: 0,
        expiresAt: Math.floor(Date.now() / 1000) + 3600,
        description: "Test payment",
        metadata: "0x"
      };

      await torquePayments.connect(customer).createPayment(paymentRequest, 1);
      const paymentId = await torquePayments.getUserPayments(await customer.getAddress());
      await torquePayments.connect(customer).processPayment(paymentId[0], 1);

      await expect(
        torquePayments.connect(customer2).refundPayment(paymentId[0], 1)
      ).to.be.revertedWith("Not payment payee");
    });
  });
}); 