import { expect } from "chai";
import { ethers } from "hardhat";

describe("MockPriceFeed", function () {
  let mockPriceFeed: any;

  beforeEach(async function () {
    const MockPriceFeed = await ethers.getContractFactory("MockPriceFeed");
    mockPriceFeed = await MockPriceFeed.deploy();
    await mockPriceFeed.waitForDeployment();
  });

  describe("Deployment", function () {
    it("Should deploy with correct initial values", async function () {
      expect(await mockPriceFeed.decimals()).to.equal(8);
      expect(await mockPriceFeed.description()).to.equal("Mock Price Feed");
      expect(await mockPriceFeed.version()).to.equal(1);
    });

    it("Should have correct initial price", async function () {
      const priceData = await mockPriceFeed.latestRoundData();
      expect(priceData.answer).to.equal(2000 * 10**8); // $2,000
      expect(priceData.roundId).to.equal(1);
      expect(priceData.answeredInRound).to.equal(1);
    });
  });

  describe("Price Updates", function () {
    it("Should allow setting new price", async function () {
      const newPrice = 2500 * 10**8; // $2,500
      await mockPriceFeed.setPrice(newPrice);
      
      const priceData = await mockPriceFeed.latestRoundData();
      expect(priceData.answer).to.equal(newPrice);
      expect(priceData.roundId).to.equal(2); // Should increment
    });

    it("Should increment round ID on price update", async function () {
      const initialRoundId = (await mockPriceFeed.latestRoundData()).roundId;
      
      await mockPriceFeed.setPrice(3000 * 10**8);
      const newRoundId = (await mockPriceFeed.latestRoundData()).roundId;
      
      expect(newRoundId).to.equal(initialRoundId + 1n);
    });

    it("Should update timestamp on price update", async function () {
      const initialTimestamp = (await mockPriceFeed.latestRoundData()).updatedAt;
      
      // Fast forward time
      await ethers.provider.send("evm_increaseTime", [3600]); // 1 hour
      await ethers.provider.send("evm_mine", []);
      
      await mockPriceFeed.setPrice(3000 * 10**8);
      const newTimestamp = (await mockPriceFeed.latestRoundData()).updatedAt;
      
      expect(newTimestamp).to.be.gt(initialTimestamp);
    });
  });

  describe("Get Round Data", function () {
    it("Should return correct data for specific round", async function () {
      const roundId = 1;
      const priceData = await mockPriceFeed.getRoundData(roundId);
      
      expect(priceData.roundId).to.equal(roundId);
      expect(priceData.answer).to.equal(2000 * 10**8);
      expect(priceData.answeredInRound).to.equal(1);
    });

    it("Should handle multiple rounds", async function () {
      await mockPriceFeed.setPrice(2500 * 10**8);
      await mockPriceFeed.setPrice(3000 * 10**8);
      
      // getRoundData always returns current price regardless of round ID
      const round1Data = await mockPriceFeed.getRoundData(1);
      const round2Data = await mockPriceFeed.getRoundData(2);
      const round3Data = await mockPriceFeed.getRoundData(3);
      
      // All should return the current price (3000)
      expect(round1Data.answer).to.equal(3000 * 10**8);
      expect(round2Data.answer).to.equal(3000 * 10**8);
      expect(round3Data.answer).to.equal(3000 * 10**8);
    });
  });

  describe("Latest Round Data", function () {
    it("Should always return the most recent price", async function () {
      const prices = [2500, 3000, 3500, 4000];
      
      for (const price of prices) {
        await mockPriceFeed.setPrice(price * 10**8);
        const latestData = await mockPriceFeed.latestRoundData();
        expect(latestData.answer).to.equal(price * 10**8);
      }
    });
  });
}); 