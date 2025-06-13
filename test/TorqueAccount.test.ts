import { expect } from "chai";
import { ethers } from "hardhat";
import { Contract } from "ethers";

describe("TorqueAccount", function () {
  let torqueAccount: Contract;
  let owner: any;
  let user: any;
  let referrer: any;

  beforeEach(async function () {
    [owner, user, referrer] = await ethers.getSigners();
    const TorqueAccount = await ethers.getContractFactory("TorqueAccount");
    torqueAccount = await TorqueAccount.deploy();
    await torqueAccount.deployed();
  });

  describe("Account Creation", function () {
    it("should create a new account", async function () {
      await torqueAccount.connect(user).createAccount(2000, false, "testuser", ethers.ZeroAddress);
      const account = await torqueAccount.userAccounts(user.address, 1);
      expect(account.leverage).to.equal(2000);
      expect(account.exists).to.be.true;
      expect(account.isDemo).to.be.false;
      expect(account.active).to.be.true;
      expect(account.username).to.equal("testuser");
    });

    it("should create a demo account", async function () {
      await torqueAccount.connect(user).createAccount(1000, true, "demouser", ethers.ZeroAddress);
      const account = await torqueAccount.userAccounts(user.address, 1);
      expect(account.isDemo).to.be.true;
    });

    it("should create account with referrer", async function () {
      await torqueAccount.connect(user).createAccount(2000, false, "testuser", referrer.address);
      const account = await torqueAccount.userAccounts(user.address, 1);
      expect(account.referrer).to.equal(referrer.address);
      
      const referrals = await torqueAccount.referralsOf(referrer.address);
      expect(referrals[0]).to.equal(user.address);
    });

    it("should not allow duplicate usernames", async function () {
      await torqueAccount.connect(user).createAccount(2000, false, "testuser", ethers.ZeroAddress);
      await expect(
        torqueAccount.connect(referrer).createAccount(2000, false, "testuser", ethers.ZeroAddress)
      ).to.be.revertedWith("Username taken");
    });

    it("should not allow self-referral", async function () {
      await expect(
        torqueAccount.connect(user).createAccount(2000, false, "testuser", user.address)
      ).to.be.revertedWith("Cannot refer self");
    });
  });

  describe("Account Management", function () {
    beforeEach(async function () {
      await torqueAccount.connect(user).createAccount(2000, false, "testuser", ethers.ZeroAddress);
    });

    it("should update leverage", async function () {
      await torqueAccount.connect(user).updateLeverage(1, 3000);
      const account = await torqueAccount.userAccounts(user.address, 1);
      expect(account.leverage).to.equal(3000);
    });

    it("should change username", async function () {
      await torqueAccount.connect(user).changeUsername(1, "newuser");
      const account = await torqueAccount.userAccounts(user.address, 1);
      expect(account.username).to.equal("newuser");
    });

    it("should disable account", async function () {
      await torqueAccount.connect(user).disableAccount(1);
      const account = await torqueAccount.userAccounts(user.address, 1);
      expect(account.active).to.be.false;
    });

    it("should not allow invalid leverage", async function () {
      await expect(
        torqueAccount.connect(user).updateLeverage(1, 500)
      ).to.be.revertedWith("Leverage 1x to 100x");
    });

    it("should not allow invalid username length", async function () {
      await expect(
        torqueAccount.connect(user).createAccount(2000, false, "ab", ethers.ZeroAddress)
      ).to.be.revertedWith("Username length invalid");
    });
  });

  describe("Account Limits", function () {
    it("should allow maximum number of accounts", async function () {
      for (let i = 0; i < 10; i++) {
        await torqueAccount.connect(user).createAccount(
          2000,
          false,
          `testuser${i}`,
          ethers.ZeroAddress
        );
      }
      const count = await torqueAccount.accountCount(user.address);
      expect(count).to.equal(10);
    });

    it("should not allow more than maximum accounts", async function () {
      for (let i = 0; i < 10; i++) {
        await torqueAccount.connect(user).createAccount(
          2000,
          false,
          `testuser${i}`,
          ethers.ZeroAddress
        );
      }
      await expect(
        torqueAccount.connect(user).createAccount(2000, false, "testuser11", ethers.ZeroAddress)
      ).to.be.revertedWith("Max accounts reached");
    });
  });
}); 