import { expect } from "chai";
import { ethers } from "hardhat";
import { Contract, ContractFactory, Signer, BigNumber } from "ethers";

describe("TorquePayments BNPL", function () {
  let TorquePayments: ContractFactory;
  let TorqueAccount: ContractFactory;
  let TorqueUSDFactory: ContractFactory;
  let TorqueEURFactory: ContractFactory;
  let payments: Contract;
  let accountContract: Contract;
  let torqueUSD: Contract;
  let torqueEUR: Contract;
  let owner: Signer;
  let buyer: Signer;
  let merchant: Signer;
  let user1: Signer;
  let user2: Signer;
  let ownerAddress: string;
  let buyerAddress: string;
  let merchantAddress: string;
  let user1Address: string;
  let user2Address: string;

  const MIN_BNPL_AMOUNT = ethers.utils.parseUnits("0.01", 18); // 0.01 TUSD
  const MAX_BNPL_AMOUNT = ethers.utils.parseUnits("1000", 18); // 1000 TUSD
  const MIN_DOWN_PAYMENT_PERCENT = 10; // 10%
  const MAX_INSTALLMENT_COUNT = 12;

  beforeEach(async function () {
    [owner, buyer, merchant, user1, user2] = await ethers.getSigners();
    ownerAddress = await owner.getAddress();
    buyerAddress = await buyer.getAddress();
    merchantAddress = await merchant.getAddress();
    user1Address = await user1.getAddress();
    user2Address = await user2.getAddress();

    // Deploy Torque currencies
    TorqueUSDFactory = await ethers.getContractFactory("TorqueUSD");
    TorqueEURFactory = await ethers.getContractFactory("TorqueEUR");
    
    // Mock LayerZero endpoint for testing
    const mockLzEndpoint = "0x0000000000000000000000000000000000000000";
    
    torqueUSD = await TorqueUSDFactory.deploy("Torque USD", "TUSD", mockLzEndpoint);
    torqueEUR = await TorqueEURFactory.deploy("Torque EUR", "TEUR", mockLzEndpoint);

    // Deploy TorqueAccount contract
    TorqueAccount = await ethers.getContractFactory("TorqueAccount");
    accountContract = await TorqueAccount.deploy();

    // Deploy TorquePayments contract
    TorquePayments = await ethers.getContractFactory("TorquePayments");
    payments = await TorquePayments.deploy(accountContract.address, torqueUSD.address, mockLzEndpoint);

    // Setup initial state - use correct function name and Torque currencies
    await payments.setSupportedTorqueCurrency(torqueUSD.address, true);
    await payments.setSupportedTorqueCurrency(torqueEUR.address, true);
    await payments.setMerchantAuthorization(merchantAddress, true);
    await payments.setBNPLEnabledMerchant(merchantAddress, true);

    // Mint Torque currencies to buyer
    await torqueUSD.mint(buyerAddress, ethers.utils.parseUnits("10000", 18));
    await torqueEUR.mint(buyerAddress, ethers.utils.parseUnits("10000", 18));
  });

  describe("BNPL Agreement Creation", function () {
    it("Should create BNPL agreement successfully", async function () {
      const request = {
        merchant: merchantAddress,
        totalAmount: ethers.utils.parseUnits("100", 18), // 100 TUSD
        downPayment: ethers.utils.parseUnits("10", 18), // 10 TUSD (10%)
        currency: torqueUSD.address,
        schedule: 2, // MONTHLY
        installmentCount: 6,
        defaultThreshold: 30,
        expiresAt: (await ethers.provider.getBlock("latest")).timestamp + 86400,
        description: "Electronics Purchase",
        metadata: "0x"
      };

      await expect(payments.connect(buyer).createBNPLAgreement(request, 0))
        .to.emit(payments, "BNPLAgreementCreated")
        .withArgs(ethers.utils.hexZeroPad("0x1", 32), buyerAddress, merchantAddress, ethers.utils.parseUnits("100", 18));

      const agreements = await payments.getUserBNPLAgreements(buyerAddress);
      expect(agreements.length).to.equal(1);
    });

    it("Should fail if merchant not authorized", async function () {
      await payments.setMerchantAuthorization(merchantAddress, false);

      const request = {
        merchant: merchantAddress,
        totalAmount: ethers.utils.parseUnits("100", 18),
        downPayment: ethers.utils.parseUnits("10", 18),
        currency: torqueUSD.address,
        schedule: 2,
        installmentCount: 6,
        defaultThreshold: 30,
        expiresAt: (await ethers.provider.getBlock("latest")).timestamp + 86400,
        description: "Test Purchase",
        metadata: "0x"
      };

      await expect(payments.connect(buyer).createBNPLAgreement(request, 0))
        .to.be.revertedWith("Merchant not authorized");
    });

    it("Should fail if BNPL not enabled for merchant", async function () {
      await payments.setBNPLEnabledMerchant(merchantAddress, false);

      const request = {
        merchant: merchantAddress,
        totalAmount: ethers.utils.parseUnits("100", 18),
        downPayment: ethers.utils.parseUnits("10", 18),
        currency: torqueUSD.address,
        schedule: 2,
        installmentCount: 6,
        defaultThreshold: 30,
        expiresAt: (await ethers.provider.getBlock("latest")).timestamp + 86400,
        description: "Test Purchase",
        metadata: "0x"
      };

      await expect(payments.connect(buyer).createBNPLAgreement(request, 0))
        .to.be.revertedWith("BNPL not enabled for merchant");
    });

    it("Should fail if amount too small", async function () {
      const request = {
        merchant: merchantAddress,
        totalAmount: ethers.utils.parseUnits("0.005", 18), // Below minimum
        downPayment: ethers.utils.parseUnits("0.001", 18),
        currency: torqueUSD.address,
        schedule: 2,
        installmentCount: 6,
        defaultThreshold: 30,
        expiresAt: (await ethers.provider.getBlock("latest")).timestamp + 86400,
        description: "Test Purchase",
        metadata: "0x"
      };

      await expect(payments.connect(buyer).createBNPLAgreement(request, 0))
        .to.be.revertedWith("Amount too small for BNPL");
    });

    it("Should fail if amount too large", async function () {
      const request = {
        merchant: merchantAddress,
        totalAmount: ethers.utils.parseUnits("2000", 18), // Above maximum
        downPayment: ethers.utils.parseUnits("200", 18),
        currency: torqueUSD.address,
        schedule: 2,
        installmentCount: 6,
        defaultThreshold: 30,
        expiresAt: (await ethers.provider.getBlock("latest")).timestamp + 86400,
        description: "Test Purchase",
        metadata: "0x"
      };

      await expect(payments.connect(buyer).createBNPLAgreement(request, 0))
        .to.be.revertedWith("Amount too large for BNPL");
    });

    it("Should fail if down payment too small", async function () {
      const request = {
        merchant: merchantAddress,
        totalAmount: ethers.utils.parseUnits("100", 18),
        downPayment: ethers.utils.parseUnits("5", 18), // 5% (below 10% minimum)
        currency: torqueUSD.address,
        schedule: 2,
        installmentCount: 6,
        defaultThreshold: 30,
        expiresAt: (await ethers.provider.getBlock("latest")).timestamp + 86400,
        description: "Test Purchase",
        metadata: "0x"
      };

      await expect(payments.connect(buyer).createBNPLAgreement(request, 0))
        .to.be.revertedWith("Down payment too small");
    });

    it("Should fail if too many installments", async function () {
      const request = {
        merchant: merchantAddress,
        totalAmount: ethers.utils.parseUnits("100", 18),
        downPayment: ethers.utils.parseUnits("10", 18),
        currency: torqueUSD.address,
        schedule: 2,
        installmentCount: 15, // Above maximum of 12
        defaultThreshold: 30,
        expiresAt: (await ethers.provider.getBlock("latest")).timestamp + 86400,
        description: "Test Purchase",
        metadata: "0x"
      };

      await expect(payments.connect(buyer).createBNPLAgreement(request, 0))
        .to.be.revertedWith("Too many installments");
    });

    it("Should fail if currency not supported", async function () {
      const request = {
        merchant: merchantAddress,
        totalAmount: ethers.utils.parseUnits("100", 18),
        downPayment: ethers.utils.parseUnits("10", 18),
        currency: user1Address, // Invalid currency
        schedule: 2,
        installmentCount: 6,
        defaultThreshold: 30,
        expiresAt: (await ethers.provider.getBlock("latest")).timestamp + 86400,
        description: "Test Purchase",
        metadata: "0x"
      };

      await expect(payments.connect(buyer).createBNPLAgreement(request, 0))
        .to.be.revertedWith("Only Torque currencies supported");
    });
  });

  describe("BNPL Agreement Activation", function () {
    let bnplId: string;
    let request: any;

    beforeEach(async function () {
      request = {
        merchant: merchantAddress,
        totalAmount: ethers.utils.parseUnits("100", 18),
        downPayment: ethers.utils.parseUnits("10", 18),
        currency: torqueUSD.address,
        schedule: 2, // MONTHLY
        installmentCount: 6,
        defaultThreshold: 30,
        expiresAt: (await ethers.provider.getBlock("latest")).timestamp + 86400,
        description: "Electronics Purchase",
        metadata: "0x"
      };

      const tx = await payments.connect(buyer).createBNPLAgreement(request, 0);
      const receipt = await tx.wait();
      const event = receipt.events?.find((e: any) => e.event === "BNPLAgreementCreated");
      bnplId = event?.args?.bnplId;
    });

    it("Should activate BNPL agreement successfully", async function () {
      const initialBalance = await torqueUSD.balanceOf(buyerAddress);

      await torqueUSD.connect(buyer).approve(payments.address, ethers.utils.parseUnits("10", 18));

      await expect(payments.connect(buyer).activateBNPLAgreement(bnplId, 0))
        .to.emit(payments, "BNPLAgreementActivated")
        .withArgs(bnplId, buyerAddress, ethers.utils.parseUnits("100", 18));

      const agreement = await payments.getBNPLAgreement(bnplId);
      expect(agreement.status).to.equal(1); // ACTIVE
      expect(agreement.activatedAt).to.be.gt(0);

      // Check down payment was transferred
      expect(await torqueUSD.balanceOf(buyerAddress)).to.equal(initialBalance.sub(ethers.utils.parseUnits("10", 18)));
    });

    it("Should fail if insufficient balance", async function () {
      await expect(payments.connect(user1).activateBNPLAgreement(bnplId, 0))
        .to.be.revertedWith("Insufficient balance");
    });

    it("Should fail if not agreement owner", async function () {
      await torqueUSD.connect(buyer).approve(payments.address, ethers.utils.parseUnits("10", 18));

      await expect(payments.connect(user1).activateBNPLAgreement(bnplId, 0))
        .to.be.revertedWith("Not agreement owner");
    });

    it("Should fail if agreement already activated", async function () {
      await torqueUSD.connect(buyer).approve(payments.address, ethers.utils.parseUnits("10", 18));
      await payments.connect(buyer).activateBNPLAgreement(bnplId, 0);

      await expect(payments.connect(buyer).activateBNPLAgreement(bnplId, 0))
        .to.be.revertedWith("Agreement not pending");
    });
  });

  describe("BNPL Installment Payments", function () {
    let bnplId: string;
    let request: any;

    beforeEach(async function () {
      request = {
        merchant: merchantAddress,
        totalAmount: ethers.utils.parseUnits("100", 18),
        downPayment: ethers.utils.parseUnits("10", 18),
        currency: torqueUSD.address,
        schedule: 2, // MONTHLY
        installmentCount: 6,
        defaultThreshold: 30,
        expiresAt: (await ethers.provider.getBlock("latest")).timestamp + 86400,
        description: "Electronics Purchase",
        metadata: "0x"
      };

      const tx = await payments.connect(buyer).createBNPLAgreement(request, 0);
      const receipt = await tx.wait();
      const event = receipt.events?.find((e: any) => e.event === "BNPLAgreementCreated");
      bnplId = event?.args?.bnplId;

      // Activate the agreement
      await torqueUSD.connect(buyer).approve(payments.address, ethers.utils.parseUnits("10", 18));
      await payments.connect(buyer).activateBNPLAgreement(bnplId, 0);
    });

    it("Should pay installment successfully", async function () {
      const agreement = await payments.getBNPLAgreement(bnplId);
      const installmentAmount = agreement.installmentAmount;
      const initialBalance = await torqueUSD.balanceOf(buyerAddress);

      await torqueUSD.connect(buyer).approve(payments.address, installmentAmount);

      await expect(payments.connect(buyer).payBNPLInstallment(bnplId, 1, 0))
        .to.emit(payments, "BNPLInstallmentPaid")
        .withArgs(bnplId, 1, installmentAmount);

      // Check installment was paid
      const installment = await payments.getBNPLInstallment(bnplId, 1);
      expect(installment.paid).to.be.true;
      expect(installment.paidAt).to.be.gt(0);

      // Check balance was reduced
      expect(await torqueUSD.balanceOf(buyerAddress)).to.equal(initialBalance.sub(installmentAmount));
    });

    it("Should fail if installment already paid", async function () {
      const agreement = await payments.getBNPLAgreement(bnplId);
      const installmentAmount = agreement.installmentAmount;

      await torqueUSD.connect(buyer).approve(payments.address, installmentAmount);
      await payments.connect(buyer).payBNPLInstallment(bnplId, 1, 0);

      await expect(payments.connect(buyer).payBNPLInstallment(bnplId, 1, 0))
        .to.be.revertedWith("Installment already paid");
    });

    it("Should fail if not agreement owner", async function () {
      const agreement = await payments.getBNPLAgreement(bnplId);
      const installmentAmount = agreement.installmentAmount;

      await torqueUSD.connect(buyer).approve(payments.address, installmentAmount);

      await expect(payments.connect(user1).payBNPLInstallment(bnplId, 1, 0))
        .to.be.revertedWith("Not agreement owner");
    });

    it("Should complete agreement after all installments", async function () {
      const agreement = await payments.getBNPLAgreement(bnplId);
      const installmentAmount = agreement.installmentAmount;

      // Pay all installments
      for (let i = 1; i <= 6; i++) {
        await torqueUSD.connect(buyer).approve(payments.address, installmentAmount);
        await payments.connect(buyer).payBNPLInstallment(bnplId, i, 0);
      }

      const finalAgreement = await payments.getBNPLAgreement(bnplId);
      expect(finalAgreement.status).to.equal(2); // PAID
      expect(finalAgreement.completedAt).to.be.gt(0);
    });
  });

  describe("BNPL Default Handling", function () {
    let bnplId: string;
    let request: any;

    beforeEach(async function () {
      request = {
        merchant: merchantAddress,
        totalAmount: ethers.utils.parseUnits("100", 18),
        downPayment: ethers.utils.parseUnits("10", 18),
        currency: torqueUSD.address,
        schedule: 2, // MONTHLY
        installmentCount: 6,
        defaultThreshold: 30,
        expiresAt: (await ethers.provider.getBlock("latest")).timestamp + 86400,
        description: "Electronics Purchase",
        metadata: "0x"
      };

      const tx = await payments.connect(buyer).createBNPLAgreement(request, 0);
      const receipt = await tx.wait();
      const event = receipt.events?.find((e: any) => e.event === "BNPLAgreementCreated");
      bnplId = event?.args?.bnplId;

      // Activate the agreement
      await torqueUSD.connect(buyer).approve(payments.address, ethers.utils.parseUnits("10", 18));
      await payments.connect(buyer).activateBNPLAgreement(bnplId, 0);
    });

    it("Should mark agreement as defaulted after threshold", async function () {
      const agreement = await payments.getBNPLAgreement(bnplId);
      
      // Fast forward time past default threshold
      await ethers.provider.send("evm_increaseTime", [31 * 24 * 60 * 60]); // 31 days
      await ethers.provider.send("evm_mine", []);

      await expect(payments.connect(merchant).markBNPLDefaulted(bnplId))
        .to.emit(payments, "BNPLAgreementDefaulted")
        .withArgs(bnplId, buyerAddress, "Payment default");

      const defaultedAgreement = await payments.getBNPLAgreement(bnplId);
      expect(defaultedAgreement.status).to.equal(3); // DEFAULTED
    });

    it("Should fail if not merchant", async function () {
      await ethers.provider.send("evm_increaseTime", [31 * 24 * 60 * 60]);
      await ethers.provider.send("evm_mine", []);

      await expect(payments.connect(user1).markBNPLDefaulted(bnplId))
        .to.be.revertedWith("Not merchant");
    });

    it("Should fail if not past default threshold", async function () {
      await expect(payments.connect(merchant).markBNPLDefaulted(bnplId))
        .to.be.revertedWith("Not past default threshold");
    });
  });

  describe("BNPL Statistics", function () {
    let bnplId: string;

    beforeEach(async function () {
      const request = {
        merchant: merchantAddress,
        totalAmount: ethers.utils.parseUnits("100", 18),
        downPayment: ethers.utils.parseUnits("10", 18),
        currency: torqueUSD.address,
        schedule: 2,
        installmentCount: 6,
        defaultThreshold: 30,
        expiresAt: (await ethers.provider.getBlock("latest")).timestamp + 86400,
        description: "Electronics Purchase",
        metadata: "0x"
      };

      const tx = await payments.connect(buyer).createBNPLAgreement(request, 0);
      const receipt = await tx.wait();
      const event = receipt.events?.find((e: any) => e.event === "BNPLAgreementCreated");
      bnplId = event?.args?.bnplId;
    });

    it("Should return user BNPL statistics", async function () {
      const stats = await payments.getUserBNPLStats(buyerAddress);
      expect(stats.totalAgreements).to.equal(1);
      expect(stats.totalAmount).to.equal(ethers.utils.parseUnits("100", 18));
      expect(stats.activeAgreements).to.equal(0);
      expect(stats.completedAgreements).to.equal(0);
      expect(stats.defaultedAgreements).to.equal(0);
    });

    it("Should return merchant BNPL statistics", async function () {
      const stats = await payments.getMerchantBNPLStats(merchantAddress);
      expect(stats.totalAgreements).to.equal(1);
      expect(stats.totalAmount).to.equal(ethers.utils.parseUnits("100", 18));
      expect(stats.activeAgreements).to.equal(0);
      expect(stats.completedAgreements).to.equal(0);
      expect(stats.defaultedAgreements).to.equal(0);
    });

    it("Should return BNPL agreement details", async function () {
      const agreement = await payments.getBNPLAgreement(bnplId);
      expect(agreement.buyer).to.equal(buyerAddress);
      expect(agreement.merchant).to.equal(merchantAddress);
      expect(agreement.totalAmount).to.equal(ethers.utils.parseUnits("100", 18));
      expect(agreement.downPayment).to.equal(ethers.utils.parseUnits("10", 18));
      expect(agreement.currency).to.equal(torqueUSD.address);
      expect(agreement.status).to.equal(0); // AUTHORIZED
    });
  });
}); 