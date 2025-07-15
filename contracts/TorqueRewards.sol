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

    // Vesting schedule for rewards
    struct VestingSchedule {
        uint256 totalAmount;
        uint256 claimedAmount;
        uint256 startTime;
        uint256 duration;
        bool isActive;
    }

    // Referral system
    struct ReferralInfo {
        address referrer;
        uint256 totalEarnings;
        uint256 totalReferredUsers;
        uint256 lastActivityTime;
        bool isActive;
    }

    // Emission control parameters
    struct EmissionControl {
        uint256 dailyEmissionCap;
        uint256 currentDayEmitted;
        uint256 lastEmissionReset;
        uint256 totalEmitted;
        uint256 maxTotalEmission;
        bool emissionPaused;
    }

    // Reward configurations
    mapping(RewardType => RewardConfig) public rewardConfigs;
    mapping(address => UserRewards) public userRewards;
    mapping(address => uint256) public userVolume;
    mapping(address => uint256) public userActivityScore;
    
    // Vesting schedules
    mapping(address => VestingSchedule) public userVesting;
    
    // Referral system
    mapping(address => ReferralInfo) public referralInfo;
    mapping(address => address) public referrers;
    mapping(address => address[]) public referredUsers;
    
    // Emission control
    EmissionControl public emissionControl;
    
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
    
    // Emission control constants
    uint256 public constant MAX_DAILY_EMISSIONS = 5000 * 10**18; // 5k TORQ/day (reduced from 10k)
    uint256 public constant MAX_TOTAL_EMISSIONS = 1000000 * 10**18; // 1M TORQ total
    uint256 public constant EMISSION_RESET_PERIOD = 1 days;
    
    // Vesting constants
    uint256 public constant VESTING_DURATION = 365 days; // 1 year vesting
    uint256 public constant VESTING_CLIFF = 30 days; // 30 day cliff
    
    // Referral constants
    uint256 public constant REFERRAL_REWARD_RATE = 150; // 1.5% (reduced from 2%)
    uint256 public constant REFERRAL_ACTIVITY_THRESHOLD = 100 * 10**6; // 100 USDC minimum activity
    uint256 public constant REFERRAL_BONUS_DURATION = 90 days; // 90 days of bonus rewards

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
    
    // Vesting events
    event VestingScheduleCreated(
        address indexed user,
        uint256 totalAmount,
        uint256 startTime,
        uint256 duration
    );
    event VestingClaimed(
        address indexed user,
        uint256 amount,
        uint256 remainingAmount
    );
    
    // Referral events
    event ReferralRegistered(
        address indexed referrer,
        address indexed referee,
        uint256 timestamp
    );
    event ReferralRewardEarned(
        address indexed referrer,
        address indexed referee,
        uint256 amount,
        uint256 activityValue,
        uint256 timestamp
    );
    
    // Emission control events
    event EmissionCapUpdated(
        uint256 newDailyCap,
        uint256 newTotalCap,
        uint256 timestamp
    );
    event EmissionPaused(
        bool paused,
        uint256 timestamp
    );

    constructor(
        address _rewardToken,
        address _torqueFX
    ) Ownable(msg.sender) {
        rewardToken = IERC20(_rewardToken);
        torqueFX = ITorqueFX(_torqueFX);
        
        // Initialize emission control
        emissionControl = EmissionControl({
            dailyEmissionCap: MAX_DAILY_EMISSIONS,
            currentDayEmitted: 0,
            lastEmissionReset: block.timestamp,
            totalEmitted: 0,
            maxTotalEmission: MAX_TOTAL_EMISSIONS,
            emissionPaused: false
        });
        
        _initializeRewardConfigs();
        _initializeVolumeTiers();
    }

    /**
     * @dev Initialize reward configurations for different activities
     * UPDATED: More conservative reward rates to combat hyperinflation
     */
    function _initializeRewardConfigs() internal {
        // FX Trading rewards - earn TORQ by trading
        rewardConfigs[RewardType.FX_TRADING] = RewardConfig({
            baseRate: 15,      // 0.15% of trade volume (reduced from 0.25%)
            multiplier: 100,   // 1x multiplier
            cap: 100 * 10**18, // 100 TORQ max per trade (reduced from 1000)
            active: true
        });

        // Liquidity Provision rewards - earn TORQ by providing liquidity
        rewardConfigs[RewardType.LIQUIDITY_PROVISION] = RewardConfig({
            baseRate: 30,      // 0.3% of liquidity provided (reduced from 0.5%)
            multiplier: 100,   // 1x multiplier
            cap: 200 * 10**18, // 200 TORQ max per liquidity action (reduced from 2000)
            active: true
        });

        // Staking rewards - earn TORQ by staking for governance
        rewardConfigs[RewardType.STAKING] = RewardConfig({
            baseRate: 50,      // 0.5% of staked amount (reduced from 1%)
            multiplier: 100,   // 1x multiplier
            cap: 500 * 10**18, // 500 TORQ max per staking action (reduced from 5000)
            active: true
        });

        // Referral rewards - earn TORQ by bringing new users
        rewardConfigs[RewardType.REFERRAL] = RewardConfig({
            baseRate: REFERRAL_REWARD_RATE, // 1.5% of referred user's activity (reduced from 2%)
            multiplier: 100,   // 1x multiplier
            cap: 500 * 10**18, // 500 TORQ max per referral (reduced from 1000)
            active: true
        });

        // Volume bonus rewards - earn TORQ for high volume
        rewardConfigs[RewardType.VOLUME_BONUS] = RewardConfig({
            baseRate: 3,       // 0.03% bonus on total volume (reduced from 0.05%)
            multiplier: 100,   // 1x multiplier
            cap: 1000 * 10**18, // 1000 TORQ max per volume period (reduced from 10000)
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
     * UPDATED: Added emission control check
     */
    function awardFXTradingReward(
        address trader,
        uint256 tradeVolume,
        bytes32 pair
    ) external {
        require(msg.sender == address(torqueFX), "Only TorqueFX");
        require(rewardConfigs[RewardType.FX_TRADING].active, "FX trading rewards disabled");
        require(!emissionControl.emissionPaused, "Emission paused");
        
        uint256 reward = _calculateReward(
            RewardType.FX_TRADING,
            tradeVolume,
            trader
        );
        
        // NEW: Check emission cap before distributing
        _checkEmissionCap(reward);
        
        _distributeReward(trader, RewardType.FX_TRADING, reward, tradeVolume);
        _updateActivityScore(trader, 10); // Trading gives high activity score
        
        // NEW: Award referral rewards if applicable
        _awardReferralReward(trader, tradeVolume);
    }

    /**
     * @dev Award rewards for liquidity provision
     * UPDATED: Added emission control check
     */
    function awardLiquidityReward(
        address provider,
        uint256 liquidityAmount,
        address token
    ) external {
        require(msg.sender == address(torqueFX), "Only TorqueFX");
        require(rewardConfigs[RewardType.LIQUIDITY_PROVISION].active, "Liquidity rewards disabled");
        require(!emissionControl.emissionPaused, "Emission paused");
        
        uint256 reward = _calculateReward(
            RewardType.LIQUIDITY_PROVISION,
            liquidityAmount,
            provider
        );
        
        // Check emission cap before distributing
        _checkEmissionCap(reward);
        
        _distributeReward(provider, RewardType.LIQUIDITY_PROVISION, reward, liquidityAmount);
        _updateActivityScore(provider, 15); // Liquidity provision gives highest activity score
    }

    /**
     * @dev Award rewards for staking activity
     * UPDATED: Added emission control check
     */
    function awardStakingReward(
        address staker,
        uint256 stakedAmount,
        uint256 lockDuration
    ) external {
        require(msg.sender == address(torqueFX), "Only TorqueFX");
        require(rewardConfigs[RewardType.STAKING].active, "Staking rewards disabled");
        require(!emissionControl.emissionPaused, "Emission paused");
        
        // Higher rewards for longer lock periods
        uint256 durationMultiplier = (lockDuration / 30 days) + 1; // 1x for 30 days, 2x for 60 days, etc.
        
        uint256 reward = _calculateReward(
            RewardType.STAKING,
            stakedAmount * durationMultiplier,
            staker
        );
        
        // Check emission cap before distributing
        _checkEmissionCap(reward);
        
        _distributeReward(staker, RewardType.STAKING, reward, stakedAmount);
        _updateActivityScore(staker, 8); // Staking gives good activity score
    }

    /**
     * @dev Complete referral reward system
     */
    function awardReferralReward(
        address referrer,
        address referee,
        uint256 activityValue
    ) external {
        require(msg.sender == address(torqueFX), "Only TorqueFX");
        require(rewardConfigs[RewardType.REFERRAL].active, "Referral rewards disabled");
        require(!emissionControl.emissionPaused, "Emission paused");
        require(referrers[referee] == referrer, "Invalid referral");
        require(activityValue >= REFERRAL_ACTIVITY_THRESHOLD, "Activity below threshold");
        
        // Check if referral is still within bonus period
        ReferralInfo storage refInfo = referralInfo[referee];
        if (block.timestamp - refInfo.lastActivityTime > REFERRAL_BONUS_DURATION) {
            return; // Referral bonus period expired
        }
        
        uint256 reward = _calculateReward(
            RewardType.REFERRAL,
            activityValue,
            referrer
        );
        
        // Check emission cap before distributing
        _checkEmissionCap(reward);
        
        _distributeReward(referrer, RewardType.REFERRAL, reward, activityValue);
        _updateActivityScore(referrer, 5); // Referral gives moderate activity score
        
        // Update referral statistics
        refInfo.totalEarnings += reward;
        refInfo.lastActivityTime = block.timestamp;
        
        emit ReferralRewardEarned(referrer, referee, reward, activityValue, block.timestamp);
    }

    /**
     * @dev Register a referral relationship
     */
    function registerReferral(address referrer, address referee) external {
        require(msg.sender == address(torqueFX), "Only TorqueFX");
        require(referrer != referee, "Cannot refer self");
        require(referrer != address(0) && referee != address(0), "Invalid addresses");
        require(referrers[referee] == address(0), "Already referred");
        
        referrers[referee] = referrer;
        referredUsers[referrer].push(referee);
        
        // Initialize referral info
        referralInfo[referee] = ReferralInfo({
            referrer: referrer,
            totalEarnings: 0,
            totalReferredUsers: 0,
            lastActivityTime: block.timestamp,
            isActive: true
        });
        
        // Update referrer's stats
        ReferralInfo storage refInfo = referralInfo[referrer];
        if (refInfo.referrer == address(0)) {
            // First time referrer
            refInfo.referrer = address(0); // Self-referral
            refInfo.totalEarnings = 0;
            refInfo.totalReferredUsers = 1;
            refInfo.lastActivityTime = block.timestamp;
            refInfo.isActive = true;
        } else {
            refInfo.totalReferredUsers++;
        }
        
        emit ReferralRegistered(referrer, referee, block.timestamp);
    }

    /**
     * @dev Internal function to award referral rewards
     */
    function _awardReferralReward(address user, uint256 activityValue) internal {
        address referrer = referrers[user];
        if (referrer != address(0)) {
            this.awardReferralReward(referrer, user, activityValue);
        }
    }

    /**
     * @dev Check emission cap before distributing rewards
     */
    function _checkEmissionCap(uint256 amount) internal {
        // Reset daily cap if needed
        if (block.timestamp - emissionControl.lastEmissionReset >= EMISSION_RESET_PERIOD) {
            emissionControl.currentDayEmitted = 0;
            emissionControl.lastEmissionReset = block.timestamp;
        }
        
        // Check daily cap
        require(
            emissionControl.currentDayEmitted + amount <= emissionControl.dailyEmissionCap,
            "Daily emission cap exceeded"
        );
        
        // Check total cap
        require(
            emissionControl.totalEmitted + amount <= emissionControl.maxTotalEmission,
            "Total emission cap exceeded"
        );
        
        // Update emission tracking
        emissionControl.currentDayEmitted += amount;
        emissionControl.totalEmitted += amount;
    }

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
     * @dev Distribute reward to user with vesting
     * UPDATED: Now creates vesting schedule instead of immediate distribution
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
        
        // Create or update vesting schedule
        _createOrUpdateVesting(user, amount);
        
        // Update global stats
        totalRewardsDistributed += amount;
        totalVolumeProcessed += activityValue;
        
        emit RewardEarned(user, rewardType, amount, activityValue, block.timestamp);
    }

    /**
     * @dev Create or update vesting schedule for user
     */
    function _createOrUpdateVesting(address user, uint256 amount) internal {
        VestingSchedule storage vesting = userVesting[user];
        
        if (!vesting.isActive) {
            // Create new vesting schedule
            vesting.totalAmount = amount;
            vesting.claimedAmount = 0;
            vesting.startTime = block.timestamp;
            vesting.duration = VESTING_DURATION;
            vesting.isActive = true;
            
            emit VestingScheduleCreated(user, amount, block.timestamp, VESTING_DURATION);
        } else {
            // Add to existing vesting schedule
            vesting.totalAmount += amount;
        }
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
     * @dev Calculate claimable rewards from vesting schedule
     */
    function _calculateClaimableRewards(address user) internal view returns (uint256) {
        VestingSchedule storage vesting = userVesting[user];
        
        if (!vesting.isActive) return 0;
        
        uint256 timeElapsed = block.timestamp - vesting.startTime;
        
        // Check cliff period
        if (timeElapsed < VESTING_CLIFF) {
            return 0;
        }
        
        // Calculate vested amount
        uint256 vestedAmount;
        if (timeElapsed >= vesting.duration) {
            vestedAmount = vesting.totalAmount;
        } else {
            vestedAmount = (vesting.totalAmount * timeElapsed) / vesting.duration;
        }
        
        return vestedAmount - vesting.claimedAmount;
    }

    /**
     * @dev Claim all accumulated rewards with vesting
     * UPDATED: Now uses vesting schedule
     */
    function claimRewards() external nonReentrant whenNotPaused {
        uint256 claimableAmount = _calculateClaimableRewards(msg.sender);
        require(claimableAmount > 0, "No rewards to claim");
        
        VestingSchedule storage vesting = userVesting[msg.sender];
        vesting.claimedAmount += claimableAmount;
        
        // Reset vesting if fully claimed
        if (vesting.claimedAmount >= vesting.totalAmount) {
            vesting.isActive = false;
        }
        
        // Reset user rewards tracking
        UserRewards storage userReward = userRewards[msg.sender];
        userReward.lastClaimTime = block.timestamp;
        
        // Transfer rewards
        rewardToken.transfer(msg.sender, claimableAmount);
        
        emit RewardsClaimed(msg.sender, claimableAmount, block.timestamp);
        emit VestingClaimed(msg.sender, claimableAmount, vesting.totalAmount - vesting.claimedAmount);
    }

    /**
     * @dev Get user's reward summary
     * UPDATED: Added vesting information
     */
    function getUserRewards(address user) external view returns (
        uint256 totalEarned,
        uint256 activityScore,
        uint256 volumeTier,
        uint256[] memory rewardsByType,
        uint256[] memory activityCount,
        uint256 claimableAmount,
        uint256 totalVested,
        uint256 claimedAmount
    ) {
        UserRewards storage userReward = userRewards[user];
        VestingSchedule storage vesting = userVesting[user];
        
        rewardsByType = new uint256[](7);
        activityCount = new uint256[](7);
        
        for (uint256 i = 0; i < 7; i++) {
            rewardsByType[i] = userReward.rewardsByType[RewardType(i)];
            activityCount[i] = userReward.activityCount[RewardType(i)];
        }
        
        claimableAmount = _calculateClaimableRewards(user);
        totalVested = vesting.totalAmount;
        claimedAmount = vesting.claimedAmount;
        
        return (
            userReward.totalEarned,
            userReward.activityScore,
            _getUserTierMultiplier(user),
            rewardsByType,
            activityCount,
            claimableAmount,
            totalVested,
            claimedAmount
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
     * @dev Get referral information
     */
    function getReferralInfo(address user) external view returns (
        address referrer,
        uint256 totalEarnings,
        uint256 totalReferredUsers,
        uint256 lastActivityTime,
        bool isActive,
        address[] memory referred
    ) {
        ReferralInfo storage refInfo = referralInfo[user];
        referrer = refInfo.referrer;
        totalEarnings = refInfo.totalEarnings;
        totalReferredUsers = refInfo.totalReferredUsers;
        lastActivityTime = refInfo.lastActivityTime;
        isActive = refInfo.isActive;
        referred = referredUsers[user];
    }

    /**
     * @dev Get emission control information
     */
    function getEmissionInfo() external view returns (
        uint256 dailyEmissionCap,
        uint256 currentDayEmitted,
        uint256 lastEmissionReset,
        uint256 totalEmitted,
        uint256 maxTotalEmission,
        bool emissionPaused,
        uint256 nextResetTime
    ) {
        dailyEmissionCap = emissionControl.dailyEmissionCap;
        currentDayEmitted = emissionControl.currentDayEmitted;
        lastEmissionReset = emissionControl.lastEmissionReset;
        totalEmitted = emissionControl.totalEmitted;
        maxTotalEmission = emissionControl.maxTotalEmission;
        emissionPaused = emissionControl.emissionPaused;
        nextResetTime = lastEmissionReset + EMISSION_RESET_PERIOD;
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
     * @dev Update emission control parameters
     */
    function updateEmissionControl(
        uint256 newDailyCap,
        uint256 newTotalCap,
        bool pauseEmission
    ) external onlyOwner {
        emissionControl.dailyEmissionCap = newDailyCap;
        emissionControl.maxTotalEmission = newTotalCap;
        emissionControl.emissionPaused = pauseEmission;
        
        emit EmissionCapUpdated(newDailyCap, newTotalCap, block.timestamp);
        emit EmissionPaused(pauseEmission, block.timestamp);
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
