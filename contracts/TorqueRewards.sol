// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.30;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/Pausable.sol";
import "./TorqueFX.sol";

interface ITorqueFX {
    function getPosition(address user, bytes32 pair) external view returns (
        uint256 collateral,
        int256 entryPrice,
        bool isLong,
        uint256 lastLiquidationAmount,
        uint256 stopLossPrice,
        uint256 takeProfitPrice,
        uint256 positionSize,
        uint256 positionId,
        uint256 closePrice,
        int256 pnl,
        bool isOpen,
        address baseToken,
        address quoteToken
    );
}

contract TorqueRewards is Ownable, ReentrancyGuard, Pausable {
    IERC20 public immutable rewardToken;
    ITorqueFX public immutable torqueFX;

    // Reward categories for different economic activities
    enum RewardType { 
        FX_TRADING,           // Trading FX pairs
        LIQUIDITY_PROVISION,  // Providing liquidity
        STAKING,              // Staking for governance
        REFERRAL,             // Bringing new users
        VOLUME_BONUS          // High volume bonuses
    }

    struct RewardConfig {
        uint256 baseRate;     // Base reward rate (basis points)
        uint256 multiplier;   // Multiplier for activity level
        uint256 cap;          // Maximum reward per activity
        bool active;          // Whether this reward type is active
    }

    struct UserRewards {
        uint256 totalEarned;
        uint256 lastClaimTime;
        uint256 activityScore;
        uint256 volumeTier;
        mapping(RewardType => uint256) rewardsByType;
        mapping(RewardType => uint256) activityCount;
    }

    struct VolumeTier {
        uint256 minVolume;
        uint256 rewardMultiplier;
        string tierName;
    }

    // Reward configurations
    mapping(RewardType => RewardConfig) public rewardConfigs;
    mapping(address => UserRewards) public userRewards;
    mapping(address => uint256) public userVolume;
    mapping(address => uint256) public userActivityScore;
    
    // Volume tiers for bonus rewards
    VolumeTier[] public volumeTiers;
    
    // Global tracking
    uint256 public totalRewardsDistributed;
    uint256 public totalVolumeProcessed;
    uint256 public totalActiveUsers;
    
    // Constants
    uint256 public constant BASIS_POINTS = 10000;
    uint256 public constant ACTIVITY_SCORE_DECAY = 1 days;
    uint256 public constant MAX_ACTIVITY_SCORE = 1000;
    uint256 public constant VOLUME_WINDOW = 30 days;

    // Events
    event RewardEarned(
        address indexed user,
        RewardType indexed rewardType,
        uint256 amount,
        uint256 activityValue,
        uint256 timestamp
    );
    event RewardsClaimed(
        address indexed user,
        uint256 totalAmount,
        uint256 timestamp
    );
    event VolumeTierUpgraded(
        address indexed user,
        string tierName,
        uint256 newMultiplier,
        uint256 timestamp
    );
    event ActivityScoreUpdated(
        address indexed user,
        uint256 newScore,
        uint256 timestamp
    );
    event RewardConfigUpdated(
        RewardType indexed rewardType,
        uint256 baseRate,
        uint256 multiplier,
        uint256 cap
    );

    constructor(
        address _rewardToken,
        address _torqueFX
    ) Ownable(msg.sender) {
        rewardToken = IERC20(_rewardToken);
        torqueFX = ITorqueFX(_torqueFX);
        
        _initializeRewardConfigs();
        _initializeVolumeTiers();
    }

    /**
     * @dev Initialize reward configurations for different activities
     */
    function _initializeRewardConfigs() internal {
        // FX Trading rewards - earn TORQ by trading
        rewardConfigs[RewardType.FX_TRADING] = RewardConfig({
            baseRate: 25,      // 0.25% of trade volume
            multiplier: 100,   // 1x multiplier
            cap: 1000 * 10**18, // 1000 TORQ max per trade
            active: true
        });

        // Liquidity Provision rewards - earn TORQ by providing liquidity
        rewardConfigs[RewardType.LIQUIDITY_PROVISION] = RewardConfig({
            baseRate: 50,      // 0.5% of liquidity provided
            multiplier: 100,   // 1x multiplier
            cap: 2000 * 10**18, // 2000 TORQ max per liquidity action
            active: true
        });

        // Staking rewards - earn TORQ by staking for governance
        rewardConfigs[RewardType.STAKING] = RewardConfig({
            baseRate: 100,     // 1% of staked amount
            multiplier: 100,   // 1x multiplier
            cap: 5000 * 10**18, // 5000 TORQ max per staking action
            active: true
        });

        // Referral rewards - earn TORQ by bringing new users
        rewardConfigs[RewardType.REFERRAL] = RewardConfig({
            baseRate: 200,     // 2% of referred user's activity
            multiplier: 100,   // 1x multiplier
            cap: 1000 * 10**18, // 1000 TORQ max per referral
            active: true
        });

        // Volume bonus rewards - earn TORQ for high volume
        rewardConfigs[RewardType.VOLUME_BONUS] = RewardConfig({
            baseRate: 5,       // 0.05% bonus on total volume
            multiplier: 100,   // 1x multiplier
            cap: 10000 * 10**18, // 10000 TORQ max per volume period
            active: true
        });
    }

    /**
     * @dev Initialize volume tiers for bonus rewards
     */
    function _initializeVolumeTiers() internal {
        volumeTiers.push(VolumeTier({
            minVolume: 0,
            rewardMultiplier: 100, // 1x
            tierName: "Bronze"
        }));
        
        volumeTiers.push(VolumeTier({
            minVolume: 10000 * 10**6, // 10k USDC
            rewardMultiplier: 125, // 1.25x
            tierName: "Silver"
        }));
        
        volumeTiers.push(VolumeTier({
            minVolume: 100000 * 10**6, // 100k USDC
            rewardMultiplier: 150, // 1.5x
            tierName: "Gold"
        }));
        
        volumeTiers.push(VolumeTier({
            minVolume: 1000000 * 10**6, // 1M USDC
            rewardMultiplier: 200, // 2x
            tierName: "Platinum"
        }));
        
        volumeTiers.push(VolumeTier({
            minVolume: 10000000 * 10**6, // 10M USDC
            rewardMultiplier: 300, // 3x
            tierName: "Diamond"
        }));
    }

    /**
     * @dev Award rewards for FX trading activity
     */
    function awardFXTradingReward(
        address trader,
        uint256 tradeVolume,
        bytes32 pair
    ) external {
        require(msg.sender == address(torqueFX), "Only TorqueFX");
        require(rewardConfigs[RewardType.FX_TRADING].active, "FX trading rewards disabled");
        
        uint256 reward = _calculateReward(
            RewardType.FX_TRADING,
            tradeVolume,
            trader
        );
        
        _distributeReward(trader, RewardType.FX_TRADING, reward, tradeVolume);
        _updateActivityScore(trader, 10); // Trading gives high activity score
    }



    /**
     * @dev Award rewards for liquidity provision
     */
    function awardLiquidityReward(
        address provider,
        uint256 liquidityAmount,
        address token
    ) external {
        require(msg.sender == address(torqueFX), "Only TorqueFX");
        require(rewardConfigs[RewardType.LIQUIDITY_PROVISION].active, "Liquidity rewards disabled");
        
        uint256 reward = _calculateReward(
            RewardType.LIQUIDITY_PROVISION,
            liquidityAmount,
            provider
        );
        
        _distributeReward(provider, RewardType.LIQUIDITY_PROVISION, reward, liquidityAmount);
        _updateActivityScore(provider, 15); // Liquidity provision gives highest activity score
    }

    /**
     * @dev Award rewards for staking activity
     */
    function awardStakingReward(
        address staker,
        uint256 stakedAmount,
        uint256 lockDuration
    ) external {
        require(msg.sender == address(torqueFX), "Only TorqueFX");
        require(rewardConfigs[RewardType.STAKING].active, "Staking rewards disabled");
        
        // Higher rewards for longer lock periods
        uint256 durationMultiplier = (lockDuration / 30 days) + 1; // 1x for 30 days, 2x for 60 days, etc.
        
        uint256 reward = _calculateReward(
            RewardType.STAKING,
            stakedAmount * durationMultiplier,
            staker
        );
        
        _distributeReward(staker, RewardType.STAKING, reward, stakedAmount);
        _updateActivityScore(staker, 8); // Staking gives good activity score
    }



    /**
     * @dev Award referral rewards
     */


    /**
     * @dev Calculate reward amount based on activity and user tier
     */
    function _calculateReward(
        RewardType rewardType,
        uint256 activityValue,
        address user
    ) internal view returns (uint256) {
        RewardConfig memory config = rewardConfigs[rewardType];
        require(config.active, "Reward type disabled");
        
        // Base reward calculation
        uint256 baseReward = (activityValue * config.baseRate) / BASIS_POINTS;
        
        // Apply volume tier multiplier
        uint256 tierMultiplier = _getUserTierMultiplier(user);
        uint256 tierReward = (baseReward * tierMultiplier) / 100;
        
        // Apply activity score bonus
        uint256 activityBonus = _getActivityScoreBonus(user);
        uint256 totalReward = tierReward + activityBonus;
        
        // Cap the reward
        if (totalReward > config.cap) {
            totalReward = config.cap;
        }
        
        return totalReward;
    }

    /**
     * @dev Get user's volume tier multiplier
     */
    function _getUserTierMultiplier(address user) internal view returns (uint256) {
        uint256 currentUserVolume = userVolume[user];
        
        for (uint256 i = volumeTiers.length - 1; i >= 0; i--) {
            if (currentUserVolume >= volumeTiers[i].minVolume) {
                return volumeTiers[i].rewardMultiplier;
            }
        }
        
        return 100; // Default 1x multiplier
    }

    /**
     * @dev Get activity score bonus
     */
    function _getActivityScoreBonus(address user) internal view returns (uint256) {
        uint256 activityScore = userActivityScore[user];
        
        // Bonus increases with activity score
        if (activityScore >= 800) {
            return 50; // 0.5% bonus for very active users
        } else if (activityScore >= 600) {
            return 30; // 0.3% bonus for active users
        } else if (activityScore >= 400) {
            return 15; // 0.15% bonus for moderately active users
        } else if (activityScore >= 200) {
            return 5;  // 0.05% bonus for somewhat active users
        }
        
        return 0; // No bonus for inactive users
    }

    /**
     * @dev Distribute reward to user
     */
    function _distributeReward(
        address user,
        RewardType rewardType,
        uint256 amount,
        uint256 activityValue
    ) internal {
        if (amount == 0) return;
        
        UserRewards storage userReward = userRewards[user];
        userReward.rewardsByType[rewardType] += amount;
        userReward.totalEarned += amount;
        userReward.activityCount[rewardType]++;
        
        // Update global stats
        totalRewardsDistributed += amount;
        totalVolumeProcessed += activityValue;
        
        emit RewardEarned(user, rewardType, amount, activityValue, block.timestamp);
    }

    /**
     * @dev Update user's activity score
     */
    function _updateActivityScore(address user, uint256 points) internal {
        UserRewards storage userReward = userRewards[user];
        
        // Decay old activity score
        uint256 timeSinceLastUpdate = block.timestamp - userReward.lastClaimTime;
        if (timeSinceLastUpdate > ACTIVITY_SCORE_DECAY) {
            uint256 decayAmount = (timeSinceLastUpdate / ACTIVITY_SCORE_DECAY) * 10;
            if (userReward.activityScore > decayAmount) {
                userReward.activityScore -= decayAmount;
            } else {
                userReward.activityScore = 0;
            }
        }
        
        // Add new points
        userReward.activityScore += points;
        if (userReward.activityScore > MAX_ACTIVITY_SCORE) {
            userReward.activityScore = MAX_ACTIVITY_SCORE;
        }
        
        userActivityScore[user] = userReward.activityScore;
        emit ActivityScoreUpdated(user, userReward.activityScore, block.timestamp);
    }

    /**
     * @dev Claim all accumulated rewards
     */
    function claimRewards() external nonReentrant whenNotPaused {
        UserRewards storage userReward = userRewards[msg.sender];
        require(userReward.totalEarned > 0, "No rewards to claim");
        
        uint256 totalAmount = userReward.totalEarned;
        
        // Reset all rewards
        for (uint256 i = 0; i < 7; i++) {
            userReward.rewardsByType[RewardType(i)] = 0;
        }
        userReward.totalEarned = 0;
        userReward.lastClaimTime = block.timestamp;
        
        // Transfer rewards
        rewardToken.transfer(msg.sender, totalAmount);
        
        emit RewardsClaimed(msg.sender, totalAmount, block.timestamp);
    }

    /**
     * @dev Get user's reward summary
     */
    function getUserRewards(address user) external view returns (
        uint256 totalEarned,
        uint256 activityScore,
        uint256 volumeTier,
        uint256[] memory rewardsByType,
        uint256[] memory activityCount
    ) {
        UserRewards storage userReward = userRewards[user];
        
        rewardsByType = new uint256[](7);
        activityCount = new uint256[](7);
        
        for (uint256 i = 0; i < 7; i++) {
            rewardsByType[i] = userReward.rewardsByType[RewardType(i)];
            activityCount[i] = userReward.activityCount[RewardType(i)];
        }
        
        return (
            userReward.totalEarned,
            userReward.activityScore,
            _getUserTierMultiplier(user),
            rewardsByType,
            activityCount
        );
    }

    /**
     * @dev Get volume tier information
     */
    function getVolumeTier(address user) external view returns (
        string memory tierName,
        uint256 multiplier,
        uint256 currentVolume,
        uint256 nextTierVolume
    ) {
        currentVolume = userVolume[user];
        multiplier = _getUserTierMultiplier(user);
        
        // Find current tier
        for (uint256 i = 0; i < volumeTiers.length; i++) {
            if (currentVolume >= volumeTiers[i].minVolume) {
                tierName = volumeTiers[i].tierName;
                
                // Find next tier volume requirement
                if (i < volumeTiers.length - 1) {
                    nextTierVolume = volumeTiers[i + 1].minVolume;
                } else {
                    nextTierVolume = 0; // Already at highest tier
                }
                break;
            }
        }
    }

    /**
     * @dev Update reward configuration
     */
    function updateRewardConfig(
        RewardType rewardType,
        uint256 baseRate,
        uint256 multiplier,
        uint256 cap,
        bool active
    ) external onlyOwner {
        rewardConfigs[rewardType] = RewardConfig({
            baseRate: baseRate,
            multiplier: multiplier,
            cap: cap,
            active: active
        });
        
        emit RewardConfigUpdated(rewardType, baseRate, multiplier, cap);
    }

    /**
     * @dev Pause/unpause rewards
     */
    function pause() external onlyOwner {
        _pause();
    }

    function unpause() external onlyOwner {
        _unpause();
    }
}
