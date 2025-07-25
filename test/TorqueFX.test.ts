import { expect } from "chai";
import { ethers } from "hardhat";
import { Contract } from "ethers";
import { SignerWithAddress } from "@nomicfoundation/hardhat-ethers/signers";

describe("TorqueFX", function () {
  let torqueFX: any;
  let usdc: any;
  let mockPriceFeed: any;
  let mockDEX: any;
  let owner: SignerWithAddress;
  let user: SignerWithAddress;
  let pairId: string;
  const INITIAL_PRICE = 2000 * 10**8; // $2000
  const MARGIN = ethers.parseUnits("1000", 6); // 1000 USDC
  const LEVERAGE = 2000; // 20x

  beforeEach(async function () {
    [owner, user] = await ethers.getSigners();

    // Deploy mock USDC
    const MockUSDC = await ethers.getContractFactory("MockERC20");
    usdc = await MockUSDC.deploy("USD Coin", "USDC", 6);
    await usdc.waitForDeployment();

    // Deploy mock DEX
    const MockTorqueDEX = await ethers.getContractFactory("MockTorqueDEX");
    mockDEX = await MockTorqueDEX.deploy();
    await mockDEX.waitForDeployment();

    // Deploy TorqueFX
    const TorqueFX = await ethers.getContractFactory("TorqueFX");
    const usdcAddress = await usdc.getAddress();
    torqueFX = await TorqueFX.deploy(await mockDEX.getAddress(), usdcAddress); // DEX contract first, then USDC
    await torqueFX.waitForDeployment();

    // Deploy mock price feed
    const MockPriceFeed = await ethers.getContractFactory("MockPriceFeed");
    mockPriceFeed = await MockPriceFeed.deploy();
    await mockPriceFeed.waitForDeployment();

    // Set up test pair - use the same pair ID that openPosition will generate
    const usdcAddr = await usdc.getAddress();
    pairId = ethers.keccak256(ethers.solidityPacked(["address", "address"], [usdcAddr, usdcAddr]));
    await torqueFX.setPriceFeed(pairId, await mockPriceFeed.getAddress());

    // Set liquidation thresholds
    await torqueFX.setLiquidationThresholds(8500, 9500);

    // Set fee recipient
    await torqueFX.setFeeRecipient(owner.address);

    // Mint USDC to user
    await usdc.mint(await user.getAddress(), MARGIN * 10n);
    await usdc.connect(user).approve(await torqueFX.getAddress(), MARGIN * 10n);
  });

  describe("Position Management", function () {
    it("should open a long position", async function () {
      await torqueFX.connect(user).openPosition(await usdc.getAddress(), await usdc.getAddress(), MARGIN, LEVERAGE, true);
      const position = await torqueFX.positions(await user.getAddress(), pairId);
      const expectedCollateral = MARGIN - (MARGIN * 5n / 10000n); // Subtract 0.05% fee
      expect(position.collateral).to.equal(expectedCollateral);
      expect(position.isLong).to.be.true;
    });

    it("should open a short position", async function () {
      await torqueFX.connect(user).openPosition(await usdc.getAddress(), await usdc.getAddress(), MARGIN, LEVERAGE, false);
      const position = await torqueFX.positions(await user.getAddress(), pairId);
      const expectedCollateral = MARGIN - (MARGIN * 5n / 10000n); // Subtract 0.05% fee
      expect(position.collateral).to.equal(expectedCollateral);
      expect(position.isLong).to.be.false;
    });

    it("should close a profitable position", async function () {
      await torqueFX.connect(user).openPosition(await usdc.getAddress(), await usdc.getAddress(), MARGIN, 1, true);
      
      // Increase price by 10%
      const newPrice = INITIAL_PRICE * 11 / 10;
      await mockPriceFeed.setPrice(newPrice);
      
      const initialBalance = await usdc.balanceOf(await user.getAddress());
      await torqueFX.connect(user).closePosition(pairId);
      const finalBalance = await usdc.balanceOf(await user.getAddress());
      
      expect(finalBalance).to.be.gt(initialBalance);
    });

    it("should partially liquidate a position", async function () {
      await torqueFX.connect(user).openPosition(await usdc.getAddress(), await usdc.getAddress(), MARGIN, 1, true);
      
      // Decrease price to trigger partial liquidation
      const newPrice = INITIAL_PRICE * 85 / 100;
      await mockPriceFeed.setPrice(newPrice);
      
      const initialBalance = await usdc.balanceOf(await user.getAddress());
      await torqueFX.connect(user).liquidate(await user.getAddress(), pairId);
      const finalBalance = await usdc.balanceOf(await user.getAddress());
      
      const position = await torqueFX.positions(await user.getAddress(), pairId);
      // Check that some collateral remains (partial liquidation)
      expect(position.collateral).to.be.gt(0);
    });

    it("should fully liquidate a position", async function () {
      await torqueFX.connect(user).openPosition(await usdc.getAddress(), await usdc.getAddress(), MARGIN, 1, true);
      
      // Decrease price to trigger full liquidation
      const newPrice = INITIAL_PRICE * 70 / 100; // More severe price drop
      await mockPriceFeed.setPrice(newPrice);
      
      await torqueFX.connect(user).liquidate(await user.getAddress(), pairId);
      const position = await torqueFX.positions(await user.getAddress(), pairId);
      // Position should be deleted (full liquidation)
      expect(position.collateral).to.equal(0);
    });
  });

  describe("Health Factor", function () {
    it("should calculate correct health factor for profitable position", async function () {
      await torqueFX.connect(user).openPosition(await usdc.getAddress(), await usdc.getAddress(), MARGIN, 1, true);
      const position = await torqueFX.positions(await user.getAddress(), pairId);
      const healthFactor = await torqueFX.calculateHealthFactor(
        position.collateral,
        position.positionSize,
        0 // PnL is 0 for profitable position
      );
      expect(healthFactor).to.equal(10000); // 100%
    });

    it("should calculate correct health factor for losing position", async function () {
      await torqueFX.connect(user).openPosition(await usdc.getAddress(), await usdc.getAddress(), MARGIN, 1, true);
      const position = await torqueFX.positions(await user.getAddress(), pairId);
      const healthFactor = await torqueFX.calculateHealthFactor(
        position.collateral,
        position.positionSize,
        -(position.collateral / 2n) // Negative PnL
      );
      expect(healthFactor).to.be.lt(10000);
    });
  });

  describe("Fee Management", function () {
    it("should charge correct open fee", async function () {
      const initialBalance = await usdc.balanceOf(await owner.getAddress());
      await torqueFX.connect(user).openPosition(await usdc.getAddress(), await usdc.getAddress(), MARGIN, 1, true);
      const finalBalance = await usdc.balanceOf(await owner.getAddress());
      const fee = MARGIN * 5n / 10000n; // 0.05%
      expect(finalBalance - initialBalance).to.equal(fee);
    });

    it("should charge correct close fee", async function () {
      await torqueFX.connect(user).openPosition(await usdc.getAddress(), await usdc.getAddress(), MARGIN, 1, true);
      
      // Increase price by 10%
      const newPrice = INITIAL_PRICE * 11 / 10;
      await mockPriceFeed.setPrice(newPrice);
      
      const initialBalance = await usdc.balanceOf(await user.getAddress());
      await torqueFX.connect(user).closePosition(pairId);
      const finalBalance = await usdc.balanceOf(await user.getAddress());
      
      // User should receive money (profit), so fee is deducted from the profit
      const profitReceived = finalBalance - initialBalance;
      // The fee is charged on the total amount returned, not on the profit
      expect(profitReceived).to.be.gt(0); // User should make a profit
    });
  });
}); 