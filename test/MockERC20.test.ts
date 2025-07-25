import { expect } from "chai";
import { ethers } from "hardhat";
import { SignerWithAddress } from "@nomicfoundation/hardhat-ethers/signers";

describe("MockERC20", function () {
  let mockToken: any;
  let owner: SignerWithAddress;
  let user1: SignerWithAddress;
  let user2: SignerWithAddress;

  beforeEach(async function () {
    [owner, user1, user2] = await ethers.getSigners();

    const MockERC20 = await ethers.getContractFactory("MockERC20");
    mockToken = await MockERC20.deploy("Mock Token", "MTK", 18);
    await mockToken.waitForDeployment();
  });

  describe("Deployment", function () {
    it("Should deploy with correct name and symbol", async function () {
      expect(await mockToken.name()).to.equal("Mock Token");
      expect(await mockToken.symbol()).to.equal("MTK");
      expect(await mockToken.decimals()).to.equal(18);
    });

    it("Should have correct initial supply", async function () {
      expect(await mockToken.totalSupply()).to.equal(0);
    });
  });

  describe("Minting", function () {
    it("Should allow minting tokens", async function () {
      const amount = ethers.parseEther("1000");
      await mockToken.mint(user1.address, amount);
      
      expect(await mockToken.balanceOf(user1.address)).to.equal(amount);
      expect(await mockToken.totalSupply()).to.equal(amount);
    });

    it("Should allow minting to multiple users", async function () {
      const amount1 = ethers.parseEther("500");
      const amount2 = ethers.parseEther("300");
      
      await mockToken.mint(user1.address, amount1);
      await mockToken.mint(user2.address, amount2);
      
      expect(await mockToken.balanceOf(user1.address)).to.equal(amount1);
      expect(await mockToken.balanceOf(user2.address)).to.equal(amount2);
      expect(await mockToken.totalSupply()).to.equal(amount1 + amount2);
    });
  });

  describe("Transfer", function () {
    beforeEach(async function () {
      await mockToken.mint(user1.address, ethers.parseEther("1000"));
    });

    it("Should allow transfer between users", async function () {
      const transferAmount = ethers.parseEther("100");
      await mockToken.connect(user1).transfer(user2.address, transferAmount);
      
      expect(await mockToken.balanceOf(user1.address)).to.equal(ethers.parseEther("900"));
      expect(await mockToken.balanceOf(user2.address)).to.equal(transferAmount);
    });

    it("Should fail transfer with insufficient balance", async function () {
      const transferAmount = ethers.parseEther("2000");
      await expect(
        mockToken.connect(user1).transfer(user2.address, transferAmount)
      ).to.be.revertedWithCustomError(mockToken, "ERC20InsufficientBalance");
    });
  });

  describe("Approve and TransferFrom", function () {
    beforeEach(async function () {
      await mockToken.mint(user1.address, ethers.parseEther("1000"));
    });

    it("Should allow approve and transferFrom", async function () {
      const approveAmount = ethers.parseEther("500");
      const transferAmount = ethers.parseEther("200");
      
      await mockToken.connect(user1).approve(user2.address, approveAmount);
      expect(await mockToken.allowance(user1.address, user2.address)).to.equal(approveAmount);
      
      await mockToken.connect(user2).transferFrom(user1.address, user2.address, transferAmount);
      expect(await mockToken.balanceOf(user2.address)).to.equal(transferAmount);
      expect(await mockToken.allowance(user1.address, user2.address)).to.equal(approveAmount - transferAmount);
    });

    it("Should fail transferFrom with insufficient allowance", async function () {
      const approveAmount = ethers.parseEther("100");
      const transferAmount = ethers.parseEther("200");
      
      await mockToken.connect(user1).approve(user2.address, approveAmount);
      
      await expect(
        mockToken.connect(user2).transferFrom(user1.address, user2.address, transferAmount)
      ).to.be.revertedWithCustomError(mockToken, "ERC20InsufficientAllowance");
    });
  });
}); 