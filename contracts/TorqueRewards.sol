// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "./4337/TorqueAccount.sol";

interface ITorqueAccount {
    function userAccounts(address user, uint256 accountId) external view returns (
        uint256 leverage,
        bool exists,
        bool active,
        string memory username,
        address referrer
    );
    function isValidAccount(address user, uint256 accountId) external view returns (bool);
}

contract TorqueRewards is Ownable, ReentrancyGuard {
    IERC20 public rewardToken;
    ITorqueAccount public torqueAccount;

    // Reward rates (in basis points)
    uint256 public referralRewardBps = 100; // 1% referral reward
    uint256 public cashbackRewardBps = 50;  // 0.5% trading cashback

    // Reward tracking
    mapping(address => uint256) public referralRewards;
    mapping(address => uint256) public cashbackRewards;
    mapping(address => uint256) public totalEarned;

    event ReferralRewardPaid(address indexed referrer, address indexed trader, uint256 amount);
    event CashbackRewardPaid(address indexed trader, uint256 amount);
    event RewardRatesUpdated(uint256 referralBps, uint256 cashbackBps);

    constructor(address _rewardToken, address _torqueAccount) Ownable(msg.sender) {
        rewardToken = IERC20(_rewardToken);
        torqueAccount = ITorqueAccount(_torqueAccount);
    }

    function distributeReferralReward(
        address trader,
        uint256 accountId,
        uint256 tradeAmount
    ) external {
        // CHECKS
        require(msg.sender == address(torqueAccount), "Only TorqueAccount");
        
        // EFFECTS
        (, , , , address referrer) = torqueAccount.userAccounts(trader, accountId);
        if (referrer != address(0)) {
            uint256 reward = (tradeAmount * referralRewardBps) / 10000;
            referralRewards[referrer] += reward;
            totalEarned[referrer] += reward;
            emit ReferralRewardPaid(referrer, trader, reward);
        }
    }

    function distributeCashbackReward(
        address trader,
        uint256 tradeAmount
    ) external {
        // CHECKS
        require(msg.sender == address(torqueAccount), "Only TorqueAccount");
        
        // EFFECTS
        uint256 reward = (tradeAmount * cashbackRewardBps) / 10000;
        cashbackRewards[trader] += reward;
        totalEarned[trader] += reward;
        emit CashbackRewardPaid(trader, reward);
    }

    function claimReferralRewards() external nonReentrant {
        // CHECKS
        uint256 reward = referralRewards[msg.sender];
        require(reward > 0, "No rewards to claim");
        
        // EFFECTS
        referralRewards[msg.sender] = 0;
        
        // INTERACTIONS
        rewardToken.transfer(msg.sender, reward);
    }

    function claimCashbackRewards() external nonReentrant {
        // CHECKS
        uint256 reward = cashbackRewards[msg.sender];
        require(reward > 0, "No rewards to claim");
        
        // EFFECTS
        cashbackRewards[msg.sender] = 0;
        
        // INTERACTIONS
        rewardToken.transfer(msg.sender, reward);
    }

    function setRewardRates(uint256 _referralBps, uint256 _cashbackBps) external onlyOwner {
        // CHECKS
        require(_referralBps <= 1000, "Referral rate too high"); // Max 10%
        require(_cashbackBps <= 500, "Cashback rate too high");  // Max 5%
        
        // EFFECTS
        referralRewardBps = _referralBps;
        cashbackRewardBps = _cashbackBps;
        
        emit RewardRatesUpdated(_referralBps, _cashbackBps);
    }

    function getTotalRewards(address user) external view returns (
        uint256 referral,
        uint256 cashback,
        uint256 total
    ) {
        referral = referralRewards[user];
        cashback = cashbackRewards[user];
        total = totalEarned[user];
    }
}
