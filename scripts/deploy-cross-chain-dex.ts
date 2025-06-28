import { ethers } from "hardhat";
import { Contract } from "ethers";

async function main() {
  const [deployer] = await ethers.getSigners();
  console.log("Deploying contracts with the account:", deployer.address);

  // LayerZero endpoint addresses for different chains
  const LZ_ENDPOINTS = {
    1: "0x66A71Dcef29A0fFBDBE3c6a460a3B5BC225Cd675", // Ethereum
    42161: "0x3c2269811836af69497E5F486A85D7316753cf62", // Arbitrum
    10: "0x3c2269811836af69497E5F486A85D7316753cf62", // Optimism
    137: "0x3c2269811836af69497E5F486A85D7316753cf62", // Polygon
    8453: "0xb6319cC6c8c27A8F5dAF0dD3DF91EA35C4720dd7", // Base
    146: "0x3c2269811836af69497E5F486A85D7316753cf62", // Sonic
    2741: "0x3c2269811836af69497E5F486A85D7316753cf62", // Abstract
    56: "0x3c2269811836af69497E5F486A85D7316753cf62", // BSC
    999: "0x3c2269811836af69497E5F486A85D7316753cf62", // HyperEVM
    252: "0x3c2269811836af69497E5F486A85D7316753cf62", // Fraxtal
    43114: "0x3c2269811836af69497E5F486A85D7316753cf62", // Avalanche
  };

  // Get current chain ID
  const chainId = await deployer.getChainId();
  const lzEndpoint = LZ_ENDPOINTS[chainId as keyof typeof LZ_ENDPOINTS];
  
  if (!lzEndpoint) {
    throw new Error(`LayerZero endpoint not found for chain ID ${chainId}`);
  }

  console.log(`Deploying on chain ID: ${chainId}`);
  console.log(`LayerZero endpoint: ${lzEndpoint}`);

  // Deploy mock tokens for testing (replace with actual token addresses in production)
  console.log("Deploying mock tokens...");
  
  const MockERC20 = await ethers.getContractFactory("MockERC20");
  const mockToken0 = await MockERC20.deploy("Mock Token 0", "MTK0");
  await mockToken0.deployed();
  console.log("Mock Token 0 deployed to:", mockToken0.address);

  const mockToken1 = await MockERC20.deploy("Mock Token 1", "MTK1");
  await mockToken1.deployed();
  console.log("Mock Token 1 deployed to:", mockToken1.address);

  // Deploy TorqueDEX
  console.log("Deploying TorqueDEX...");
  const TorqueDEX = await ethers.getContractFactory("TorqueDEX");
  const torqueDEX = await TorqueDEX.deploy(
    mockToken0.address,
    mockToken1.address,
    "Torque LP Token",
    "TLP",
    deployer.address, // fee recipient
    false, // isStablePair
    lzEndpoint,
    deployer.address // owner
  );
  await torqueDEX.deployed();
  console.log("TorqueDEX deployed to:", torqueDEX.address);

  // Set up cross-chain DEX addresses (this would be done on each chain)
  console.log("Setting up cross-chain DEX addresses...");
  
  // Example: Set DEX addresses for other chains
  // In production, you would deploy TorqueDEX on each chain and set the addresses
  const supportedChainIds = [1, 42161, 10, 137, 8453, 146, 2741, 56, 999, 252, 43114];
  
  for (const targetChainId of supportedChainIds) {
    if (targetChainId !== chainId) {
      // This is just for demonstration - in reality, you'd set the actual deployed addresses
      const mockDexAddress = ethers.utils.getAddress(
        ethers.utils.hexlify(ethers.utils.randomBytes(20))
      );
      
      try {
        await torqueDEX.setDEXAddress(targetChainId, mockDexAddress);
        console.log(`Set DEX address for chain ${targetChainId}: ${mockDexAddress}`);
      } catch (error) {
        console.log(`Failed to set DEX address for chain ${targetChainId}:`, error);
      }
    }
  }

  // Mint some tokens to the deployer for testing
  console.log("Minting test tokens...");
  const mintAmount = ethers.utils.parseEther("1000000"); // 1M tokens
  
  await mockToken0.mint(deployer.address, mintAmount);
  await mockToken1.mint(deployer.address, mintAmount);
  
  console.log(`Minted ${ethers.utils.formatEther(mintAmount)} tokens to deployer`);

  // Approve tokens for DEX
  console.log("Approving tokens for DEX...");
  await mockToken0.approve(torqueDEX.address, mintAmount);
  await mockToken1.approve(torqueDEX.address, mintAmount);
  console.log("Tokens approved for DEX");

  // Test single-chain liquidity provision
  console.log("Testing single-chain liquidity provision...");
  const liquidityAmount0 = ethers.utils.parseEther("1000");
  const liquidityAmount1 = ethers.utils.parseEther("1000");
  
  try {
    const tx = await torqueDEX.addLiquidity(
      liquidityAmount0,
      liquidityAmount1,
      -1000, // lowerTick
      1000,  // upperTick
      { gasLimit: 500000 }
    );
    await tx.wait();
    console.log("Single-chain liquidity added successfully");
  } catch (error) {
    console.log("Failed to add single-chain liquidity:", error);
  }

  // Test cross-chain liquidity quote
  console.log("Testing cross-chain liquidity quote...");
  try {
    const dstChainIds = [42161, 137]; // Arbitrum and Polygon
    const adapterParams = [
      ethers.utils.defaultAbiCoder.encode(["uint16", "uint256"], [1, 200000]), // Arbitrum
      ethers.utils.defaultAbiCoder.encode(["uint16", "uint256"], [1, 200000]), // Polygon
    ];
    
    const gasQuote = await torqueDEX.getCrossChainLiquidityQuote(dstChainIds, adapterParams);
    console.log(`Cross-chain liquidity gas quote: ${gasQuote.toString()}`);
  } catch (error) {
    console.log("Failed to get cross-chain liquidity quote:", error);
  }

  console.log("\n=== Deployment Summary ===");
  console.log("Chain ID:", chainId);
  console.log("LayerZero Endpoint:", lzEndpoint);
  console.log("Mock Token 0:", mockToken0.address);
  console.log("Mock Token 1:", mockToken1.address);
  console.log("TorqueDEX:", torqueDEX.address);
  console.log("Owner:", deployer.address);
  
  console.log("\n=== Next Steps ===");
  console.log("1. Deploy TorqueDEX on all supported chains");
  console.log("2. Set the correct DEX addresses for each chain using setDEXAddress()");
  console.log("3. Replace mock tokens with actual token addresses");
  console.log("4. Test cross-chain liquidity provision");
  console.log("5. Configure proper fee recipients and parameters");

  return {
    mockToken0: mockToken0.address,
    mockToken1: mockToken1.address,
    torqueDEX: torqueDEX.address,
    chainId,
    lzEndpoint
  };
}

main()
  .then((result) => {
    console.log("Deployment completed successfully");
    process.exit(0);
  })
  .catch((error) => {
    console.error("Deployment failed:", error);
    process.exit(1);
  }); 