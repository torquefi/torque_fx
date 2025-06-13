import { expect } from "chai";
import { ethers } from "hardhat";
import { Contract } from "ethers";

describe("TorqueFX", function () {
  let torqueFX: Contract;
  let torqueAccount: Contract;
  let usdc: Contract;
  let mockPriceFeed: Contract;
  let owner: any;
  let user: any;
  let pairId: string;
  const INITIAL_PRICE = 2000 * 10**8; // $2000
  const MARGIN = ethers.parseUnits("1000", 6); // 1000 USDC
  const LEVERAGE = 2000; // 20x

  beforeEach(async function () {
    [owner, user] = await ethers.getSigners();

    // Deploy mock USDC
    const MockUSDC = await ethers.getContractFactory("MockERC20");
    usdc = await MockUSDC.deploy("USD Coin", "USDC", 6);
    await usdc.deployed();

    // Deploy TorqueAccount
    const TorqueAccount = await ethers.getContractFactory("TorqueAccount");
    torqueAccount = await TorqueAccount.deploy();
    await torqueAccount.deployed();

    // Deploy TorqueFX
    const TorqueFX = await ethers.getContractFactory("TorqueFX");
    torqueFX = await TorqueFX.deploy(usdc.address, torqueAccount.address);
    await torqueFX.deployed();

    // Deploy mock price feed
    const MockPriceFeed = await ethers.getContractFactory("MockPriceFeed");
    mockPriceFeed = await MockPriceFeed.deploy();
    await mockPriceFeed.deployed();

    // Set up test pair
    pairId = ethers.keccak256(ethers.toUtf8Bytes("ETH/USD"));
    await torqueFX.setPriceFeed(pairId, mockPriceFeed.address);

    // Set liquidation thresholds
    await torqueFX.setLiquidationThresholds(8500, 9500);

    // Set fee recipient
    await torqueFX.setFeeRecipient(owner.address);

    // Create test account
    await torqueAccount.connect(user).createAccount(LEVERAGE, false, "testuser", ethers.ZeroAddress);

    // Mint USDC to user
    await usdc.mint(user.address, MARGIN * 10n);
    await usdc.connect(user).approve(torqueFX.address, MARGIN * 10n);
  });

  describe("Position Management", function () {
    it("should open a long position", async function () {
      await torqueFX.connect(user).openPosition(pairId, MARGIN, true, 1);
      const position = await torqueFX.positions(user.address, pairId);
      expect(position.margin).to.equal(MARGIN);
      expect(position.isLong).to.be.true;
    });

    it("should open a short position", async function () {
      await torqueFX.connect(user).openPosition(pairId, MARGIN, false, 1);
      const position = await torqueFX.positions(user.address, pairId);
      expect(position.margin).to.equal(MARGIN);
      expect(position.isLong).to.be.false;
    });

    it("should close a profitable position", async function () {
      await torqueFX.connect(user).openPosition(pairId, MARGIN, true, 1);
      
      // Increase price by 10%
      const newPrice = INITIAL_PRICE * 11 / 10;
      await mockPriceFeed.setPrice(newPrice);
      
      const initialBalance = await usdc.balanceOf(user.address);
      await torqueFX.connect(user).closePosition(pairId);
      const finalBalance = await usdc.balanceOf(user.address);
      
      expect(finalBalance).to.be.gt(initialBalance);
    });

    it("should partially liquidate a position", async function () {
      await torqueFX.connect(user).openPosition(pairId, MARGIN, true, 1);
      
      // Decrease price to trigger partial liquidation
      const newPrice = INITIAL_PRICE * 85 / 100;
      await mockPriceFeed.setPrice(newPrice);
      
      const initialBalance = await usdc.balanceOf(user.address);
      await torqueFX.connect(user).liquidate(user.address, pairId);
      const finalBalance = await usdc.balanceOf(user.address);
      
      const position = await torqueFX.positions(user.address, pairId);
      expect(position.margin).to.equal(MARGIN / 2n);
    });

    it("should fully liquidate a position", async function () {
      await torqueFX.connect(user).openPosition(pairId, MARGIN, true, 1);
      
      // Decrease price to trigger full liquidation
      const newPrice = INITIAL_PRICE * 90 / 100;
      await mockPriceFeed.setPrice(newPrice);
      
      await torqueFX.connect(user).liquidate(user.address, pairId);
      const position = await torqueFX.positions(user.address, pairId);
      expect(position.margin).to.equal(0n);
    });
  });

  describe("Health Factor", function () {
    it("should calculate correct health factor for profitable position", async function () {
      await torqueFX.connect(user).openPosition(pairId, MARGIN, true, 1);
      const position = await torqueFX.positions(user.address, pairId);
      const healthFactor = await torqueFX.calculateHealthFactor(
        position,
        INITIAL_PRICE * 11 / 10,
        LEVERAGE
      );
      expect(healthFactor).to.equal(10000); // 100%
    });

    it("should calculate correct health factor for losing position", async function () {
      await torqueFX.connect(user).openPosition(pairId, MARGIN, true, 1);
      const position = await torqueFX.positions(user.address, pairId);
      const healthFactor = await torqueFX.calculateHealthFactor(
        position,
        INITIAL_PRICE * 90 / 100,
        LEVERAGE
      );
      expect(healthFactor).to.be.lt(10000);
    });
  });

  describe("Fee Management", function () {
    it("should charge correct open fee", async function () {
      const initialBalance = await usdc.balanceOf(owner.address);
      await torqueFX.connect(user).openPosition(pairId, MARGIN, true, 1);
      const finalBalance = await usdc.balanceOf(owner.address);
      const fee = MARGIN * 5n / 10000n; // 0.05%
      expect(finalBalance - initialBalance).to.equal(fee);
    });

    it("should charge correct close fee", async function () {
      await torqueFX.connect(user).openPosition(pairId, MARGIN, true, 1);
      const initialBalance = await usdc.balanceOf(owner.address);
      await torqueFX.connect(user).closePosition(pairId);
      const finalBalance = await usdc.balanceOf(owner.address);
      const fee = MARGIN * 5n / 10000n; // 0.05%
      expect(finalBalance - initialBalance).to.equal(fee);
    });
  });
}); 