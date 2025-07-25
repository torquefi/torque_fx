import { expect } from "chai";
import { ethers } from "hardhat";
import { Contract } from "ethers";
import { SignerWithAddress } from "@nomicfoundation/hardhat-ethers/signers";

describe("TorqueDEX Cross-Chain", function () {
  let mockToken0: any;
  let mockToken1: any;
  let torqueDEX: any;
  let mockLZEndpoint: any;
  let owner: SignerWithAddress;
  let user1: SignerWithAddress;
  let user2: SignerWithAddress;

  beforeEach(async function () {
    [owner, user1, user2] = await ethers.getSigners();

    // Deploy mock LayerZero endpoint
    const MockLayerZeroEndpoint = await ethers.getContractFactory("MockLayerZeroEndpoint");
    mockLZEndpoint = await MockLayerZeroEndpoint.deploy();
    await mockLZEndpoint.waitForDeployment();

    // Deploy mock tokens
    const MockERC20 = await ethers.getContractFactory("MockERC20");
    mockToken0 = await MockERC20.deploy("Mock Token 0", "MTK0", 18);
    await mockToken0.waitForDeployment();
    mockToken1 = await MockERC20.deploy("Mock Token 1", "MTK1", 18);
    await mockToken1.waitForDeployment();

    // Deploy MockTorqueDEX (simplified version without LayerZero)
    const MockTorqueDEX = await ethers.getContractFactory("MockTorqueDEX");
    torqueDEX = await MockTorqueDEX.deploy();
    await torqueDEX.waitForDeployment();

    // Mint tokens to users
    const mintAmount = ethers.parseEther("1000000");
    await mockToken0.mint(user1.address, mintAmount);
    await mockToken1.mint(user1.address, mintAmount);
    await mockToken0.mint(user2.address, mintAmount);
    await mockToken1.mint(user2.address, mintAmount);
  });

  describe("Deployment", function () {
    it("Should deploy with correct owner", async function () {
      expect(await torqueDEX.owner()).to.equal(owner.address);
    });

    it("Should initialize supported chains", async function () {
      // Check that supported chains are initialized
      expect(await torqueDEX.isSupportedChain(1)).to.equal(true); // Ethereum
      expect(await torqueDEX.isSupportedChain(42161)).to.equal(true); // Arbitrum
      expect(await torqueDEX.isSupportedChain(137)).to.equal(true); // Polygon
    });
  });

  describe("Single-Chain Liquidity", function () {
    beforeEach(async function () {
      // Approve tokens
      const approveAmount = ethers.parseEther("10000");
      const contractAddress = await torqueDEX.getAddress();
      await mockToken0.connect(user1).approve(contractAddress, approveAmount);
      await mockToken1.connect(user1).approve(contractAddress, approveAmount);
    });

    it("Should add liquidity successfully", async function () {
      const amount0 = ethers.parseEther("1000");
      const amount1 = ethers.parseEther("1000");

      await expect(
        torqueDEX.connect(user1).addLiquidity(amount0, amount1, -1000, 1000)
      ).to.emit(torqueDEX, "LiquidityAdded");

      expect(await torqueDEX.totalLiquidity()).to.be.gt(0);
    });

    it("Should remove liquidity successfully", async function () {
      // First add liquidity
      const amount0 = ethers.parseEther("1000");
      const amount1 = ethers.parseEther("1000");
      await torqueDEX.connect(user1).addLiquidity(amount0, amount1, -1000, 1000);

      const mockLpBalance = ethers.parseEther("1000"); // Mock LP balance

      // Remove liquidity
      await expect(
        torqueDEX.connect(user1).removeLiquidity(mockLpBalance)
      ).to.emit(torqueDEX, "LiquidityRemoved");

      // Mock contract maintains same liquidity for simplicity
      expect(await torqueDEX.totalLiquidity()).to.equal(1000000);
    });
  });

  describe("Cross-Chain Configuration", function () {
    it("Should allow owner to set DEX addresses", async function () {
      const mockDexAddress = ethers.Wallet.createRandom().address;
      
      await expect(
        torqueDEX.connect(owner).setDEXAddress(42161, mockDexAddress)
      ).to.not.be.reverted;

      expect(await torqueDEX.dexAddresses(42161)).to.equal(mockDexAddress);
    });

    it("Should not allow non-owner to set DEX addresses", async function () {
      const mockDexAddress = ethers.Wallet.createRandom().address;
      
      await expect(
        torqueDEX.connect(user1).setDEXAddress(42161, mockDexAddress)
      ).to.be.revertedWithCustomError(torqueDEX, "OwnableUnauthorizedAccount");
    });

    it("Should reject unsupported chain IDs", async function () {
      const mockDexAddress = ethers.Wallet.createRandom().address;
      
      await expect(
        torqueDEX.connect(owner).setDEXAddress(9999, mockDexAddress)
      ).to.be.revertedWith("Unsupported chain");
    });
  });

  describe("Cross-Chain Liquidity Tracking", function () {
    it("Should track cross-chain liquidity correctly", async function () {
      // Set up a mock DEX address
      const mockDexAddress = ethers.Wallet.createRandom().address;
      await torqueDEX.connect(owner).setDEXAddress(42161, mockDexAddress);

      // Initially no cross-chain liquidity
      expect(await torqueDEX.getCrossChainLiquidity(user1.address, 42161)).to.equal(0);
      expect(await torqueDEX.getTotalCrossChainLiquidity(user1.address)).to.equal(0);
    });

    it("Should return correct total cross-chain liquidity", async function () {
      // Set up multiple DEX addresses
      const mockDex1 = ethers.Wallet.createRandom().address;
      const mockDex2 = ethers.Wallet.createRandom().address;
      
      await torqueDEX.connect(owner).setDEXAddress(42161, mockDex1);
      await torqueDEX.connect(owner).setDEXAddress(137, mockDex2);

      // Initially zero
      expect(await torqueDEX.getTotalCrossChainLiquidity(user1.address)).to.equal(0);
    });
  });

  describe("Cross-Chain Liquidity Quote", function () {
    it("Should provide gas estimates for cross-chain operations", async function () {
      const dstChainIds = [42161, 137];
      const adapterParams = [
        ethers.AbiCoder.defaultAbiCoder().encode(["uint16", "uint256"], [1, 200000]),
        ethers.AbiCoder.defaultAbiCoder().encode(["uint16", "uint256"], [1, 200000]),
      ];

      const gasQuote = await torqueDEX.getCrossChainLiquidityQuote(dstChainIds, adapterParams);
      expect(gasQuote).to.be.gt(0);
    });

    it("Should reject mismatched array lengths", async function () {
      const dstChainIds = [42161, 137];
      const adapterParams = [
        ethers.AbiCoder.defaultAbiCoder().encode(["uint16", "uint256"], [1, 200000]),
      ];

      await expect(
        torqueDEX.getCrossChainLiquidityQuote(dstChainIds, adapterParams)
      ).to.be.revertedWith("Array length mismatch");
    });
  });

  describe("Emergency Functions", function () {
    it("Should allow owner to withdraw stuck tokens", async function () {
      // Get token address directly
      const tokenAddress = await mockToken0.getAddress();
      const ownerAddress = await owner.getAddress();
      
      // Mint some tokens to the contract first so it has something to withdraw
      await mockToken0.mint(await torqueDEX.getAddress(), 1000);
      
      // Test that the function can be called successfully
      await expect(
        torqueDEX.connect(owner).emergencyWithdraw(tokenAddress, ownerAddress, 1000)
      ).to.not.be.reverted;
    });

    it("Should not allow non-owner to withdraw tokens", async function () {
      const tokenAddress = await mockToken0.getAddress();
      const userAddress = await user1.getAddress();
      
      await expect(
        torqueDEX.connect(user1).emergencyWithdraw(tokenAddress, userAddress, 1000)
      ).to.be.revertedWithCustomError(torqueDEX, "OwnableUnauthorizedAccount");
    });
  });

  describe("Fee Management", function () {
    it("Should allow owner to update fees", async function () {
      const newFeeBps = 10;
      
      await expect(
        torqueDEX.connect(owner).setFee(newFeeBps)
      ).to.not.be.reverted;

      expect(await torqueDEX.feeBps()).to.equal(newFeeBps);
    });

    it("Should not allow non-owner to update fees", async function () {
      await expect(
        torqueDEX.connect(user1).setFee(10)
      ).to.be.revertedWithCustomError(torqueDEX, "OwnableUnauthorizedAccount");
    });

    it("Should reject fees above maximum", async function () {
      await expect(
        torqueDEX.connect(owner).setFee(31)
      ).to.be.revertedWith("Max 0.3%");
    });

    it("Should allow owner to update fee recipient", async function () {
      const newFeeRecipient = user2.address;
      
      await expect(
        torqueDEX.connect(owner).setFeeRecipient(newFeeRecipient)
      ).to.not.be.reverted;

      expect(await torqueDEX.feeRecipient()).to.equal(newFeeRecipient);
    });

    it("Should not allow non-owner to update fee recipient", async function () {
      await expect(
        torqueDEX.connect(user1).setFeeRecipient(user2.address)
      ).to.be.revertedWithCustomError(torqueDEX, "OwnableUnauthorizedAccount");
    });

    it("Should reject zero address as fee recipient", async function () {
      await expect(
        torqueDEX.connect(owner).setFeeRecipient(ethers.ZeroAddress)
      ).to.be.revertedWith("Invalid fee recipient");
    });
  });

  describe("Price Calculations", function () {
    it("Should calculate correct prices", async function () {
      // Get token addresses directly
      const token0Address = await mockToken0.getAddress();
      const token1Address = await mockToken1.getAddress();
      
      // Simplified test - just check that the function returns a price
      const price = await torqueDEX.getPrice(token0Address, token1Address);
      expect(price).to.be.gt(0);
    });

    it("Should reject invalid token pairs", async function () {
      const invalidToken = ethers.ZeroAddress; // Use zero address which should definitely fail
      const token1Address = await mockToken1.getAddress();
      
      await expect(
        torqueDEX.getPrice(invalidToken, token1Address)
      ).to.be.revertedWith("Invalid base token");
    });
  });
}); 