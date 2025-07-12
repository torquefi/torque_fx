import { expect } from "chai";
import { ethers } from "hardhat";
import { Contract, ContractFactory, Signer, BigNumber } from "ethers";
import { parseUnits } from "ethers/lib/utils";

describe("TorquePayments Mass Payments", function () {
  let TorquePayments: ContractFactory;
  let TorqueUSDFactory: ContractFactory;
  let TorqueEURFactory: ContractFactory;
  let TorqueGBPFactory: ContractFactory;
  let payments: Contract;
  let torqueUSD: Contract;
  let torqueEUR: Contract;
  let torqueGBP: Contract;
  let owner: Signer;
  let payer: Signer;
  let recipient1: Signer;
  let recipient2: Signer;
  let recipient3: Signer;
  let user1: Signer;
  let user2: Signer;
  let ownerAddress: string;
  let payerAddress: string;
  let recipient1Address: string;
  let recipient2Address: string;
  let recipient3Address: string;
  let user1Address: string;
  let user2Address: string;

  const MAX_MASS_PAYMENT_RECIPIENTS = 1000;
  const MIN_MASS_PAYMENT_AMOUNT = ethers.utils.parseUnits("0.001", 18); // 0.001 TUSD (18 decimals)
  const MAX_MASS_PAYMENT_AMOUNT = ethers.utils.parseUnits("1000000", 18); // 1M TUSD
  const MASS_PAYMENT_BATCH_SIZE = 50;

  beforeEach(async function () {
    [owner, payer, recipient1, recipient2, recipient3, user1, user2] = await ethers.getSigners();
    ownerAddress = await owner.getAddress();
    payerAddress = await payer.getAddress();
    recipient1Address = await recipient1.getAddress();
    recipient2Address = await recipient2.getAddress();
    recipient3Address = await recipient3.getAddress();
    user1Address = await user1.getAddress();
    user2Address = await user2.getAddress();

    // Deploy Torque currencies
    TorqueUSDFactory = await ethers.getContractFactory("TorqueUSD");
    TorqueEURFactory = await ethers.getContractFactory("TorqueEUR");
    TorqueGBPFactory = await ethers.getContractFactory("TorqueGBP");
    
    // Mock LayerZero endpoint for testing
    const mockLzEndpoint = "0x0000000000000000000000000000000000000000";
    
    torqueUSD = await TorqueUSDFactory.deploy("Torque USD", "TUSD", mockLzEndpoint);
    torqueEUR = await TorqueEURFactory.deploy("Torque EUR", "TEUR", mockLzEndpoint);
    torqueGBP = await TorqueGBPFactory.deploy("Torque GBP", "TGBP", mockLzEndpoint);

    // Deploy TorquePayments contract
    TorquePayments = await ethers.getContractFactory("TorquePayments");
    payments = await TorquePayments.deploy(torqueUSD.address, mockLzEndpoint);

    // Setup initial state - use correct function name and Torque currencies
    await payments.setSupportedTorqueCurrency(torqueUSD.address, true);
    await payments.setSupportedTorqueCurrency(torqueEUR.address, true);
    await payments.setSupportedTorqueCurrency(torqueGBP.address, true);
    await payments.setMassPaymentEnabled(payerAddress, true);

    // Mint Torque currencies to payer
    await torqueUSD.mint(payerAddress, ethers.utils.parseUnits("100000", 18));
    await torqueEUR.mint(payerAddress, ethers.utils.parseUnits("100000", 18));
    await torqueGBP.mint(payerAddress, ethers.utils.parseUnits("100000", 18));
  });

  describe("Mass Payment Creation", function () {
    it("Should create a mass payment successfully", async function () {
      const totalAmount = ethers.utils.parseUnits("10000", 18); // 10,000 TUSD

      const request = {
        currency: torqueUSD.address,
        totalAmount: totalAmount,
        expiresAt: (await ethers.provider.getBlock("latest")).timestamp + 86400,
        description: "Q4 Contractor Payouts",
        metadata: "0x"
      };

      await expect(payments.connect(payer).createMassPayment(request, 0))
        .to.emit(payments, "MassPaymentCreated")
        .withArgs(ethers.utils.hexZeroPad("0x1", 32), payerAddress, torqueUSD.address, totalAmount, 0);

      const massPayments = await payments.getUserMassPayments(payerAddress);
      expect(massPayments.length).to.equal(1);
    });

    it("Should fail if mass payments not enabled", async function () {
      await payments.setMassPaymentEnabled(payerAddress, false);

      const request = {
        currency: torqueUSD.address,
        totalAmount: ethers.utils.parseUnits("10000", 18),
        expiresAt: (await ethers.provider.getBlock("latest")).timestamp + 86400,
        description: "Test Mass Payment",
        metadata: "0x"
      };

      await expect(payments.connect(payer).createMassPayment(request, 0))
        .to.be.revertedWith("Mass payments not enabled");
    });

    it("Should fail if amount is too small", async function () {
      const request = {
        currency: torqueUSD.address,
        totalAmount: ethers.utils.parseUnits("0.0005", 18), // Below minimum
        expiresAt: (await ethers.provider.getBlock("latest")).timestamp + 86400,
        description: "Test Mass Payment",
        metadata: "0x"
      };

      await expect(payments.connect(payer).createMassPayment(request, 0))
        .to.be.revertedWith("Amount too small for mass payment");
    });

    it("Should fail if amount is too large", async function () {
      const request = {
        currency: torqueUSD.address,
        totalAmount: ethers.utils.parseUnits("2000000", 18), // Above maximum
        expiresAt: (await ethers.provider.getBlock("latest")).timestamp + 86400,
        description: "Test Mass Payment",
        metadata: "0x"
      };

      await expect(payments.connect(payer).createMassPayment(request, 0))
        .to.be.revertedWith("Amount too large for mass payment");
    });

    it("Should fail if currency not supported", async function () {
      const request = {
        currency: user1Address, // Invalid currency
        totalAmount: ethers.utils.parseUnits("10000", 18),
        expiresAt: (await ethers.provider.getBlock("latest")).timestamp + 86400,
        description: "Test Mass Payment",
        metadata: "0x"
      };

      await expect(payments.connect(payer).createMassPayment(request, 0))
        .to.be.revertedWith("Only Torque currencies supported");
    });
  });

  describe("Mass Payment Recipients", function () {
    let massPaymentId: string;
    let request: any;

    beforeEach(async function () {
      request = {
        currency: torqueUSD.address,
        totalAmount: ethers.utils.parseUnits("10000", 18),
        expiresAt: (await ethers.provider.getBlock("latest")).timestamp + 86400,
        description: "Test Mass Payment",
        metadata: "0x"
      };

      const tx = await payments.connect(payer).createMassPayment(request, 0);
      const receipt = await tx.wait();
      const event = receipt.events?.find((e: any) => e.event === "MassPaymentCreated");
      massPaymentId = event?.args?.massPaymentId;
    });

    it("Should add recipients successfully", async function () {
      const recipients = [
        {
          recipient: recipient1Address,
          amount: ethers.utils.parseUnits("3000", 18),
          recipientType: 0, // CONTRACTOR
          description: "Web Development Services",
          metadata: "0x",
          processed: false,
          processedAt: 0,
          failureReason: ""
        },
        {
          recipient: recipient2Address,
          amount: ethers.utils.parseUnits("4000", 18),
          recipientType: 0, // CONTRACTOR
          description: "Design Services",
          metadata: "0x",
          processed: false,
          processedAt: 0,
          failureReason: ""
        },
        {
          recipient: recipient3Address,
          amount: ethers.utils.parseUnits("3000", 18),
          recipientType: 0, // CONTRACTOR
          description: "Marketing Services",
          metadata: "0x",
          processed: false,
          processedAt: 0,
          failureReason: ""
        }
      ];

      await expect(payments.connect(payer).addMassPaymentRecipients(massPaymentId, recipients))
        .to.emit(payments, "MassPaymentRecipientAdded")
        .withArgs(massPaymentId, recipient1Address, ethers.utils.parseUnits("3000", 18), 0);

      const massPayment = await payments.getMassPayment(massPaymentId);
      expect(massPayment.recipientCount).to.equal(3);
    });

    it("Should fail if not mass payment owner", async function () {
      const recipients = [
        {
          recipient: recipient1Address,
          amount: ethers.utils.parseUnits("3000", 18),
          recipientType: 0,
          description: "Test",
          metadata: "0x",
          processed: false,
          processedAt: 0,
          failureReason: ""
        }
      ];

      await expect(payments.connect(user1).addMassPaymentRecipients(massPaymentId, recipients))
        .to.be.revertedWith("Not mass payment owner");
    });

    it("Should fail if mass payment not pending", async function () {
      // First add recipients
      const recipients = [
        {
          recipient: recipient1Address,
          amount: ethers.utils.parseUnits("3000", 18),
          recipientType: 0,
          description: "Test",
          metadata: "0x",
          processed: false,
          processedAt: 0,
          failureReason: ""
        }
      ];
      await payments.connect(payer).addMassPaymentRecipients(massPaymentId, recipients);

      // Process the payment
      await torqueUSD.connect(payer).approve(payments.address, ethers.utils.parseUnits("3000", 18));
      await payments.connect(payer).processMassPayment(massPaymentId, 0);

      // Try to add more recipients
      const newRecipients = [
        {
          recipient: recipient2Address,
          amount: ethers.utils.parseUnits("1000", 18),
          recipientType: 0,
          description: "Test",
          metadata: "0x",
          processed: false,
          processedAt: 0,
          failureReason: ""
        }
      ];

      await expect(payments.connect(payer).addMassPaymentRecipients(massPaymentId, newRecipients))
        .to.be.revertedWith("Mass payment not pending");
    });

    it("Should fail if too many recipients", async function () {
      const recipients = [];
      for (let i = 0; i < MAX_MASS_PAYMENT_RECIPIENTS + 1; i++) {
        recipients.push({
          recipient: user1Address,
          amount: ethers.utils.parseUnits("10", 18),
          recipientType: 0,
          description: "Test",
          metadata: "0x",
          processed: false,
          processedAt: 0,
          failureReason: ""
        });
      }

      await expect(payments.connect(payer).addMassPaymentRecipients(massPaymentId, recipients))
        .to.be.revertedWith("Too many recipients");
    });

    it("Should fail if total amount exceeds mass payment amount", async function () {
      const recipients = [
        {
          recipient: recipient1Address,
          amount: ethers.utils.parseUnits("6000", 18), // 6,000 TUSD
          recipientType: 0,
          description: "Test",
          metadata: "0x",
          processed: false,
          processedAt: 0,
          failureReason: ""
        },
        {
          recipient: recipient2Address,
          amount: ethers.utils.parseUnits("6000", 18), // 6,000 TUSD (total 12,000 > 10,000)
          recipientType: 0,
          description: "Test",
          metadata: "0x",
          processed: false,
          processedAt: 0,
          failureReason: ""
        }
      ];

      await expect(payments.connect(payer).addMassPaymentRecipients(massPaymentId, recipients))
        .to.be.revertedWith("Total amount exceeds mass payment amount");
    });
  });

  describe("Mass Payment Processing", function () {
    let massPaymentId: string;
    let request: any;

    beforeEach(async function () {
      request = {
        currency: torqueUSD.address,
        totalAmount: ethers.utils.parseUnits("10000", 18),
        expiresAt: (await ethers.provider.getBlock("latest")).timestamp + 86400,
        description: "Test Mass Payment",
        metadata: "0x"
      };

      const tx = await payments.connect(payer).createMassPayment(request, 0);
      const receipt = await tx.wait();
      const event = receipt.events?.find((e: any) => e.event === "MassPaymentCreated");
      massPaymentId = event?.args?.massPaymentId;

      // Add recipients
      const recipients = [
        {
          recipient: recipient1Address,
          amount: ethers.utils.parseUnits("3000", 18),
          recipientType: 0,
          description: "Web Development",
          metadata: "0x",
          processed: false,
          processedAt: 0,
          failureReason: ""
        },
        {
          recipient: recipient2Address,
          amount: ethers.utils.parseUnits("4000", 18),
          recipientType: 0,
          description: "Design Services",
          metadata: "0x",
          processed: false,
          processedAt: 0,
          failureReason: ""
        },
        {
          recipient: recipient3Address,
          amount: ethers.utils.parseUnits("3000", 18),
          recipientType: 0,
          description: "Marketing",
          metadata: "0x",
          processed: false,
          processedAt: 0,
          failureReason: ""
        }
      ];

      await payments.connect(payer).addMassPaymentRecipients(massPaymentId, recipients);
    });

    it("Should process mass payment successfully", async function () {
      const initialBalance1 = await torqueUSD.balanceOf(recipient1Address);
      const initialBalance2 = await torqueUSD.balanceOf(recipient2Address);
      const initialBalance3 = await torqueUSD.balanceOf(recipient3Address);

      await torqueUSD.connect(payer).approve(payments.address, ethers.utils.parseUnits("10000", 18));

      await expect(payments.connect(payer).processMassPayment(massPaymentId, 0))
        .to.emit(payments, "MassPaymentCompleted")
        .withArgs(massPaymentId, payerAddress, 3, 0, await ethers.provider.getBlock("latest").then(b => b.timestamp));

      const massPayment = await payments.getMassPayment(massPaymentId);
      expect(massPayment.status).to.equal(2); // COMPLETED
      expect(massPayment.processedCount).to.equal(3);
      expect(massPayment.failedCount).to.equal(0);

      // Check recipient balances
      expect(await torqueUSD.balanceOf(recipient1Address)).to.equal(initialBalance1.add(ethers.utils.parseUnits("3000", 18)));
      expect(await torqueUSD.balanceOf(recipient2Address)).to.equal(initialBalance2.add(ethers.utils.parseUnits("4000", 18)));
      expect(await torqueUSD.balanceOf(recipient3Address)).to.equal(initialBalance3.add(ethers.utils.parseUnits("3000", 18)));
    });

    it("Should fail if insufficient balance", async function () {
      await expect(payments.connect(user1).processMassPayment(massPaymentId, 0))
        .to.be.revertedWith("Insufficient balance");
    });

    it("Should fail if not mass payment owner", async function () {
      await torqueUSD.connect(payer).approve(payments.address, ethers.utils.parseUnits("10000", 18));

      await expect(payments.connect(user1).processMassPayment(massPaymentId, 0))
        .to.be.revertedWith("Not mass payment owner");
    });

    it("Should fail if no recipients", async function () {
      // Create new mass payment without recipients
      const newRequest = {
        currency: torqueUSD.address,
        totalAmount: ethers.utils.parseUnits("1000", 18),
        expiresAt: (await ethers.provider.getBlock("latest")).timestamp + 86400,
        description: "Test",
        metadata: "0x"
      };

      const tx = await payments.connect(payer).createMassPayment(newRequest, 0);
      const receipt = await tx.wait();
      const event = receipt.events?.find((e: any) => e.event === "MassPaymentCreated");
      const newMassPaymentId = event?.args?.massPaymentId;

      await expect(payments.connect(payer).processMassPayment(newMassPaymentId, 0))
        .to.be.revertedWith("No recipients to process");
    });
  });

  describe("Mass Payment Batch Processing", function () {
    let massPaymentId: string;
    let request: any;

    beforeEach(async function () {
      request = {
        currency: torqueUSD.address,
        totalAmount: ethers.utils.parseUnits("100000", 18), // 100,000 TUSD
        expiresAt: (await ethers.provider.getBlock("latest")).timestamp + 86400,
        description: "Large Mass Payment",
        metadata: "0x"
      };

      const tx = await payments.connect(payer).createMassPayment(request, 0);
      const receipt = await tx.wait();
      const event = receipt.events?.find((e: any) => e.event === "MassPaymentCreated");
      massPaymentId = event?.args?.massPaymentId;

      // Add 100 recipients
      const recipients = [];
      for (let i = 0; i < 100; i++) {
        recipients.push({
          recipient: user1Address, // Using same address for simplicity
          amount: ethers.utils.parseUnits("1000", 18), // 1,000 TUSD each
          recipientType: 0,
          description: `Recipient ${i}`,
          metadata: "0x",
          processed: false,
          processedAt: 0,
          failureReason: ""
        });
      }

      await payments.connect(payer).addMassPaymentRecipients(massPaymentId, recipients);
    });

    it("Should process batch successfully", async function () {
      await expect(payments.connect(payer).processMassPaymentBatch(massPaymentId, 0))
        .to.emit(payments, "MassPaymentBatchProcessed")
        .withArgs(massPaymentId, ethers.utils.hexZeroPad("0x1", 32), 50, 0, ethers.utils.parseUnits("50000", 18));

      const massPayment = await payments.getMassPayment(massPaymentId);
      expect(massPayment.status).to.equal(1); // PROCESSING
      expect(massPayment.processedCount).to.equal(50);
    });
  });

  describe("Mass Payment Cancellation", function () {
    let massPaymentId: string;
    let request: any;

    beforeEach(async function () {
      request = {
        currency: torqueUSD.address,
        totalAmount: ethers.utils.parseUnits("10000", 18),
        expiresAt: (await ethers.provider.getBlock("latest")).timestamp + 86400,
        description: "Test Mass Payment",
        metadata: "0x"
      };

      const tx = await payments.connect(payer).createMassPayment(request, 0);
      const receipt = await tx.wait();
      const event = receipt.events?.find((e: any) => e.event === "MassPaymentCreated");
      massPaymentId = event?.args?.massPaymentId;
    });

    it("Should cancel mass payment successfully", async function () {
      await expect(payments.connect(payer).cancelMassPayment(massPaymentId))
        .to.emit(payments, "MassPaymentFailed")
        .withArgs(massPaymentId, payerAddress, "Cancelled by payer");

      const massPayment = await payments.getMassPayment(massPaymentId);
      expect(massPayment.status).to.equal(4); // CANCELLED
    });

    it("Should fail if not mass payment owner", async function () {
      await expect(payments.connect(user1).cancelMassPayment(massPaymentId))
        .to.be.revertedWith("Not mass payment owner");
    });

    it("Should fail if mass payment already processed", async function () {
      // Add recipients and process
      const recipients = [
        {
          recipient: recipient1Address,
          amount: ethers.utils.parseUnits("10000", 18),
          recipientType: 0,
          description: "Test",
          metadata: "0x",
          processed: false,
          processedAt: 0,
          failureReason: ""
        }
      ];

      await payments.connect(payer).addMassPaymentRecipients(massPaymentId, recipients);
      await torqueUSD.connect(payer).approve(payments.address, ethers.utils.parseUnits("10000", 18));
      await payments.connect(payer).processMassPayment(massPaymentId, 0);

      await expect(payments.connect(payer).cancelMassPayment(massPaymentId))
        .to.be.revertedWith("Mass payment already processed");
    });
  });

  describe("Mass Payment Statistics", function () {
    let massPaymentId: string;

    beforeEach(async function () {
      const request = {
        currency: torqueUSD.address,
        totalAmount: ethers.utils.parseUnits("10000", 18),
        expiresAt: (await ethers.provider.getBlock("latest")).timestamp + 86400,
        description: "Test Mass Payment",
        metadata: "0x"
      };

      const tx = await payments.connect(payer).createMassPayment(request, 0);
      const receipt = await tx.wait();
      const event = receipt.events?.find((e: any) => e.event === "MassPaymentCreated");
      massPaymentId = event?.args?.massPaymentId;

      // Add recipients
      const recipients = [
        {
          recipient: recipient1Address,
          amount: ethers.utils.parseUnits("3000", 18),
          recipientType: 0, // CONTRACTOR
          description: "Web Development",
          metadata: "0x",
          processed: false,
          processedAt: 0,
          failureReason: ""
        },
        {
          recipient: recipient2Address,
          amount: ethers.utils.parseUnits("4000", 18),
          recipientType: 1, // FREELANCER
          description: "Design Services",
          metadata: "0x",
          processed: false,
          processedAt: 0,
          failureReason: ""
        },
        {
          recipient: recipient3Address,
          amount: ethers.utils.parseUnits("3000", 18),
          recipientType: 2, // SELLER
          description: "Marketing",
          metadata: "0x",
          processed: false,
          processedAt: 0,
          failureReason: ""
        }
      ];

      await payments.connect(payer).addMassPaymentRecipients(massPaymentId, recipients);
    });

    it("Should return user mass payment statistics", async function () {
      const stats = await payments.getUserMassPaymentStats(payerAddress);
      expect(stats.totalPayments).to.equal(1);
      expect(stats.totalRecipients).to.equal(3);
      expect(stats.totalAmount).to.equal(ethers.utils.parseUnits("10000", 18));
      expect(stats.totalProcessed).to.equal(0);
      expect(stats.totalFailed).to.equal(0);
    });

    it("Should return recipient statistics", async function () {
      const stats = await payments.getRecipientStats(recipient1Address);
      expect(stats.totalReceived).to.equal(0); // Not processed yet
      expect(stats.paymentCount).to.equal(0);
      expect(stats.recipientTypeCounts[0]).to.equal(0); // CONTRACTOR count
    });

    it("Should return mass payment details", async function () {
      const massPayment = await payments.getMassPayment(massPaymentId);
      expect(massPayment.payer).to.equal(payerAddress);
      expect(massPayment.currency).to.equal(torqueUSD.address);
      expect(massPayment.totalAmount).to.equal(ethers.utils.parseUnits("10000", 18));
      expect(massPayment.recipientCount).to.equal(3);

      const recipients = await payments.getMassPaymentRecipients(massPaymentId);
      expect(recipients.length).to.equal(3);
      expect(recipients[0].recipient).to.equal(recipient1Address);
      expect(recipients[1].recipient).to.equal(recipient2Address);
      expect(recipients[2].recipient).to.equal(recipient3Address);
    });
  });

  describe("Multi-Currency Mass Payments", function () {
    it("Should support different Torque currencies", async function () {
      // Test with Torque EUR
      const request = {
        currency: torqueEUR.address,
        totalAmount: ethers.utils.parseUnits("5000", 18), // 5,000 TEUR
        expiresAt: (await ethers.provider.getBlock("latest")).timestamp + 86400,
        description: "European Team Payouts",
        metadata: "0x"
      };

      const tx = await payments.connect(payer).createMassPayment(request, 0);
      const receipt = await tx.wait();
      const event = receipt.events?.find((e: any) => e.event === "MassPaymentCreated");
      const massPaymentId = event?.args?.massPaymentId;

      const recipients = [
        {
          recipient: recipient1Address,
          amount: ethers.utils.parseUnits("2500", 18), // 2,500 TEUR
          recipientType: 0,
          description: "European Development",
          metadata: "0x",
          processed: false,
          processedAt: 0,
          failureReason: ""
        },
        {
          recipient: recipient2Address,
          amount: ethers.utils.parseUnits("2500", 18), // 2,500 TEUR
          recipientType: 0,
          description: "European Design",
          metadata: "0x",
          processed: false,
          processedAt: 0,
          failureReason: ""
        }
      ];

      await payments.connect(payer).addMassPaymentRecipients(massPaymentId, recipients);
      await torqueEUR.connect(payer).approve(payments.address, ethers.utils.parseUnits("5000", 18));
      await payments.connect(payer).processMassPayment(massPaymentId, 0);

      const massPayment = await payments.getMassPayment(massPaymentId);
      expect(massPayment.status).to.equal(2); // COMPLETED
      expect(massPayment.currency).to.equal(torqueEUR.address);
    });

    it("Should handle maximum recipients", async function () {
      const request = {
        currency: torqueUSD.address,
        totalAmount: ethers.utils.parseUnits("1000000", 18), // 1M TUSD
        expiresAt: (await ethers.provider.getBlock("latest")).timestamp + 86400,
        description: "Maximum Recipients Test",
        metadata: "0x"
      };

      const tx = await payments.connect(payer).createMassPayment(request, 0);
      const receipt = await tx.wait();
      const event = receipt.events?.find((e: any) => e.event === "MassPaymentCreated");
      const massPaymentId = event?.args?.massPaymentId;

      // Add maximum recipients
      const recipients = [];
      for (let i = 0; i < MAX_MASS_PAYMENT_RECIPIENTS; i++) {
        recipients.push({
          recipient: user1Address,
          amount: ethers.utils.parseUnits("1000", 18), // 1000 TUSD each
          recipientType: 0,
          description: `Recipient ${i}`,
          metadata: "0x",
          processed: false,
          processedAt: 0,
          failureReason: ""
        });
      }

      await payments.connect(payer).addMassPaymentRecipients(massPaymentId, recipients);

      const massPayment = await payments.getMassPayment(massPaymentId);
      expect(massPayment.recipientCount).to.equal(MAX_MASS_PAYMENT_RECIPIENTS);
    });
  });
}); 