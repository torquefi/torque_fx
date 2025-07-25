import { expect } from "chai"
import { ethers } from "hardhat"
import { Contract, Signer } from "ethers"
import { loadFixture } from "@nomicfoundation/hardhat-toolbox/network-helpers"

describe("TorqueRewards Enhanced", function () {
  async function deployTorqueRewardsFixture() {
    const [owner, user1, user2, user3, treasury] = await ethers.getSigners()

    const MockERC20 = await ethers.getContractFactory("MockERC20")
    const rewardToken = await MockERC20.deploy("TORQ Token", "TORQ", 18)
    const usdc = await MockERC20.deploy("USDC", "USDC", 6)
    
    // Deploy TorqueFX contract with owner as the caller
    const TorqueFX = await ethers.getContractFactory("TorqueFX")
    const torqueFX = await TorqueFX.deploy(owner.address, await usdc.getAddress())

    const TorqueRewards = await ethers.getContractFactory("TorqueRewards")
    const torqueRewards = await TorqueRewards.deploy(
      await rewardToken.getAddress(),
      await torqueFX.getAddress()
    )

    // Mint tokens to rewards contract
    await rewardToken.mint(await torqueRewards.getAddress(), ethers.parseEther("1000000"))

    return { torqueRewards, rewardToken, torqueFX, usdc, owner, user1, user2, user3, treasury }
  }

  describe("Owner Functions", function () {
    it("Should allow owner to update reward config", async function () {
      const { torqueRewards, owner } = await loadFixture(deployTorqueRewardsFixture)

      // Update FX trading reward config
      await torqueRewards.connect(owner).updateRewardConfig(
        0, // FX_TRADING
        20, // new base rate (0.2%)
        150, // new multiplier (1.5x)
        ethers.parseEther("200"), // new cap
        true // active
      )

      // Verify the config was updated
      const config = await torqueRewards.rewardConfigs(0)
      expect(config.baseRate).to.equal(20)
      expect(config.multiplier).to.equal(150)
      expect(config.cap).to.equal(ethers.parseEther("200"))
    })

    it("Should allow owner to update emission control", async function () {
      const { torqueRewards, owner } = await loadFixture(deployTorqueRewardsFixture)

      // Update emission control
      await torqueRewards.connect(owner).updateEmissionControl(
        ethers.parseEther("5000"), // new daily cap
        ethers.parseEther("1000000"), // new total cap
        false // don't pause
      )

      // Verify the emission control was updated
      const emissionInfo = await torqueRewards.getEmissionInfo()
      expect(emissionInfo.dailyEmissionCap).to.equal(ethers.parseEther("5000"))
      expect(emissionInfo.maxTotalEmission).to.equal(ethers.parseEther("1000000"))
      expect(emissionInfo.emissionPaused).to.equal(false)
    })

    it("Should prevent non-owner from updating config", async function () {
      const { torqueRewards, user1 } = await loadFixture(deployTorqueRewardsFixture)

      await expect(
        torqueRewards.connect(user1).updateRewardConfig(
          0, // FX_TRADING
          20, // new base rate
          150, // new multiplier
          ethers.parseEther("200"), // new cap
          true // active
        )
      ).to.be.revertedWithCustomError(torqueRewards, "OwnableUnauthorizedAccount")
    })

    it("Should allow owner to pause and unpause rewards", async function () {
      const { torqueRewards, owner } = await loadFixture(deployTorqueRewardsFixture)

      // Pause rewards
      await torqueRewards.connect(owner).pause()
      expect(await torqueRewards.paused()).to.be.true

      // Unpause rewards
      await torqueRewards.connect(owner).unpause()
      expect(await torqueRewards.paused()).to.be.false
    })

    it("Should get correct reward configs", async function () {
      const { torqueRewards } = await loadFixture(deployTorqueRewardsFixture)

      // Check FX trading config
      const fxConfig = await torqueRewards.rewardConfigs(0)
      expect(fxConfig.baseRate).to.equal(15) // 0.15%
      expect(fxConfig.multiplier).to.equal(100) // 1x
      expect(fxConfig.cap).to.equal(ethers.parseEther("100")) // 100 TORQ
      expect(fxConfig.active).to.be.true

      // Check liquidity provision config
      const lpConfig = await torqueRewards.rewardConfigs(1)
      expect(lpConfig.baseRate).to.equal(30) // 0.3%
      expect(lpConfig.multiplier).to.equal(100) // 1x
      expect(lpConfig.cap).to.equal(ethers.parseEther("200")) // 200 TORQ
      expect(lpConfig.active).to.be.true
    })

    it("Should get correct emission info", async function () {
      const { torqueRewards } = await loadFixture(deployTorqueRewardsFixture)

      const emissionInfo = await torqueRewards.getEmissionInfo()
      expect(emissionInfo.dailyEmissionCap).to.equal(ethers.parseEther("5000")) // 5k TORQ per day
      expect(emissionInfo.maxTotalEmission).to.equal(ethers.parseEther("1000000")) // 1M TORQ total
      expect(emissionInfo.emissionPaused).to.equal(false)
      expect(emissionInfo.currentDayEmitted).to.equal(0)
    })

    it("Should get user volume tier", async function () {
      const { torqueRewards, user1 } = await loadFixture(deployTorqueRewardsFixture)

      const tierInfo = await torqueRewards.getVolumeTier(user1.address)
      expect(tierInfo.tierName).to.equal("Bronze") // Default tier
      expect(tierInfo.multiplier).to.equal(100) // 1x multiplier
      expect(tierInfo.currentVolume).to.equal(0) // No volume yet
    })
  })
}) 