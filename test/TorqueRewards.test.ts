import { expect } from "chai"
import { ethers } from "hardhat"
import { Contract, Signer } from "ethers"
import { loadFixture } from "@nomicfoundation/hardhat-toolbox/network-helpers"

describe("TorqueRewards Enhanced", function () {
  async function deployTorqueRewardsFixture() {
    const [owner, user1, user2, user3, treasury] = await ethers.getSigners()

    const MockERC20 = await ethers.getContractFactory("MockERC20")
    const rewardToken = await MockERC20.deploy("TORQ Token", "TORQ")
    const mockTorqueFX = await MockERC20.deploy("Mock TorqueFX", "TFX")

    const TorqueRewards = await ethers.getContractFactory("TorqueRewards")
    const torqueRewards = await TorqueRewards.deploy(
      await rewardToken.getAddress(),
      await mockTorqueFX.getAddress()
    )

    // Mint tokens to rewards contract
    await rewardToken.mint(await torqueRewards.getAddress(), ethers.parseEther("1000000"))

    return { torqueRewards, rewardToken, mockTorqueFX, owner, user1, user2, user3, treasury }
  }

  describe("Emission Controls", function () {
    it("Should respect daily emission cap", async function () {
      const { torqueRewards, mockTorqueFX, user1 } = await loadFixture(deployTorqueRewardsFixture)

      // Try to award more than daily cap
      const dailyCap = await torqueRewards.MAX_DAILY_EMISSIONS()
      const excessiveReward = dailyCap + ethers.parseEther("1000")

      await expect(
        torqueRewards.connect(mockTorqueFX as any).awardFXTradingReward(
          user1.address,
          excessiveReward,
          ethers.keccak256(ethers.toUtf8Bytes("EUR/USD"))
        )
      ).to.be.revertedWith("Daily emission cap exceeded")
    })

    it("Should respect total emission cap", async function () {
      const { torqueRewards, mockTorqueFX, user1 } = await loadFixture(deployTorqueRewardsFixture)

      // Get emission info
      const emissionInfo = await torqueRewards.getEmissionInfo()
      const totalCap = emissionInfo.maxTotalEmission

      // Award rewards up to the cap
      const rewardAmount = ethers.parseEther("100")
      const maxRewards = totalCap / rewardAmount

      for (let i = 0; i < Number(maxRewards); i++) {
        await torqueRewards.connect(mockTorqueFX as any).awardFXTradingReward(
          user1.address,
          rewardAmount,
          ethers.keccak256(ethers.toUtf8Bytes("EUR/USD"))
        )
      }

      // Next reward should fail
      await expect(
        torqueRewards.connect(mockTorqueFX as any).awardFXTradingReward(
          user1.address,
          rewardAmount,
          ethers.keccak256(ethers.toUtf8Bytes("EUR/USD"))
        )
      ).to.be.revertedWith("Total emission cap exceeded")
    })

    it("Should reset daily cap after 24 hours", async function () {
      const { torqueRewards, mockTorqueFX, user1 } = await loadFixture(deployTorqueRewardsFixture)

      // Award rewards up to daily cap
      const dailyCap = await torqueRewards.MAX_DAILY_EMISSIONS()
      await torqueRewards.connect(mockTorqueFX as any).awardFXTradingReward(
        user1.address,
        dailyCap,
        ethers.keccak256(ethers.toUtf8Bytes("EUR/USD"))
      )

      // Fast forward 24 hours
      await ethers.provider.send("evm_increaseTime", [24 * 60 * 60])
      await ethers.provider.send("evm_mine", [])

      // Should be able to award more rewards
      await torqueRewards.connect(mockTorqueFX as any).awardFXTradingReward(
        user1.address,
        ethers.parseEther("100"),
        ethers.keccak256(ethers.toUtf8Bytes("EUR/USD"))
      )
    })

    it("Should allow owner to pause emissions", async function () {
      const { torqueRewards, mockTorqueFX, user1, owner } = await loadFixture(deployTorqueRewardsFixture)

      // Pause emissions
      await torqueRewards.connect(owner).updateEmissionControl(
        ethers.parseEther("5000"),
        ethers.parseEther("1000000"),
        true
      )

      // Try to award rewards
      await expect(
        torqueRewards.connect(mockTorqueFX).awardFXTradingReward(
          user1.address,
          ethers.parseEther("100"),
          ethers.keccak256(ethers.toUtf8Bytes("EUR/USD"))
        )
      ).to.be.revertedWith("Emission paused")
    })
  })

  describe("Referral System", function () {
    it("Should register referral relationship", async function () {
      const { torqueRewards, mockTorqueFX, user1, user2 } = await loadFixture(deployTorqueRewardsFixture)

      // Register referral
      await torqueRewards.connect(mockTorqueFX).registerReferral(user1.address, user2.address)

      // Check referral info
      const refInfo = await torqueRewards.getReferralInfo(user2.address)
      expect(refInfo.referrer).to.equal(user1.address)
      expect(refInfo.isActive).to.be.true
    })

    it("Should prevent self-referral", async function () {
      const { torqueRewards, mockTorqueFX, user1 } = await loadFixture(deployTorqueRewardsFixture)

      await expect(
        torqueRewards.connect(mockTorqueFX).registerReferral(user1.address, user1.address)
      ).to.be.revertedWith("Cannot refer self")
    })

    it("Should prevent double referral", async function () {
      const { torqueRewards, mockTorqueFX, user1, user2 } = await loadFixture(deployTorqueRewardsFixture)

      // Register referral
      await torqueRewards.connect(mockTorqueFX).registerReferral(user1.address, user2.address)

      // Try to register again
      await expect(
        torqueRewards.connect(mockTorqueFX).registerReferral(user1.address, user2.address)
      ).to.be.revertedWith("Already referred")
    })

    it("Should award referral rewards", async function () {
      const { torqueRewards, mockTorqueFX, user1, user2 } = await loadFixture(deployTorqueRewardsFixture)

      // Register referral
      await torqueRewards.connect(mockTorqueFX).registerReferral(user1.address, user2.address)

      // Award trading reward to referee (should trigger referral reward)
      const tradeVolume = ethers.parseUnits("1000", 6) // 1000 USDC
      await torqueRewards.connect(mockTorqueFX).awardFXTradingReward(
        user2.address,
        tradeVolume,
        ethers.keccak256(ethers.toUtf8Bytes("EUR/USD"))
      )

      // Check referral info
      const refInfo = await torqueRewards.getReferralInfo(user1.address)
      expect(refInfo.totalEarnings).to.be.gt(0)
    })

    it("Should respect referral activity threshold", async function () {
      const { torqueRewards, mockTorqueFX, user1, user2 } = await loadFixture(deployTorqueRewardsFixture)

      // Register referral
      await torqueRewards.connect(mockTorqueFX).registerReferral(user1.address, user2.address)

      // Award small trading reward (below threshold)
      const smallVolume = ethers.parseUnits("50", 6) // 50 USDC (below 100 USDC threshold)
      await torqueRewards.connect(mockTorqueFX).awardFXTradingReward(
        user2.address,
        smallVolume,
        ethers.keccak256(ethers.toUtf8Bytes("EUR/USD"))
      )

      // Check referral info - should not have earned rewards
      const refInfo = await torqueRewards.getReferralInfo(user1.address)
      expect(refInfo.totalEarnings).to.equal(0)
    })
  })

  describe("Vesting System", function () {
    it("Should create vesting schedule for new rewards", async function () {
      const { torqueRewards, mockTorqueFX, user1 } = await loadFixture(deployTorqueRewardsFixture)

      // Award trading reward
      await torqueRewards.connect(mockTorqueFX).awardFXTradingReward(
        user1.address,
        ethers.parseUnits("1000", 6),
        ethers.keccak256(ethers.toUtf8Bytes("EUR/USD"))
      )

      // Check user rewards
      const userRewards = await torqueRewards.getUserRewards(user1.address)
      expect(userRewards.totalVested).to.be.gt(0)
      expect(userRewards.claimableAmount).to.equal(0) // Should be 0 due to cliff
    })

    it("Should respect vesting cliff", async function () {
      const { torqueRewards, mockTorqueFX, user1 } = await loadFixture(deployTorqueRewardsFixture)

      // Award trading reward
      await torqueRewards.connect(mockTorqueFX).awardFXTradingReward(
        user1.address,
        ethers.parseUnits("1000", 6),
        ethers.keccak256(ethers.toUtf8Bytes("EUR/USD"))
      )

      // Fast forward 15 days (before cliff)
      await ethers.provider.send("evm_increaseTime", [15 * 24 * 60 * 60])
      await ethers.provider.send("evm_mine", [])

      // Should not be able to claim
      const userRewards = await torqueRewards.getUserRewards(user1.address)
      expect(userRewards.claimableAmount).to.equal(0)
    })

    it("Should allow partial claiming after cliff", async function () {
      const { torqueRewards, mockTorqueFX, user1 } = await loadFixture(deployTorqueRewardsFixture)

      // Award trading reward
      await torqueRewards.connect(mockTorqueFX).awardFXTradingReward(
        user1.address,
        ethers.parseUnits("1000", 6),
        ethers.keccak256(ethers.toUtf8Bytes("EUR/USD"))
      )

      // Fast forward 60 days (after cliff, partial vesting)
      await ethers.provider.send("evm_increaseTime", [60 * 24 * 60 * 60])
      await ethers.provider.send("evm_mine", [])

      // Should be able to claim partial amount
      const userRewards = await torqueRewards.getUserRewards(user1.address)
      expect(userRewards.claimableAmount).to.be.gt(0)

      // Claim rewards
      const balanceBefore = await torqueRewards.rewardToken().balanceOf(user1.address)
      await torqueRewards.connect(user1).claimRewards()
      const balanceAfter = await torqueRewards.rewardToken().balanceOf(user1.address)

      expect(balanceAfter).to.be.gt(balanceBefore)
    })

    it("Should allow full claiming after vesting period", async function () {
      const { torqueRewards, mockTorqueFX, user1 } = await loadFixture(deployTorqueRewardsFixture)

      // Award trading reward
      await torqueRewards.connect(mockTorqueFX).awardFXTradingReward(
        user1.address,
        ethers.parseUnits("1000", 6),
        ethers.keccak256(ethers.toUtf8Bytes("EUR/USD"))
      )

      // Fast forward 1 year (full vesting)
      await ethers.provider.send("evm_increaseTime", [365 * 24 * 60 * 60])
      await ethers.provider.send("evm_mine", [])

      // Should be able to claim full amount
      const userRewards = await torqueRewards.getUserRewards(user1.address)
      expect(userRewards.claimableAmount).to.equal(userRewards.totalVested)

      // Claim rewards
      const balanceBefore = await torqueRewards.rewardToken().balanceOf(user1.address)
      await torqueRewards.connect(user1).claimRewards()
      const balanceAfter = await torqueRewards.rewardToken().balanceOf(user1.address)

      expect(balanceAfter - balanceBefore).to.equal(userRewards.totalVested)
    })
  })

  describe("Reduced Reward Rates", function () {
    it("Should use reduced FX trading reward rate", async function () {
      const { torqueRewards, mockTorqueFX, user1 } = await loadFixture(deployTorqueRewardsFixture)

      // Award trading reward
      const tradeVolume = ethers.parseUnits("1000", 6) // 1000 USDC
      await torqueRewards.connect(mockTorqueFX).awardFXTradingReward(
        user1.address,
        tradeVolume,
        ethers.keccak256(ethers.toUtf8Bytes("EUR/USD"))
      )

      // Check user rewards - should be lower than before
      const userRewards = await torqueRewards.getUserRewards(user1.address)
      expect(userRewards.totalVested).to.be.gt(0)
      expect(userRewards.totalVested).to.be.lt(ethers.parseEther("10")) // Should be much lower than old rates
    })

    it("Should use reduced liquidity provision reward rate", async function () {
      const { torqueRewards, mockTorqueFX, user1 } = await loadFixture(deployTorqueRewardsFixture)

      // Award liquidity reward
      const liquidityAmount = ethers.parseUnits("1000", 6) // 1000 USDC
      await torqueRewards.connect(mockTorqueFX).awardLiquidityReward(
        user1.address,
        liquidityAmount,
        ethers.ZeroAddress
      )

      // Check user rewards
      const userRewards = await torqueRewards.getUserRewards(user1.address)
      expect(userRewards.totalVested).to.be.gt(0)
      expect(userRewards.totalVested).to.be.lt(ethers.parseEther("10")) // Should be much lower than old rates
    })

    it("Should use reduced staking reward rate", async function () {
      const { torqueRewards, mockTorqueFX, user1 } = await loadFixture(deployTorqueRewardsFixture)

      // Award staking reward
      const stakedAmount = ethers.parseEther("100") // 100 TORQ
      await torqueRewards.connect(mockTorqueFX).awardStakingReward(
        user1.address,
        stakedAmount,
        365 * 24 * 60 * 60 // 1 year lock
      )

      // Check user rewards
      const userRewards = await torqueRewards.getUserRewards(user1.address)
      expect(userRewards.totalVested).to.be.gt(0)
      expect(userRewards.totalVested).to.be.lt(ethers.parseEther("10")) // Should be much lower than old rates
    })
  })

  describe("Volume Tiers", function () {
    it("Should apply volume tier multipliers", async function () {
      const { torqueRewards, mockTorqueFX, user1 } = await loadFixture(deployTorqueRewardsFixture)

      // Award multiple trading rewards to increase volume
      for (let i = 0; i < 10; i++) {
        await torqueRewards.connect(mockTorqueFX).awardFXTradingReward(
          user1.address,
          ethers.parseUnits("10000", 6), // 10k USDC per trade
          ethers.keccak256(ethers.toUtf8Bytes("EUR/USD"))
        )
      }

      // Check volume tier
      const volumeTier = await torqueRewards.getVolumeTier(user1.address)
      expect(volumeTier.tierName).to.equal("Silver") // Should be Silver tier (100k+ volume)
      expect(volumeTier.multiplier).to.equal(125) // 1.25x multiplier
    })
  })

  describe("Activity Score", function () {
    it("Should update activity score", async function () {
      const { torqueRewards, mockTorqueFX, user1 } = await loadFixture(deployTorqueRewardsFixture)

      // Award trading reward
      await torqueRewards.connect(mockTorqueFX).awardFXTradingReward(
        user1.address,
        ethers.parseUnits("1000", 6),
        ethers.keccak256(ethers.toUtf8Bytes("EUR/USD"))
      )

      // Check activity score
      const userRewards = await torqueRewards.getUserRewards(user1.address)
      expect(userRewards.activityScore).to.be.gt(0)
    })

    it("Should decay activity score over time", async function () {
      const { torqueRewards, mockTorqueFX, user1 } = await loadFixture(deployTorqueRewardsFixture)

      // Award trading reward
      await torqueRewards.connect(mockTorqueFX).awardFXTradingReward(
        user1.address,
        ethers.parseUnits("1000", 6),
        ethers.keccak256(ethers.toUtf8Bytes("EUR/USD"))
      )

      // Get initial activity score
      const initialScore = (await torqueRewards.getUserRewards(user1.address)).activityScore

      // Fast forward 2 days
      await ethers.provider.send("evm_increaseTime", [2 * 24 * 60 * 60])
      await ethers.provider.send("evm_mine", [])

      // Award another reward to trigger decay
      await torqueRewards.connect(mockTorqueFX).awardFXTradingReward(
        user1.address,
        ethers.parseUnits("1000", 6),
        ethers.keccak256(ethers.toUtf8Bytes("EUR/USD"))
      )

      // Check activity score - should be lower due to decay
      const finalScore = (await torqueRewards.getUserRewards(user1.address)).activityScore
      expect(finalScore).to.be.lt(initialScore + 10) // Should be less than initial + new points
    })
  })

  describe("Owner Functions", function () {
    it("Should allow owner to update reward config", async function () {
      const { torqueRewards, owner } = await loadFixture(deployTorqueRewardsFixture)

      // Update FX trading reward config
      await torqueRewards.connect(owner).updateRewardConfig(
        0, // FX_TRADING
        20, // new base rate
        100, // multiplier
        ethers.parseEther("200"), // new cap
        true // active
      )

      // Verify update
      const config = await torqueRewards.rewardConfigs(0)
      expect(config.baseRate).to.equal(20)
      expect(config.cap).to.equal(ethers.parseEther("200"))
    })

    it("Should allow owner to update emission control", async function () {
      const { torqueRewards, owner } = await loadFixture(deployTorqueRewardsFixture)

      // Update emission control
      await torqueRewards.connect(owner).updateEmissionControl(
        ethers.parseEther("3000"), // new daily cap
        ethers.parseEther("500000"), // new total cap
        false // not paused
      )

      // Verify update
      const emissionInfo = await torqueRewards.getEmissionInfo()
      expect(emissionInfo.dailyEmissionCap).to.equal(ethers.parseEther("3000"))
      expect(emissionInfo.maxTotalEmission).to.equal(ethers.parseEther("500000"))
      expect(emissionInfo.emissionPaused).to.be.false
    })

    it("Should prevent non-owner from updating config", async function () {
      const { torqueRewards, user1 } = await loadFixture(deployTorqueRewardsFixture)

      await expect(
        torqueRewards.connect(user1).updateRewardConfig(
          0, // FX_TRADING
          20, // new base rate
          100, // multiplier
          ethers.parseEther("200"), // new cap
          true // active
        )
      ).to.be.revertedWithCustomError(torqueRewards, "OwnableUnauthorizedAccount")
    })
  })
}) 