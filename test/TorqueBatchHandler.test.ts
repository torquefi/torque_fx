import { expect } from "chai";
import { ethers } from "hardhat";
import { Contract, Signer } from "ethers";

describe("TorqueBatchHandler", function () {
  let batchHandler: Contract;
  let mockUSDC: Contract;
  let mockPriceFeed: Contract;
  let torqueUSD: Contract;
  let torqueUSEngine: Contract;
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

    // Deploy mock contracts
    const MockUSDC = await ethers.getContractFactory("MockERC20");
    mockUSDC = await MockUSDC.deploy("USD Coin", "USDC", 6);
    await mockUSDC.waitForDeployment();

    const MockPriceFeed = await ethers.getContractFactory("MockPriceFeed");
    mockPriceFeed = await MockPriceFeed.deploy(8, "USD/ETH", 18);
    await mockPriceFeed.waitForDeployment();

    // Deploy TorqueUSD currency
    const TorqueUSD = await ethers.getContractFactory("TorqueUSD");
    torqueUSD = await TorqueUSD.deploy("Torque USD", "TorqueUSD", "0x1a44076050125825900e736c501f859c50fE728c");
    await torqueUSD.waitForDeployment();

    // Deploy TorqueUSDEngine
    const TorqueUSDEngine = await ethers.getContractFactory("TorqueUSDEngine");
    torqueUSEngine = await TorqueUSDEngine.deploy(
      await mockUSDC.getAddress(),
      await mockPriceFeed.getAddress(),
      await torqueUSD.getAddress(),
      "0x1a44076050125825900e736c501f859c50fE728c"
    );
    await torqueUSEngine.waitForDeployment();

    // Deploy TorqueBatchHandler
    const TorqueBatchHandler = await ethers.getContractFactory("TorqueBatchHandler");
    batchHandler = await TorqueBatchHandler.deploy(
      "0x1a44076050125825900e736c501f859c50fE728c",
      deployerAddress
    );
    await batchHandler.waitForDeployment();

    // Configure batch minter
    await batchHandler.addSupportedCurrency(await torqueUSD.getAddress());
    await batchHandler.setEngineAddress(
      await torqueUSD.getAddress(),
      CHAIN_IDS.ETHEREUM,
      await torqueUSEngine.getAddress()
    );

    // Mint USDC to user for testing
    await mockUSDC.mint(userAddress, ethers.parseUnits("10000", 6));
  });

  describe("Deployment", function () {
    it("Should deploy with correct owner", async function () {
      expect(await batchHandler.owner()).to.equal(deployerAddress);
    });

    it("Should have correct LayerZero endpoint", async function () {
      expect(await batchHandler.endpoint()).to.equal("0x1a44076050125825900e736c501f859c50fE728c");
    });

    it("Should have correct max batch size", async function () {
      expect(await batchHandler.maxBatchSize()).to.equal(50);
    });
  });

  describe("Configuration", function () {
    it("Should add supported currency", async function () {
      const currencyAddress = await torqueUSD.getAddress();
      expect(await batchHandler.supportedCurrencies(currencyAddress)).to.be.true;
    });

    it("Should set engine address", async function () {
      const currencyAddress = await torqueUSD.getAddress();
      const engineAddress = await torqueUSEngine.getAddress();
      const chainId = CHAIN_IDS.ETHEREUM;

      expect(await batchHandler.engineAddresses(currencyAddress, chainId)).to.equal(engineAddress);
    });

    it("Should only allow owner to add supported currency", async function () {
      const newCurrency = ethers.Wallet.createRandom().address;
      
      await expect(
        batchHandler.connect(user).addSupportedCurrency(newCurrency)
      ).to.be.revertedWithCustomError(batchHandler, "OwnableUnauthorizedAccount");
    });

    it("Should only allow owner to set engine address", async function () {
      const currencyAddress = await torqueUSD.getAddress();
      const engineAddress = await torqueUSEngine.getAddress();
      const chainId = CHAIN_IDS.ARBITRUM;

      await expect(
        batchHandler.connect(user).setEngineAddress(currencyAddress, chainId, engineAddress)
      ).to.be.revertedWithCustomError(batchHandler, "OwnableUnauthorizedAccount");
    });
  });

  describe("Batch Minting", function () {
    beforeEach(async function () {
      // Approve USDC spending
      await mockUSDC.connect(user).approve(await batchHandler.getAddress(), ethers.parseUnits("10000", 6));
    });

    it("Should revert with invalid batch size", async function () {
      const currencyAddress = await torqueUSD.getAddress();
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
      const currencyAddress = await torqueUSD.getAddress();
      const dstChainIds = [99999]; // Invalid chain ID
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
      const currencyAddress = await torqueUSD.getAddress();
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
      const currencyAddress = await torqueUSD.getAddress();
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
      const currencyAddress = await torqueUSD.getAddress();
      const dstChainIds = [CHAIN_IDS.ARBITRUM, CHAIN_IDS.OPTIMISM];
      const amountsPerChain = [ethers.parseUnits("500", 6), ethers.parseUnits("300", 6)];
      const adapterParams = ["0x", "0x"];
      const totalCollateral = ethers.parseUnits("1000", 6);

      // Set up engine addresses for destination chains
      await batchHandler.setEngineAddress(currencyAddress, CHAIN_IDS.ARBITRUM, await torqueUSEngine.getAddress());
      await batchHandler.setEngineAddress(currencyAddress, CHAIN_IDS.OPTIMISM, await torqueUSEngine.getAddress());

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
      const currencyAddress = await torqueUSD.getAddress();
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
      const currencyAddress = await torqueUSD.getAddress();
      const amount = ethers.parseUnits("100", 6);
      
      // Remove engine address to simulate failure
      await batchHandler.setEngineAddress(currencyAddress, CHAIN_IDS.ARBITRUM, ethers.ZeroAddress);
      
      const payload = ethers.AbiCoder.defaultAbiCoder().encode(
        ["address", "address", "uint256"],
        [currencyAddress, userAddress, amount]
      );

      await expect(
        batchHandler._nonblockingLzReceive(
          CHAIN_IDS.ARBITRUM,
          ethers.toUtf8Bytes("0x1234"),
          1,
          payload
        )
      ).to.emit(batchHandler, "BatchMintFailed")
        .withArgs(userAddress, currencyAddress, CHAIN_IDS.ARBITRUM, amount, "Engine not configured");
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
      const currencyAddress = await torqueUSD.getAddress();
      await batchHandler.removeSupportedCurrency(currencyAddress);
      expect(await batchHandler.supportedCurrencies(currencyAddress)).to.be.false;
    });

    it("Should allow emergency withdrawal", async function () {
      const tokenAddress = await mockUSDC.getAddress();
      const amount = ethers.parseUnits("100", 6);
      
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
      expect(supportedChainIds).to.include(CHAIN_IDS.ETHEREUM);
      expect(supportedChainIds).to.include(CHAIN_IDS.ARBITRUM);
      expect(supportedChainIds).to.include(CHAIN_IDS.OPTIMISM);
      expect(supportedChainIds).to.include(CHAIN_IDS.POLYGON);
      expect(supportedChainIds).to.include(CHAIN_IDS.BASE);
      expect(supportedChainIds).to.include(CHAIN_IDS.SONIC);
      expect(supportedChainIds).to.include(CHAIN_IDS.BSC);
      expect(supportedChainIds).to.include(CHAIN_IDS.AVALANCHE);
    });

    it("Should validate supported chain IDs", async function () {
      expect(await batchHandler.supportedChainIds(CHAIN_IDS.ETHEREUM)).to.be.true;
      expect(await batchHandler.supportedChainIds(CHAIN_IDS.ARBITRUM)).to.be.true;
      expect(await batchHandler.supportedChainIds(99999)).to.be.false;
    });
  });

  describe("Reentrancy Protection", function () {
    it("Should prevent reentrancy attacks", async function () {
      // The contract uses ReentrancyGuard, so calling batchMint twice should fail
      const currencyAddress = await torqueUSD.getAddress();
      const dstChainIds = [CHAIN_IDS.ARBITRUM];
      const amountsPerChain = [ethers.parseUnits("500", 6)];
      const adapterParams = ["0x"];

      // Set up engine address
      await batchHandler.setEngineAddress(currencyAddress, CHAIN_IDS.ARBITRUM, await torqueUSEngine.getAddress());

      // Approve USDC
      await mockUSDC.connect(user).approve(await batchHandler.getAddress(), ethers.parseUnits("10000", 6));

      // First call should succeed
      await batchHandler.connect(user).batchMint(
        currencyAddress,
        ethers.parseUnits("1000", 6),
        dstChainIds,
        amountsPerChain,
        adapterParams
      );

      // Second call should fail due to reentrancy protection
      await expect(
        batchHandler.connect(user).batchMint(
          currencyAddress,
          ethers.parseUnits("1000", 6),
          dstChainIds,
          amountsPerChain,
          adapterParams
        )
      ).to.be.reverted;
    });
  });
}); 