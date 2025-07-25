import { expect } from "chai"
import { ethers } from "hardhat"
import { Contract, Signer } from "ethers"
import { loadFixture } from "@nomicfoundation/hardhat-toolbox/network-helpers"

describe("TorqueStake", function () {
  async function deployTorqueStakeFixture() {
    const [owner, user1, user2, treasury] = await ethers.getSigners()

    const MockERC20 = await ethers.getContractFactory("MockERC20")
    const lpToken = await MockERC20.deploy("LP Token", "LP", 18)
    const torqToken = await MockERC20.deploy("TORQ Token", "TORQ", 18)
    const rewardToken = await MockERC20.deploy("Reward Token", "REWARD", 18)

    const MockTorqueStake = await ethers.getContractFactory("MockTorqueStake")
    const torqueStake: any = await MockTorqueStake.deploy(
      await lpToken.getAddress(),
      await torqToken.getAddress(),
      await rewardToken.getAddress(),
      treasury.address,
      owner.address
    )

    // Mint tokens to users
    await lpToken.mint(user1.address, ethers.parseEther("1000"))
    await torqToken.mint(user1.address, ethers.parseEther("1000"))
    await rewardToken.mint(await torqueStake.getAddress(), ethers.parseEther("1000000"))

    // Approve tokens
    await lpToken.connect(user1).approve(await torqueStake.getAddress(), ethers.parseEther("1000"))
    await torqToken.connect(user1).approve(await torqueStake.getAddress(), ethers.parseEther("1000"))

    return { torqueStake, lpToken, torqToken, rewardToken, owner, user1, user2, treasury }
  }

  describe("Staking Multipliers", function () {
    it("Should calculate correct multipliers for different lock periods", async function () {
      const { torqueStake } = await loadFixture(deployTorqueStakeFixture)

      // Test multipliers for different lock periods (matching frontend expectations)
      const testCases = [
        { days: 30, expectedMultiplier: 1.0 },   // 1.0x
        { days: 90, expectedMultiplier: 1.5 },   // 1.5x
        { days: 180, expectedMultiplier: 2.0 },  // 2.0x
        { days: 365, expectedMultiplier: 2.5 },  // 2.5x
        { days: 730, expectedMultiplier: 3.0 },  // 3.0x
        { days: 1095, expectedMultiplier: 3.5 }, // 3.5x
        { days: 1460, expectedMultiplier: 4.0 }, // 4.0x
        { days: 1825, expectedMultiplier: 4.5 }, // 4.5x
        { days: 2190, expectedMultiplier: 5.0 }, // 5.0x
        { days: 2555, expectedMultiplier: 5.0 }, // 5.0x (max)
      ]

      for (const testCase of testCases) {
        const lockDuration = testCase.days * 24 * 60 * 60 // Convert days to seconds
        const multiplier = await torqueStake.getStakeMultiplier(lockDuration)
        const multiplierValue = Number(ethers.formatEther(multiplier))
        
        // Allow for small rounding differences (within 0.1)
        expect(multiplierValue).to.be.closeTo(testCase.expectedMultiplier, 0.1)
      }
    })

    it("Should return 1x multiplier for minimum lock duration", async function () {
      const { torqueStake } = await loadFixture(deployTorqueStakeFixture)
      
      const minLockDuration = 7 * 24 * 60 * 60 // 7 days in seconds
      const multiplier = await torqueStake.getStakeMultiplier(minLockDuration)
      const multiplierValue = Number(ethers.formatEther(multiplier))
      
      expect(multiplierValue).to.be.closeTo(1.0, 0.01)
    })

    it("Should return 5x multiplier for maximum lock duration", async function () {
      const { torqueStake } = await loadFixture(deployTorqueStakeFixture)
      
      const maxLockDuration = 7 * 365 * 24 * 60 * 60 // 7 years in seconds
      const multiplier = await torqueStake.getStakeMultiplier(maxLockDuration)
      const multiplierValue = Number(ethers.formatEther(multiplier))
      
      expect(multiplierValue).to.be.closeTo(5.0, 0.01)
    })

    it("Should return 1x multiplier for lock duration below minimum", async function () {
      const { torqueStake } = await loadFixture(deployTorqueStakeFixture)
      
      const shortLockDuration = 1 * 24 * 60 * 60 // 1 day in seconds
      const multiplier = await torqueStake.getStakeMultiplier(shortLockDuration)
      const multiplierValue = Number(ethers.formatEther(multiplier))
      
      expect(multiplierValue).to.be.closeTo(1.0, 0.01)
    })

    it("Should return 5x multiplier for lock duration above maximum", async function () {
      const { torqueStake } = await loadFixture(deployTorqueStakeFixture)
      
      const longLockDuration = 10 * 365 * 24 * 60 * 60 // 10 years in seconds
      const multiplier = await torqueStake.getStakeMultiplier(longLockDuration)
      const multiplierValue = Number(ethers.formatEther(multiplier))
      
      expect(multiplierValue).to.be.closeTo(5.0, 0.01)
    })
  })

  describe("Staking with Multipliers", function () {
    it("Should stake TORQ tokens and return correct multiplier in stake info", async function () {
      const { torqueStake, user1, torqToken } = await loadFixture(deployTorqueStakeFixture)
      
      const stakeAmount = ethers.parseEther("100")
      const lockDuration = 365 * 24 * 60 * 60 // 365 days
      
      await torqueStake.connect(user1).stakeTORQ(stakeAmount, lockDuration)
      
      const stakeInfo = await torqueStake.getStakeInfo(user1.address)
      const multiplier = Number(ethers.formatEther(stakeInfo.multiplier))
      
      // Should be close to 2.5x for 365 days
      expect(multiplier).to.be.closeTo(2.5, 0.1)
    })

    it("Should stake LP tokens and return correct multiplier in stake info", async function () {
      const { torqueStake, user1, lpToken } = await loadFixture(deployTorqueStakeFixture)
      
      const stakeAmount = ethers.parseEther("100")
      const lockDuration = 730 * 24 * 60 * 60 // 730 days
      
      await torqueStake.connect(user1).stakeLP(stakeAmount, lockDuration)
      
      const stakeInfo = await torqueStake.getStakeInfo(user1.address)
      const multiplier = Number(ethers.formatEther(stakeInfo.multiplier))
      
      // Should be close to 3.0x for 730 days
      expect(multiplier).to.be.closeTo(3.0, 0.1)
    })
  })

  describe("Vote Power with Updated Multipliers", function () {
    it("Should calculate vote power with 5x multiplier for maximum lock", async function () {
      const { torqueStake, user1 } = await loadFixture(deployTorqueStakeFixture)
      
      const stakeAmount = ethers.parseEther("100")
      const maxLockDuration = 7 * 365 * 24 * 60 * 60 // 7 years
      
      await torqueStake.connect(user1).stakeTORQ(stakeAmount, maxLockDuration)
      
      const votePower = await torqueStake.getVotePower(user1.address)
      
      // Vote power should be 5x the staked amount for maximum lock
      expect(votePower).to.equal(stakeAmount * 5n)
    })

    it("Should calculate vote power with 1x multiplier for minimum lock", async function () {
      const { torqueStake, user1 } = await loadFixture(deployTorqueStakeFixture)
      
      const stakeAmount = ethers.parseEther("100")
      const minLockDuration = 7 * 24 * 60 * 60 // 7 days
      
      await torqueStake.connect(user1).stakeTORQ(stakeAmount, minLockDuration)
      
      const votePower = await torqueStake.getVotePower(user1.address)
      
      // Vote power should be 1x the staked amount for minimum lock
      expect(votePower).to.equal(stakeAmount)
    })
  })
}) 