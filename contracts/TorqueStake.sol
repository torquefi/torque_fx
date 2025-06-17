// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/math/Math.sol";

contract TorqueStake is Ownable, ReentrancyGuard {
    using Math for uint256;

    IERC20 public lpToken;
    IERC20 public torqToken;
    IERC20 public rewardToken;
    address public treasuryFeeRecipient;

    // Staking parameters
    uint256 public constant MIN_LOCK_DURATION = 7 days;
    uint256 public constant MAX_LOCK_DURATION = 7 * 365 days; // 7 years
    uint256 public constant EARLY_EXIT_PENALTY = 5000; // 50% in basis points
    uint256 public constant VOTE_POWER_MULTIPLIER = 2; // 2x vote power for max lock

    // APR parameters (in basis points)
    uint256 public constant MIN_APR = 2000; // 20%
    uint256 public constant MAX_APR = 40000; // 400%
    uint256 public constant APR_PRECISION = 10000; // For basis points

    // Staking state
    struct Stake {
        uint256 amount;
        uint256 lockEnd;
        uint256 lastRewardTime;
        uint256 accumulatedRewards;
        uint256 lockDuration; // Store original lock duration for APR calculation
    }

    mapping(address => Stake) public lpStakes;
    mapping(address => Stake) public torqStakes;
    mapping(address => uint256) public votePower;

    // Reward parameters
    uint256 public lastUpdateTime;

    event Staked(address indexed user, uint256 amount, uint256 lockDuration, bool isLp);
    event Unstaked(address indexed user, uint256 amount, bool isLp, bool isEarly);
    event RewardPaid(address indexed user, uint256 reward, bool isLp);
    event VotePowerUpdated(address indexed user, uint256 newPower);
    event TreasuryFeeRecipientUpdated(address indexed newRecipient);
    event EarlyExitPenaltyPaid(address indexed user, uint256 amount, bool isLp);

    constructor(
        address _lpToken,
        address _torqToken,
        address _rewardToken,
        address _treasuryFeeRecipient
    ) {
        lpToken = IERC20(_lpToken);
        torqToken = IERC20(_torqToken);
        rewardToken = IERC20(_rewardToken);
        treasuryFeeRecipient = _treasuryFeeRecipient;
        lastUpdateTime = block.timestamp;
    }

    function setTreasuryFeeRecipient(address _treasuryFeeRecipient) external onlyOwner {
        require(_treasuryFeeRecipient != address(0), "Invalid treasury address");
        treasuryFeeRecipient = _treasuryFeeRecipient;
        emit TreasuryFeeRecipientUpdated(_treasuryFeeRecipient);
    }

    function stakeLp(uint256 amount, uint256 lockDuration) external nonReentrant {
        // CHECKS
        require(amount > 0, "Cannot stake 0");
        require(lockDuration >= MIN_LOCK_DURATION, "Lock too short");
        require(lockDuration <= MAX_LOCK_DURATION, "Lock too long");

        // EFFECTS
        Stake storage stake = lpStakes[msg.sender];
        if (stake.amount > 0) {
            _updateRewards(msg.sender, true);
        }

        stake.amount += amount;
        stake.lockEnd = block.timestamp + lockDuration;
        stake.lastRewardTime = block.timestamp;
        stake.lockDuration = lockDuration;

        // Update vote power
        _updateVotePower(msg.sender);

        // INTERACTIONS
        lpToken.transferFrom(msg.sender, address(this), amount);

        emit Staked(msg.sender, amount, lockDuration, true);
    }

    function stakeTorq(uint256 amount, uint256 lockDuration) external nonReentrant {
        // CHECKS
        require(amount > 0, "Cannot stake 0");
        require(lockDuration >= MIN_LOCK_DURATION, "Lock too short");
        require(lockDuration <= MAX_LOCK_DURATION, "Lock too long");

        // EFFECTS
        Stake storage stake = torqStakes[msg.sender];
        if (stake.amount > 0) {
            _updateRewards(msg.sender, false);
        }

        stake.amount += amount;
        stake.lockEnd = block.timestamp + lockDuration;
        stake.lastRewardTime = block.timestamp;
        stake.lockDuration = lockDuration;

        // Update vote power
        _updateVotePower(msg.sender);

        // INTERACTIONS
        torqToken.transferFrom(msg.sender, address(this), amount);

        emit Staked(msg.sender, amount, lockDuration, false);
    }

    function unstakeLp() external nonReentrant {
        // CHECKS
        Stake storage stake = lpStakes[msg.sender];
        require(stake.amount > 0, "No stake");

        // EFFECTS
        _updateRewards(msg.sender, true);
        uint256 amount = stake.amount;
        bool isEarly = block.timestamp < stake.lockEnd;
        uint256 penalty = 0;

        if (isEarly) {
            penalty = (amount * EARLY_EXIT_PENALTY) / 10000;
            amount -= penalty;
        }

        stake.amount = 0;
        stake.lockEnd = 0;
        stake.lastRewardTime = 0;
        stake.lockDuration = 0;

        // Update vote power
        _updateVotePower(msg.sender);

        // INTERACTIONS
        if (penalty > 0) {
            lpToken.transfer(treasuryFeeRecipient, penalty);
            emit EarlyExitPenaltyPaid(msg.sender, penalty, true);
        }
        lpToken.transfer(msg.sender, amount);

        emit Unstaked(msg.sender, amount, true, isEarly);
    }

    function unstakeTorq() external nonReentrant {
        // CHECKS
        Stake storage stake = torqStakes[msg.sender];
        require(stake.amount > 0, "No stake");

        // EFFECTS
        _updateRewards(msg.sender, false);
        uint256 amount = stake.amount;
        bool isEarly = block.timestamp < stake.lockEnd;
        uint256 penalty = 0;

        if (isEarly) {
            penalty = (amount * EARLY_EXIT_PENALTY) / 10000;
            amount -= penalty;
        }

        stake.amount = 0;
        stake.lockEnd = 0;
        stake.lastRewardTime = 0;
        stake.lockDuration = 0;

        // Update vote power
        _updateVotePower(msg.sender);

        // INTERACTIONS
        if (penalty > 0) {
            torqToken.transfer(treasuryFeeRecipient, penalty);
            emit EarlyExitPenaltyPaid(msg.sender, penalty, false);
        }
        torqToken.transfer(msg.sender, amount);

        emit Unstaked(msg.sender, amount, false, isEarly);
    }

    function claimRewards(bool isLp) external nonReentrant {
        // CHECKS
        Stake storage stake = isLp ? lpStakes[msg.sender] : torqStakes[msg.sender];
        require(stake.amount > 0, "No stake");

        // EFFECTS
        _updateRewards(msg.sender, isLp);
        uint256 reward = stake.accumulatedRewards;
        require(reward > 0, "No rewards to claim");
        stake.accumulatedRewards = 0;

        // INTERACTIONS
        rewardToken.transfer(msg.sender, reward);
        emit RewardPaid(msg.sender, reward, isLp);
    }

    function _updateRewards(address user, bool isLp) internal {
        Stake storage stake = isLp ? lpStakes[user] : torqStakes[user];
        if (stake.amount == 0) return;

        uint256 timeElapsed = block.timestamp - stake.lastRewardTime;
        if (timeElapsed == 0) return;

        // Calculate APR based on lock duration
        uint256 apr = _calculateAPR(stake.lockDuration);
        
        // Calculate daily reward rate from APR
        uint256 dailyRate = (apr * APR_PRECISION) / (365 * APR_PRECISION);
        
        // Calculate reward
        uint256 reward = (stake.amount * dailyRate * timeElapsed) / (1 days * APR_PRECISION);
        
        stake.accumulatedRewards += reward;
        stake.lastRewardTime = block.timestamp;
    }

    function _calculateAPR(uint256 lockDuration) internal pure returns (uint256) {
        if (lockDuration <= MIN_LOCK_DURATION) {
            return MIN_APR;
        }
        if (lockDuration >= MAX_LOCK_DURATION) {
            return MAX_APR;
        }

        // Linear interpolation between MIN_APR and MAX_APR based on lock duration
        uint256 durationRange = MAX_LOCK_DURATION - MIN_LOCK_DURATION;
        uint256 aprRange = MAX_APR - MIN_APR;
        
        return MIN_APR + ((lockDuration - MIN_LOCK_DURATION) * aprRange) / durationRange;
    }

    function _updateVotePower(address user) internal {
        Stake storage lpStake = lpStakes[user];
        Stake storage torqStake = torqStakes[user];

        uint256 totalPower = 0;

        // Calculate LP vote power
        if (lpStake.amount > 0) {
            uint256 lockDuration = lpStake.lockEnd - block.timestamp;
            uint256 multiplier = 1e18 + ((lockDuration * (VOTE_POWER_MULTIPLIER - 1e18)) / MAX_LOCK_DURATION);
            totalPower += (lpStake.amount * multiplier) / 1e18;
        }

        // Calculate TORQ vote power
        if (torqStake.amount > 0) {
            uint256 lockDuration = torqStake.lockEnd - block.timestamp;
            uint256 multiplier = 1e18 + ((lockDuration * (VOTE_POWER_MULTIPLIER - 1e18)) / MAX_LOCK_DURATION);
            totalPower += (torqStake.amount * multiplier) / 1e18;
        }

        votePower[user] = totalPower;
        emit VotePowerUpdated(user, totalPower);
    }

    function getStakeInfo(address user) external view returns (
        uint256 lpAmount,
        uint256 lpLockEnd,
        uint256 lpRewards,
        uint256 lpApr,
        uint256 torqAmount,
        uint256 torqLockEnd,
        uint256 torqRewards,
        uint256 torqApr,
        uint256 userVotePower
    ) {
        Stake storage lpStake = lpStakes[user];
        Stake storage torqStake = torqStakes[user];

        lpAmount = lpStake.amount;
        lpLockEnd = lpStake.lockEnd;
        lpRewards = lpStake.accumulatedRewards;
        lpApr = _calculateAPR(lpStake.lockDuration);

        torqAmount = torqStake.amount;
        torqLockEnd = torqStake.lockEnd;
        torqRewards = torqStake.accumulatedRewards;
        torqApr = _calculateAPR(torqStake.lockDuration);

        userVotePower = votePower[user];
    }
} 