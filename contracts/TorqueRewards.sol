// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
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

    uint256 public constant REWARD_DURATION = 7 days;
    uint256 public constant MIN_STAKE_AMOUNT = 100e18;
    uint256 public constant MAX_STAKE_AMOUNT = 1000000e18;

    uint256 public rewardRate;
    uint256 public periodFinish;
    uint256 public lastUpdateTime;
    uint256 public rewardPerTokenStored;

    mapping(address => uint256) public userRewardPerTokenPaid;
    mapping(address => uint256) public rewards;
    mapping(address => uint256) public stakedBalance;
    mapping(address => uint256) public lastStakeTime;
    mapping(address => uint256) public totalEarned;

    event RewardAdded(uint256 reward);
    event Staked(address indexed user, uint256 amount);
    event Withdrawn(address indexed user, uint256 amount);
    event RewardPaid(address indexed user, uint256 reward);
    event RewardRateUpdated(uint256 newRate);

    constructor(address _rewardToken, address _torqueAccount) {
        rewardToken = IERC20(_rewardToken);
        torqueAccount = ITorqueAccount(_torqueAccount);
    }

    function stake(uint256 amount, uint256 accountId) external nonReentrant {
        require(isValidAccount(msg.sender, accountId), "Invalid account");
        require(amount >= MIN_STAKE_AMOUNT, "Below minimum stake");
        require(amount <= MAX_STAKE_AMOUNT, "Above maximum stake");
        require(stakedBalance[msg.sender] + amount <= MAX_STAKE_AMOUNT, "Total stake too high");

        updateReward(msg.sender);

        rewardToken.transferFrom(msg.sender, address(this), amount);
        stakedBalance[msg.sender] += amount;
        lastStakeTime[msg.sender] = block.timestamp;

        emit Staked(msg.sender, amount);
    }

    function withdraw(uint256 amount) external nonReentrant {
        require(amount > 0, "Cannot withdraw 0");
        require(stakedBalance[msg.sender] >= amount, "Insufficient stake");

        updateReward(msg.sender);

        stakedBalance[msg.sender] -= amount;
        rewardToken.transfer(msg.sender, amount);

        emit Withdrawn(msg.sender, amount);
    }

    function getReward() external nonReentrant {
        updateReward(msg.sender);

        uint256 reward = rewards[msg.sender];
        if (reward > 0) {
            rewards[msg.sender] = 0;
            totalEarned[msg.sender] += reward;
            rewardToken.transfer(msg.sender, reward);
            emit RewardPaid(msg.sender, reward);
        }
    }

    function exit() external {
        withdraw(stakedBalance[msg.sender]);
        getReward();
    }

    function updateReward(address account) public {
        rewardPerTokenStored = rewardPerToken();
        lastUpdateTime = lastTimeRewardApplicable();

        if (account != address(0)) {
            rewards[account] = earned(account);
            userRewardPerTokenPaid[account] = rewardPerTokenStored;
        }
    }

    function lastTimeRewardApplicable() public view returns (uint256) {
        return block.timestamp < periodFinish ? block.timestamp : periodFinish;
    }

    function rewardPerToken() public view returns (uint256) {
        if (stakedBalance[address(0)] == 0) {
            return rewardPerTokenStored;
        }

        return rewardPerTokenStored + (
            (lastTimeRewardApplicable() - lastUpdateTime) * rewardRate * 1e18
        ) / stakedBalance[address(0)];
    }

    function earned(address account) public view returns (uint256) {
        return (
            stakedBalance[account] * (rewardPerToken() - userRewardPerTokenPaid[account])
        ) / 1e18 + rewards[account];
    }

    function setRewardRate(uint256 _rewardRate) external onlyOwner {
        require(_rewardRate > 0, "Invalid rate");
        updateReward(address(0));

        rewardRate = _rewardRate;
        periodFinish = block.timestamp + REWARD_DURATION;
        lastUpdateTime = block.timestamp;

        emit RewardRateUpdated(_rewardRate);
    }

    function isValidAccount(address user, uint256 accountId) public view returns (bool) {
        (, bool exists, bool active, , ) = torqueAccount.userAccounts(user, accountId);
        return exists && active;
    }
}
