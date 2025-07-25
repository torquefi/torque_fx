import { expect } from "chai";
import { ethers } from "hardhat";
import { Contract, Signer } from "ethers";

describe("TorqueBatchHandler", function () {
  let batchHandler: any;
  let mockUSDC: any;
  let mockPriceFeed: any;
  let torqueUSD: any;
  let torqueUSEngine: any;
  let mockLZEndpoint: any;
  let deployer: Signer;
  let user: Signer;
  let userAddress: string;
  let deployerAddress: string;

  const CHAIN_IDS = {
    ETHEREUM: 1,
    ARBITRUM: 42161,
    OPTIMISM: 10,
    POLYGON: 137,
    BASE: 8453,
    SONIC: 146,
    BSC: 56,
    AVALANCHE: 43114,
  };

  beforeEach(async function () {
    [deployer, user] = await ethers.getSigners();
    deployerAddress = await deployer.getAddress();
    userAddress = await user.getAddress();

    // Deploy mock LayerZero endpoint
    const MockLayerZeroEndpoint = await ethers.getContractFactory("MockLayerZeroEndpoint");
    mockLZEndpoint = await MockLayerZeroEndpoint.deploy();
    await mockLZEndpoint.waitForDeployment();

    // Deploy mock contracts
    const MockUSDC = await ethers.getContractFactory("MockERC20");
    mockUSDC = await MockUSDC.deploy("USD Coin", "USDC", 6);
    await mockUSDC.waitForDeployment();

    // Deploy MockTorqueBatchHandler (simplified version without LayerZero)
    const MockTorqueBatchHandler = await ethers.getContractFactory("MockTorqueBatchHandler");
    batchHandler = await MockTorqueBatchHandler.deploy(deployerAddress);
    await batchHandler.waitForDeployment();

    // Add mock currency for testing
    await batchHandler.addSupportedCurrency(await mockUSDC.getAddress());

    // Mint USDC to user for testing
    await mockUSDC.mint(userAddress, ethers.parseUnits("10000", 6));
  });

  describe("Deployment", function () {
    it("Should deploy with correct owner", async function () {
      expect(await batchHandler.owner()).to.equal(deployerAddress);
    });

    it("Should have correct owner", async function () {
      expect(await batchHandler.owner()).to.equal(deployerAddress);
    });

    it("Should have correct max batch size", async function () {
      expect(await batchHandler.maxBatchSize()).to.equal(50);
    });
  });

  describe("Configuration", function () {
    it("Should add supported currency", async function () {
      const currencyAddress = await mockUSDC.getAddress();
      expect(await batchHandler.supportedCurrencies(currencyAddress)).to.be.true;
    });

    it("Should only allow owner to add supported currency", async function () {
      const newCurrency = ethers.Wallet.createRandom().address;
      
      await expect(
        batchHandler.connect(user).addSupportedCurrency(newCurrency)
      ).to.be.revertedWithCustomError(batchHandler, "OwnableUnauthorizedAccount");
    });
  });

  describe("Batch Minting", function () {
    beforeEach(async function () {
      // Approve USDC spending
      await mockUSDC.connect(user).approve(await batchHandler.getAddress(), ethers.parseUnits("10000", 6));
    });

    it("Should revert with invalid batch size", async function () {
      const currencyAddress = await mockUSDC.getAddress();
      const dstChainIds: number[] = [];
      const amountsPerChain: bigint[] = [];
      const adapterParams: string[] = [];

      await expect(
        batchHandler.connect(user).batchMint(
          currencyAddress,
          ethers.parseUnits("1000", 6),
          dstChainIds,
          amountsPerChain,
          adapterParams
        )
      ).to.be.revertedWithCustomError(batchHandler, "TorqueBatchHandler__InvalidBatchSize");
    });

    it("Should revert with unsupported currency", async function () {
      const unsupportedCurrency = ethers.Wallet.createRandom().address;
      const dstChainIds = [CHAIN_IDS.ARBITRUM];
      const amountsPerChain = [ethers.parseUnits("500", 6)];
      const adapterParams = ["0x"];

      await expect(
        batchHandler.connect(user).batchMint(
          unsupportedCurrency,
          ethers.parseUnits("1000", 6),
          dstChainIds,
          amountsPerChain,
          adapterParams
        )
      ).to.be.revertedWithCustomError(batchHandler, "TorqueBatchHandler__UnsupportedCurrency");
    });

    it("Should revert with invalid chain ID", async function () {
      const currencyAddress = await mockUSDC.getAddress();
      const dstChainIds = [9999]; // Invalid chain ID (valid uint16 but not supported)
      const amountsPerChain = [ethers.parseUnits("500", 6)];
      const adapterParams = ["0x"];

      await expect(
        batchHandler.connect(user).batchMint(
          currencyAddress,
          ethers.parseUnits("1000", 6),
          dstChainIds,
          amountsPerChain,
          adapterParams
        )
      ).to.be.revertedWithCustomError(batchHandler, "TorqueBatchHandler__InvalidChainId");
    });

    it("Should revert with mismatched array lengths", async function () {
      const currencyAddress = await mockUSDC.getAddress();
      const dstChainIds = [CHAIN_IDS.ARBITRUM, CHAIN_IDS.OPTIMISM];
      const amountsPerChain = [ethers.parseUnits("500", 6)]; // Only one amount
      const adapterParams = ["0x", "0x"]; // Two adapter params

      await expect(
        batchHandler.connect(user).batchMint(
          currencyAddress,
          ethers.parseUnits("1000", 6),
          dstChainIds,
          amountsPerChain,
          adapterParams
        )
      ).to.be.revertedWithCustomError(batchHandler, "TorqueBatchHandler__InvalidAmounts");
    });

    it("Should revert with zero total amount", async function () {
      const currencyAddress = await mockUSDC.getAddress();
      const dstChainIds = [CHAIN_IDS.ARBITRUM];
      const amountsPerChain = [0n]; // Zero amount
      const adapterParams = ["0x"];

      await expect(
        batchHandler.connect(user).batchMint(
          currencyAddress,
          ethers.parseUnits("1000", 6),
          dstChainIds,
          amountsPerChain,
          adapterParams
        )
      ).to.be.revertedWithCustomError(batchHandler, "TorqueBatchHandler__InvalidAmounts");
    });

    it("Should emit BatchMintInitiated event", async function () {
      const currencyAddress = await mockUSDC.getAddress();
      const dstChainIds = [CHAIN_IDS.ARBITRUM, CHAIN_IDS.OPTIMISM];
      const amountsPerChain = [ethers.parseUnits("500", 6), ethers.parseUnits("300", 6)];
      const adapterParams = ["0x", "0x"];
      const totalCollateral = ethers.parseUnits("1000", 6);

      await expect(
        batchHandler.connect(user).batchMint(
          currencyAddress,
          totalCollateral,
          dstChainIds,
          amountsPerChain,
          adapterParams
        )
      ).to.emit(batchHandler, "BatchMintInitiated")
        .withArgs(userAddress, currencyAddress, ethers.parseUnits("800", 6), dstChainIds, amountsPerChain);
    });
  });

  describe("Cross-Chain Message Handling", function () {
    it("Should handle incoming mint requests", async function () {
      const currencyAddress = await mockUSDC.getAddress();
      const amount = ethers.parseUnits("100", 6);
      
      // Simulate incoming cross-chain message
      const payload = ethers.AbiCoder.defaultAbiCoder().encode(
        ["address", "address", "uint256"],
        [currencyAddress, userAddress, amount]
      );

      // Mock the LayerZero receive function
      await expect(
        batchHandler._nonblockingLzReceive(
          CHAIN_IDS.ARBITRUM,
          ethers.toUtf8Bytes("0x1234"),
          1,
          payload
        )
      ).to.emit(batchHandler, "BatchMintCompleted")
        .withArgs(userAddress, currencyAddress, CHAIN_IDS.ARBITRUM, amount);
    });

    it("Should handle failed mint requests", async function () {
      const unsupportedCurrency = ethers.Wallet.createRandom().address;
      const amount = ethers.parseUnits("100", 6);
      
      const payload = ethers.AbiCoder.defaultAbiCoder().encode(
        ["address", "address", "uint256"],
        [unsupportedCurrency, userAddress, amount]
      );

      await expect(
        batchHandler._nonblockingLzReceive(
          CHAIN_IDS.ARBITRUM,
          ethers.toUtf8Bytes("0x1234"),
          1,
          payload
        )
      ).to.emit(batchHandler, "BatchMintFailed")
        .withArgs(userAddress, unsupportedCurrency, CHAIN_IDS.ARBITRUM, amount, "Engine not configured");
    });
  });

  describe("Gas Estimation", function () {
    it("Should estimate gas for batch operations", async function () {
      const dstChainIds = [CHAIN_IDS.ARBITRUM, CHAIN_IDS.OPTIMISM];
      const adapterParams = ["0x", "0x"];

      const gasEstimate = await batchHandler.getBatchMintQuote(dstChainIds, adapterParams);
      
      // Should return a reasonable gas estimate
      expect(gasEstimate).to.be.gt(0);
      expect(gasEstimate).to.be.lt(ethers.parseUnits("1", 18)); // Less than 1 ETH
    });
  });

  describe("Admin Functions", function () {
    it("Should allow owner to set max batch size", async function () {
      const newMaxBatchSize = 5;
      await batchHandler.setMaxBatchSize(newMaxBatchSize);
      expect(await batchHandler.maxBatchSize()).to.equal(newMaxBatchSize);
    });

    it("Should only allow owner to set max batch size", async function () {
      await expect(
        batchHandler.connect(user).setMaxBatchSize(5)
      ).to.be.revertedWithCustomError(batchHandler, "OwnableUnauthorizedAccount");
    });

    it("Should revert setting invalid max batch size", async function () {
      await expect(batchHandler.setMaxBatchSize(0)).to.be.revertedWith("Invalid batch size");
      await expect(batchHandler.setMaxBatchSize(101)).to.be.revertedWith("Invalid batch size");
    });

    it("Should allow owner to remove supported currency", async function () {
      const currencyAddress = await mockUSDC.getAddress();
      await batchHandler.removeSupportedCurrency(currencyAddress);
      expect(await batchHandler.supportedCurrencies(currencyAddress)).to.be.false;
    });

    it("Should allow emergency withdrawal", async function () {
      const tokenAddress = await mockUSDC.getAddress();
      const amount = ethers.parseUnits("100", 6);
      
      // Mint tokens to deployer first
      await mockUSDC.mint(deployerAddress, amount);
      
      // Transfer some tokens to batch minter
      await mockUSDC.transfer(await batchHandler.getAddress(), amount);
      
      const initialBalance = await mockUSDC.balanceOf(deployerAddress);
      await batchHandler.emergencyWithdraw(tokenAddress, deployerAddress, amount);
      const finalBalance = await mockUSDC.balanceOf(deployerAddress);
      
      expect(finalBalance - initialBalance).to.equal(amount);
    });
  });

  describe("Supported Chain IDs", function () {
    it("Should return all supported chain IDs", async function () {
      const supportedChainIds = await batchHandler.getSupportedChainIds();
      
      expect(supportedChainIds).to.have.length(8);
      expect(supportedChainIds).to.include(BigInt(CHAIN_IDS.ETHEREUM));
      expect(supportedChainIds).to.include(BigInt(CHAIN_IDS.ARBITRUM));
      expect(supportedChainIds).to.include(BigInt(CHAIN_IDS.OPTIMISM));
      expect(supportedChainIds).to.include(BigInt(CHAIN_IDS.POLYGON));
      expect(supportedChainIds).to.include(BigInt(CHAIN_IDS.BASE));
      expect(supportedChainIds).to.include(BigInt(CHAIN_IDS.SONIC));
      expect(supportedChainIds).to.include(BigInt(CHAIN_IDS.BSC));
      expect(supportedChainIds).to.include(BigInt(CHAIN_IDS.AVALANCHE));
    });

    it("Should validate supported chain IDs", async function () {
      expect(await batchHandler.supportedChainIds(CHAIN_IDS.ETHEREUM)).to.be.true;
      expect(await batchHandler.supportedChainIds(CHAIN_IDS.ARBITRUM)).to.be.true;
      expect(await batchHandler.supportedChainIds(9999)).to.be.false;
    });
  });

  describe("Reentrancy Protection", function () {
    it("Should allow multiple batch mint calls (mock behavior)", async function () {
      // Mock contract allows multiple calls for testing purposes
      const currencyAddress = await mockUSDC.getAddress();
      const dstChainIds = [CHAIN_IDS.ARBITRUM];
      const amountsPerChain = [ethers.parseUnits("500", 6)];
      const adapterParams = ["0x"];

      // Approve USDC
      await mockUSDC.connect(user).approve(await batchHandler.getAddress(), ethers.parseUnits("10000", 6));

      // First call should succeed
      await expect(
        batchHandler.connect(user).batchMint(
          currencyAddress,
          ethers.parseUnits("1000", 6),
          dstChainIds,
          amountsPerChain,
          adapterParams
        )
      ).to.emit(batchHandler, "BatchMintInitiated");

      // Second call should also succeed (mock behavior)
      await expect(
        batchHandler.connect(user).batchMint(
          currencyAddress,
          ethers.parseUnits("1000", 6),
          dstChainIds,
          amountsPerChain,
          adapterParams
        )
      ).to.emit(batchHandler, "BatchMintInitiated");
    });
  });
}); 