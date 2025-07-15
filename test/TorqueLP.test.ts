import { expect } from "chai"
import { ethers } from "hardhat"
import { Contract, Signer } from "ethers"
import { loadFixture } from "@nomicfoundation/hardhat-toolbox/network-helpers"

describe("TorqueLP", function () {
  async function deployTorqueLPFixture() {
    const [owner, user1, user2, dex] = await ethers.getSigners()

    const TorqueLP = await ethers.getContractFactory("TorqueLP")
    const torqueLP = await TorqueLP.deploy(
      "Torque LP Token",
      "TLP",
      "0x0000000000000000000000000000000000000000", // Mock LZ endpoint
      owner.address
    )

    // Set DEX address
    await torqueLP.connect(owner).setDEX(dex.address)

    return { torqueLP, owner, user1, user2, dex }
  }

  describe("Supply Tracking with Events", function () {
    it("Should track total supply correctly when minting", async function () {
      const { torqueLP, dex, user1 } = await loadFixture(deployTorqueLPFixture)

      const mintAmount = ethers.parseEther("1000")
      
      // Mint tokens and expect event
      await expect(torqueLP.connect(dex).mint(user1.address, mintAmount))
        .to.emit(torqueLP, "SupplyMinted")
        .withArgs(user1.address, mintAmount, mintAmount)

      // Check total supply
      expect(await torqueLP.totalSupply()).to.equal(mintAmount)
      expect(await torqueLP.getLPStats()).to.deep.include({
        supply: mintAmount
      })
    })

    it("Should track total supply correctly when burning", async function () {
      const { torqueLP, dex, user1 } = await loadFixture(deployTorqueLPFixture)

      const mintAmount = ethers.parseEther("1000")
      const burnAmount = ethers.parseEther("300")
      
      // Mint first
      await torqueLP.connect(dex).mint(user1.address, mintAmount)
      
      // Burn tokens and expect event
      await expect(torqueLP.connect(dex).burn(user1.address, burnAmount))
        .to.emit(torqueLP, "SupplyBurned")
        .withArgs(user1.address, burnAmount, mintAmount - burnAmount)

      // Check total supply
      expect(await torqueLP.totalSupply()).to.equal(mintAmount - burnAmount)
      expect(await torqueLP.getLPStats()).to.deep.include({
        supply: mintAmount - burnAmount
      })
    })

    it("Should track multiple mint/burn operations", async function () {
      const { torqueLP, dex, user1, user2 } = await loadFixture(deployTorqueLPFixture)

      // Multiple mint operations
      await torqueLP.connect(dex).mint(user1.address, ethers.parseEther("500"))
      await torqueLP.connect(dex).mint(user2.address, ethers.parseEther("300"))
      
      // Check total supply after mints
      expect(await torqueLP.totalSupply()).to.equal(ethers.parseEther("800"))

      // Burn operations
      await torqueLP.connect(dex).burn(user1.address, ethers.parseEther("100"))
      
      // Check total supply after burn
      expect(await torqueLP.totalSupply()).to.equal(ethers.parseEther("700"))

      // Final stats
      const stats = await torqueLP.getLPStats()
      expect(stats.supply).to.equal(ethers.parseEther("700"))
    })

    it("Should emit correct events for all supply changes", async function () {
      const { torqueLP, dex, user1 } = await loadFixture(deployTorqueLPFixture)

      const mintAmount = ethers.parseEther("1000")
      const burnAmount = ethers.parseEther("400")

      // Mint and verify event
      const mintTx = await torqueLP.connect(dex).mint(user1.address, mintAmount)
      const mintReceipt = await mintTx.wait()
      
      const mintEvent = mintReceipt?.logs.find(
        log => log.topics[0] === torqueLP.interface.getEventTopic("SupplyMinted")
      )
      expect(mintEvent).to.not.be.undefined

      // Burn and verify event
      const burnTx = await torqueLP.connect(dex).burn(user1.address, burnAmount)
      const burnReceipt = await burnTx.wait()
      
      const burnEvent = burnReceipt?.logs.find(
        log => log.topics[0] === torqueLP.interface.getEventTopic("SupplyBurned")
      )
      expect(burnEvent).to.not.be.undefined
    })
  })

  describe("User Share Calculation", function () {
    it("Should calculate user share correctly", async function () {
      const { torqueLP, dex, user1, user2 } = await loadFixture(deployTorqueLPFixture)

      // Mint tokens to two users
      await torqueLP.connect(dex).mint(user1.address, ethers.parseEther("600"))
      await torqueLP.connect(dex).mint(user2.address, ethers.parseEther("400"))

      // Get user info
      const user1Info = await torqueLP.getUserLPInfo(user1.address)
      const user2Info = await torqueLP.getUserLPInfo(user2.address)

      // User1 should have 60% share (600/1000 * 10000 = 6000 basis points)
      expect(user1Info.userShare).to.equal(6000)
      
      // User2 should have 40% share (400/1000 * 10000 = 4000 basis points)
      expect(user2Info.userShare).to.equal(4000)

      // Verify balances
      expect(user1Info.balance).to.equal(ethers.parseEther("600"))
      expect(user2Info.balance).to.equal(ethers.parseEther("400"))
      expect(user1Info.supply).to.equal(ethers.parseEther("1000"))
      expect(user2Info.supply).to.equal(ethers.parseEther("1000"))
    })

    it("Should handle zero supply correctly", async function () {
      const { torqueLP, user1 } = await loadFixture(deployTorqueLPFixture)

      // Get user info with zero supply
      const userInfo = await torqueLP.getUserLPInfo(user1.address)

      expect(userInfo.balance).to.equal(0)
      expect(userInfo.supply).to.equal(0)
      expect(userInfo.userShare).to.equal(0)
    })
  })

  describe("Cross-Chain Supply Info", function () {
    it("Should return cross-chain supply information", async function () {
      const { torqueLP, dex, user1 } = await loadFixture(deployTorqueLPFixture)

      const mintAmount = ethers.parseEther("1000")
      await torqueLP.connect(dex).mint(user1.address, mintAmount)

      const crossChainInfo = await torqueLP.getCrossChainSupplyInfo()

      expect(crossChainInfo.localSupply).to.equal(mintAmount)
      expect(crossChainInfo.totalSupply).to.equal(mintAmount)
      expect(crossChainInfo.isCrossChainEnabled).to.be.true
    })
  })

  describe("Access Control", function () {
    it("Should only allow DEX to mint", async function () {
      const { torqueLP, user1 } = await loadFixture(deployTorqueLPFixture)

      await expect(
        torqueLP.connect(user1).mint(user1.address, ethers.parseEther("100"))
      ).to.be.revertedWith("Only DEX can mint")
    })

    it("Should only allow DEX to burn", async function () {
      const { torqueLP, dex, user1 } = await loadFixture(deployTorqueLPFixture)

      // Mint first
      await torqueLP.connect(dex).mint(user1.address, ethers.parseEther("100"))

      // Try to burn from non-DEX
      await expect(
        torqueLP.connect(user1).burn(user1.address, ethers.parseEther("50"))
      ).to.be.revertedWith("Only DEX can burn")
    })

    it("Should only allow owner to set DEX", async function () {
      const { torqueLP, user1 } = await loadFixture(deployTorqueLPFixture)

      await expect(
        torqueLP.connect(user1).setDEX(user1.address)
      ).to.be.revertedWithCustomError(torqueLP, "OwnableUnauthorizedAccount")
    })
  })

  describe("DEX Management", function () {
    it("Should allow owner to update DEX address", async function () {
      const { torqueLP, owner, user1 } = await loadFixture(deployTorqueLPFixture)

      await expect(torqueLP.connect(owner).setDEX(user1.address))
        .to.emit(torqueLP, "DEXUpdated")
        .withArgs(await torqueLP.dex(), user1.address)

      expect(await torqueLP.dex()).to.equal(user1.address)
    })

    it("Should prevent setting zero address as DEX", async function () {
      const { torqueLP, owner } = await loadFixture(deployTorqueLPFixture)

      await expect(
        torqueLP.connect(owner).setDEX(ethers.ZeroAddress)
      ).to.be.revertedWith("Invalid DEX address")
    })
  })

  describe("Event Verification", function () {
    it("Should verify total supply from events matches tracked supply", async function () {
      const { torqueLP, dex, user1 } = await loadFixture(deployTorqueLPFixture)

      const mintAmount = ethers.parseEther("1000")
      await torqueLP.connect(dex).mint(user1.address, mintAmount)

      // Both should return the same value
      expect(await torqueLP.totalSupply()).to.equal(await torqueLP.getTotalSupplyFromEvents())
    })
  })
}) 