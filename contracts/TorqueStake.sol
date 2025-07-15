// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.28;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/math/Math.sol";
import "@layerzerolabs/lz-evm-oapp-v2/contracts/oapp/OApp.sol";

contract TorqueStake is OApp, ReentrancyGuard {
    using Math for uint256;

    IERC20 public lpToken;
    IERC20 public torqToken;
    IERC20 public rewardToken;
    address public treasuryFeeRecipient;

    // Cross-chain staking parameters
    mapping(uint16 => bool) public supportedChainIds;
    mapping(uint16 => address) public stakeAddresses;
    mapping(uint16 => mapping(address => uint256)) public crossChainStakes;
    mapping(address => uint256) public totalCrossChainStakes;
    mapping(bytes32 => bool) public processedMessages;

    // Cross-chain stake request
    struct CrossChainStakeRequest {
        address user;
        uint256 amount;
        uint256 lockDuration;
        bool isLp;
        uint16 sourceChainId;
        bool isStake;
    }

    // Staking parameters
    uint256 public constant MIN_LOCK_DURATION = 30 days;
    uint256 public constant MAX_LOCK_DURATION = 2555 days; // 7 years
    // Early exit penalty parameters
    uint256 public constant MAX_EARLY_EXIT_PENALTY = 5000; // 50% in basis points
    uint256 public constant MIN_EARLY_EXIT_PENALTY = 2500; // 25% in basis points
    uint256 public constant VOTE_POWER_MULTIPLIER = 5e18; // 5x vote power for max lock

    // Dynamic APR parameters (in basis points)
    uint256 public constant BASE_APR_TORQ = 5000; // 50% base APR for TORQ
    uint256 public constant BASE_APR_LP = 3000; // 30% base APR for LP
    uint256 public constant MAX_APR_TORQ = 80000; // 800% max APR for TORQ
    uint256 public constant MAX_APR_LP = 60000; // 600% max APR for LP
    uint256 public constant APR_PRECISION = 10000; // For basis points
    
    // TVL scaling parameters
    uint256 public constant TVL_SCALE_FACTOR = 1e18; // 1 ETH = 1e18 wei
    uint256 public constant TVL_DECAY_RATE = 5000; // 50% decay per TVL doubling (in basis points)
    uint256 public constant MIN_TVL_FOR_DECAY = 1000e18; // 1000 ETH minimum TVL before decay starts
    
    // Lock duration multiplier parameters
    uint256 public constant LOCK_MULTIPLIER_MIN = 1e18; // 1x for minimum lock
    uint256 public constant LOCK_MULTIPLIER_MAX = 55e17; // 5.5x for maximum lock

    // Staking multiplier parameters
    uint256 public constant MIN_STAKE_MULTIPLIER = 1e18; // 1x
    uint256 public constant MAX_STAKE_MULTIPLIER = 55e17; // 5.5x

    // Standard lock period tiers
    uint256 public constant LOCK_30_DAYS = 30 days;
    uint256 public constant LOCK_90_DAYS = 90 days;
    uint256 public constant LOCK_180_DAYS = 180 days;
    uint256 public constant LOCK_365_DAYS = 365 days;
    uint256 public constant LOCK_730_DAYS = 730 days; // 2 years
    uint256 public constant LOCK_1095_DAYS = 1095 days; // 3 years
    uint256 public constant LOCK_1460_DAYS = 1460 days; // 4 years
    uint256 public constant LOCK_1825_DAYS = 1825 days; // 5 years
    uint256 public constant LOCK_2190_DAYS = 2190 days; // 6 years
    uint256 public constant LOCK_2555_DAYS = 2555 days; // 7 years

    // Staking state
    struct Stake {
        uint256 amount;
        uint256 lockEnd;
        uint256 lastRewardTime;
        uint256 accumulatedRewards;
        uint256 lockDuration;
    }

    mapping(address => Stake) public lpStakes;
    mapping(address => Stake) public torqStakes;
    mapping(address => uint256) public votePower;

    // Participant tracking
    mapping(uint256 => uint256) public lockPeriodParticipants; // lockDuration => participant count
    mapping(uint256 => mapping(address => bool)) public lockPeriodStakers; // lockDuration => address => isStaking

    // Total staked tracking per lock period
    mapping(uint256 => uint256) public lockPeriodTotalStaked; // lockDuration => total staked amount

    // Global TVL tracking
    uint256 public totalLpStaked;
    uint256 public totalTorqStaked;

    // Reward parameters
    uint256 public lastUpdateTime;

    // Events
    event Staked(address indexed user, uint256 amount, uint256 lockDuration, bool isLp);
    event Unstaked(address indexed user, uint256 amount, bool isLp, bool isEarly);
    event RewardPaid(address indexed user, uint256 reward, bool isLp);
    event VotePowerUpdated(address indexed user, uint256 newPower);
    event TreasuryFeeRecipientUpdated(address indexed newRecipient);
    event EarlyExitPenaltyPaid(address indexed user, uint256 amount, bool isLp);
    event APRUpdated(uint256 newLpAPR, uint256 newTorqAPR, uint256 totalTVL);
    
    // Cross-chain events
    event CrossChainStakeRequested(
        address indexed user,
        uint16 indexed dstChainId,
        uint256 amount,
        uint256 lockDuration,
        bool isLp,
        bool isStake
    );
    event CrossChainStakeCompleted(
        address indexed user,
        uint16 indexed srcChainId,
        uint256 amount,
        bool isLp,
        bool isStake
    );
    event CrossChainStakeFailed(
        address indexed user,
        uint16 indexed srcChainId,
        string reason
    );

    // Errors
    error TorqueStake__UnsupportedChain();
    error TorqueStake__InvalidStakeAddress();
    error TorqueStake__CrossChainStakeFailed();

    constructor(
        address _lpToken,
        address _torqToken,
        address _rewardToken,
        address _treasuryFeeRecipient,
        address _lzEndpoint,
        address _owner
    ) OApp(_lzEndpoint, _owner) Ownable(_owner) {
        lpToken = IERC20(_lpToken);
        torqToken = IERC20(_torqToken);
        rewardToken = IERC20(_rewardToken);
        treasuryFeeRecipient = _treasuryFeeRecipient;
        lastUpdateTime = block.timestamp;
        
        // Initialize supported chains
        _initializeSupportedChains();
    }

    function _initializeSupportedChains() internal {
        supportedChainIds[1] = true;      // Ethereum
        supportedChainIds[42161] = true;  // Arbitrum
        supportedChainIds[10] = true;     // Optimism
        supportedChainIds[137] = true;    // Polygon
        supportedChainIds[8453] = true;   // Base
        supportedChainIds[146] = true;    // Sonic
        supportedChainIds[2741] = true;   // Abstract
        supportedChainIds[56] = true;     // BSC
        supportedChainIds[252] = true;    // Fraxtal
        supportedChainIds[43114] = true;  // Avalanche
    }

    /**
     * @dev Stake tokens on multiple chains simultaneously
     */
    function stakeCrossChain(
        uint16[] calldata dstChainIds,
        uint256[] calldata amounts,
        uint256[] calldata lockDurations,
        bool[] calldata isLp,
        bytes[] calldata adapterParams
    ) external nonReentrant {
        require(
            dstChainIds.length == amounts.length &&
            dstChainIds.length == lockDurations.length &&
            dstChainIds.length == isLp.length &&
            dstChainIds.length == adapterParams.length,
            "Array length mismatch"
        );

        for (uint256 i = 0; i < dstChainIds.length; i++) {
            if (!supportedChainIds[dstChainIds[i]]) {
                revert TorqueStake__UnsupportedChain();
            }

            // Transfer tokens to this contract first
            if (isLp[i]) {
                lpToken.transferFrom(msg.sender, address(this), amounts[i]);
            } else {
                torqToken.transferFrom(msg.sender, address(this), amounts[i]);
            }

            // Send cross-chain stake request
            _sendCrossChainStakeRequest(
                dstChainIds[i],
                msg.sender,
                amounts[i],
                lockDurations[i],
                isLp[i],
                true, // isStake
                adapterParams[i]
            );

            emit CrossChainStakeRequested(
                msg.sender,
                dstChainIds[i],
                amounts[i],
                lockDurations[i],
                isLp[i],
                true
            );
        }
    }

    /**
     * @dev Unstake tokens from multiple chains
     */
    function unstakeCrossChain(
        uint16[] calldata dstChainIds,
        bool[] calldata isLp,
        bytes[] calldata adapterParams
    ) external nonReentrant {
        require(
            dstChainIds.length == isLp.length &&
            dstChainIds.length == adapterParams.length,
            "Array length mismatch"
        );

        for (uint256 i = 0; i < dstChainIds.length; i++) {
            if (!supportedChainIds[dstChainIds[i]]) {
                revert TorqueStake__UnsupportedChain();
            }

            // Send cross-chain unstake request
            _sendCrossChainStakeRequest(
                dstChainIds[i],
                msg.sender,
                0, // amount (not used for unstake)
                0, // lockDuration (not used for unstake)
                isLp[i], // isLp - specify which token type to unstake
                false, // isStake
                adapterParams[i]
            );

            emit CrossChainStakeRequested(
                msg.sender,
                dstChainIds[i],
                0,
                0,
                isLp[i],
                false
            );
        }
    }

    /**
     * @dev Handle incoming cross-chain stake requests
     */
    function _lzReceive(
        Origin calldata _origin,
        bytes32 _guid,
        bytes calldata _message,
        address _executor,
        bytes calldata _extraData
    ) internal override {
        require(supportedChainIds[uint16(_origin.srcEid)], "Chain not supported");
        require(stakeAddresses[uint16(_origin.srcEid)] == address(uint160(uint256(bytes32(_origin.sender)))), "Invalid stake contract");

        bytes32 messageId = keccak256(abi.encodePacked(_origin.srcEid, _origin.sender, _guid));
        require(!processedMessages[messageId], "Message already processed");
        processedMessages[messageId] = true;

        CrossChainStakeRequest memory request = abi.decode(_message, (CrossChainStakeRequest));
        request.sourceChainId = uint16(_origin.srcEid);

        // Process cross-chain stake request
        if (request.isStake) {
            _processCrossChainStake(request);
        } else {
            _processCrossChainUnstake(request);
        }
    }

    /**
     * @dev Send cross-chain stake request
     */
    function _sendCrossChainStakeRequest(
        uint16 dstChainId,
        address user,
        uint256 amount,
        uint256 lockDuration,
        bool isLp,
        bool isStake,
        bytes calldata adapterParams
    ) internal {
        address dstStake = stakeAddresses[dstChainId];
        if (dstStake == address(0)) {
            revert TorqueStake__InvalidStakeAddress();
        }

        CrossChainStakeRequest memory request = CrossChainStakeRequest({
            user: user,
            amount: amount,
            lockDuration: lockDuration,
            isLp: isLp,
            sourceChainId: uint16(block.chainid),
            isStake: isStake
        });

        bytes memory payload = abi.encode(request);

        _lzSend(
            dstChainId,
            payload,
            adapterParams,
            MessagingFee(0, 0),
            payable(msg.sender)
        );
    }

    function setTreasuryFeeRecipient(address _treasuryFeeRecipient) external onlyOwner {
        require(_treasuryFeeRecipient != address(0), "Invalid treasury address");
        treasuryFeeRecipient = _treasuryFeeRecipient;
        emit TreasuryFeeRecipientUpdated(_treasuryFeeRecipient);
    }

    /**
     * @dev Set stake contract address for a specific chain
     */
    function setStakeAddress(uint16 chainId, address stakeAddress) external onlyOwner {
        require(supportedChainIds[chainId], "Unsupported chain");
        require(stakeAddress != address(0), "Invalid stake address");
        stakeAddresses[chainId] = stakeAddress;
    }

    /**
     * @dev Get cross-chain stake info for a user
     */
    function getCrossChainStakeInfo(address user, uint16 chainId) external view returns (uint256) {
        return crossChainStakes[chainId][user];
    }

    /**
     * @dev Get total cross-chain stakes for a user across all chains
     */
    function getTotalCrossChainStakes(address user) external view returns (uint256) {
        return totalCrossChainStakes[user];
    }

    /**
     * @dev Get cross-chain stake quote (gas estimation)
     */
    function getCrossChainStakeQuote(
        uint16[] calldata dstChainIds,
        bytes[] calldata adapterParams
    ) external view returns (uint256 totalGasEstimate) {
        require(dstChainIds.length == adapterParams.length, "Array length mismatch");
        
        totalGasEstimate = 0;
        for (uint256 i = 0; i < dstChainIds.length; i++) {
            uint256 messageGas = _estimateGasForMessage(dstChainIds[i], adapterParams[i]);
            totalGasEstimate += messageGas;
        }
        
        totalGasEstimate += 21000; // Base transaction cost
    }

    /**
     * @dev Estimate gas for a single cross-chain message
     */
    function _estimateGasForMessage(
        uint16 dstChainId,
        bytes calldata adapterParams
    ) internal view returns (uint256) {
        // Conservative estimate per message
        return 100000;
    }

    /**
     * @dev Internal function to stake LP tokens
     */
    function _stakeLpInternal(address user, uint256 amount, uint256 lockDuration) internal {
        require(amount > 0, "Cannot stake 0");
        require(lockDuration >= MIN_LOCK_DURATION, "Lock too short");
        require(lockDuration <= MAX_LOCK_DURATION, "Lock too long");

        Stake storage stake = lpStakes[user];
        if (stake.amount > 0) {
            _updateRewards(user, true);
        }

        // Track new participant for this lock period
        if (!lockPeriodStakers[lockDuration][user]) {
            lockPeriodStakers[lockDuration][user] = true;
            lockPeriodParticipants[lockDuration]++;
        }

        // Track total staked for this lock period
        lockPeriodTotalStaked[lockDuration] += amount;

        // Update global TVL
        totalLpStaked += amount;

        stake.amount += amount;
        stake.lockEnd = block.timestamp + lockDuration;
        stake.lastRewardTime = block.timestamp;
        stake.lockDuration = lockDuration;

        _updateVotePower(user);
        emit Staked(user, amount, lockDuration, true);
    }

    /**
     * @dev Internal function to stake TORQ tokens
     */
    function _stakeTorqInternal(address user, uint256 amount, uint256 lockDuration) internal {
        require(amount > 0, "Cannot stake 0");
        require(lockDuration >= MIN_LOCK_DURATION, "Lock too short");
        require(lockDuration <= MAX_LOCK_DURATION, "Lock too long");

        Stake storage stake = torqStakes[user];
        if (stake.amount > 0) {
            _updateRewards(user, false);
        }

        // Track new participant for this lock period
        if (!lockPeriodStakers[lockDuration][user]) {
            lockPeriodStakers[lockDuration][user] = true;
            lockPeriodParticipants[lockDuration]++;
        }

        // Track total staked for this lock period
        lockPeriodTotalStaked[lockDuration] += amount;

        // Update global TVL
        totalTorqStaked += amount;

        stake.amount += amount;
        stake.lockEnd = block.timestamp + lockDuration;
        stake.lastRewardTime = block.timestamp;
        stake.lockDuration = lockDuration;

        _updateVotePower(user);
        emit Staked(user, amount, lockDuration, false);
    }

    /**
     * @dev Calculate early exit penalty (basis points) based on lock duration
     * Formula: 50% - (lockDays / 2555) * 25%
     * Returns penalty in basis points (e.g., 5000 = 50%)
     */
    function _calculateEarlyExitPenalty(uint256 lockDuration) internal pure returns (uint256) {
        uint256 lockDays = lockDuration / 1 days;
        if (lockDays >= 2555) {
            return MIN_EARLY_EXIT_PENALTY; // 25%
        }
        // Linear decrease from 50% to 25%
        uint256 penalty = MAX_EARLY_EXIT_PENALTY - (lockDays * 2500 / 2555);
        if (penalty < MIN_EARLY_EXIT_PENALTY) {
            return MIN_EARLY_EXIT_PENALTY;
        }
        return penalty;
    }

    /**
     * @dev Internal function to unstake LP tokens
     */
    function _unstakeLpInternal(address user) internal {
        Stake storage stake = lpStakes[user];
        require(stake.amount > 0, "No stake");

        _updateRewards(user, true);
        uint256 amount = stake.amount;
        bool isEarly = block.timestamp < stake.lockEnd;
        uint256 penalty = 0;

        if (isEarly) {
            uint256 penaltyBps = _calculateEarlyExitPenalty(stake.lockDuration);
            penalty = (amount * penaltyBps) / 10000;
            amount -= penalty;
        }

        // Decrease total staked for this lock period
        lockPeriodTotalStaked[stake.lockDuration] -= stake.amount;

        stake.amount = 0;
        stake.lockEnd = 0;
        stake.lastRewardTime = 0;
        stake.lockDuration = 0;

        _updateVotePower(user);

        if (penalty > 0) {
            lpToken.transfer(treasuryFeeRecipient, penalty);
            emit EarlyExitPenaltyPaid(user, penalty, true);
        }
        lpToken.transfer(user, amount);

        emit Unstaked(user, amount, true, isEarly);
    }

    /**
     * @dev Internal function to unstake TORQ tokens
     */
    function _unstakeTorqInternal(address user) internal {
        Stake storage stake = torqStakes[user];
        require(stake.amount > 0, "No stake");

        _updateRewards(user, false);
        uint256 amount = stake.amount;
        bool isEarly = block.timestamp < stake.lockEnd;
        uint256 penalty = 0;

        if (isEarly) {
            uint256 penaltyBps = _calculateEarlyExitPenalty(stake.lockDuration);
            penalty = (amount * penaltyBps) / 10000;
            amount -= penalty;
        }

        // Decrease total staked for this lock period
        lockPeriodTotalStaked[stake.lockDuration] -= stake.amount;

        stake.amount = 0;
        stake.lockEnd = 0;
        stake.lastRewardTime = 0;
        stake.lockDuration = 0;

        _updateVotePower(user);

        if (penalty > 0) {
            torqToken.transfer(treasuryFeeRecipient, penalty);
            emit EarlyExitPenaltyPaid(user, penalty, false);
        }
        torqToken.transfer(user, amount);

        emit Unstaked(user, amount, false, isEarly);
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

        // Track new participant for this lock period
        if (!lockPeriodStakers[lockDuration][msg.sender]) {
            lockPeriodStakers[lockDuration][msg.sender] = true;
            lockPeriodParticipants[lockDuration]++;
        }

        // Track total staked for this lock period
        lockPeriodTotalStaked[lockDuration] += amount;

        // Update global TVL
        totalLpStaked += amount;

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

        // Track new participant for this lock period
        if (!lockPeriodStakers[lockDuration][msg.sender]) {
            lockPeriodStakers[lockDuration][msg.sender] = true;
            lockPeriodParticipants[lockDuration]++;
        }

        // Track total staked for this lock period
        lockPeriodTotalStaked[lockDuration] += amount;

        // Update global TVL
        totalTorqStaked += amount;

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
            uint256 penaltyBps = _calculateEarlyExitPenalty(stake.lockDuration);
            penalty = (amount * penaltyBps) / 10000;
            amount -= penalty;
        }

        // Decrease total staked for this lock period
        lockPeriodTotalStaked[stake.lockDuration] -= stake.amount;

        // Update global TVL
        totalLpStaked -= stake.amount;

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
            uint256 penaltyBps = _calculateEarlyExitPenalty(stake.lockDuration);
            penalty = (amount * penaltyBps) / 10000;
            amount -= penalty;
        }

        // Decrease total staked for this lock period
        lockPeriodTotalStaked[stake.lockDuration] -= stake.amount;

        // Update global TVL
        totalTorqStaked -= stake.amount;

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

        // Calculate APR based on lock duration and current TVL
        uint256 apr = _calculateAPR(stake.lockDuration, isLp);
        
        // Calculate daily reward rate from APR
        uint256 dailyRate = (apr * APR_PRECISION) / (365 * APR_PRECISION);
        
        // Calculate reward
        uint256 reward = (stake.amount * dailyRate * timeElapsed) / (1 days * APR_PRECISION);
        
        stake.accumulatedRewards += reward;
        stake.lastRewardTime = block.timestamp;
    }

    /**
     * @dev Calculate dynamic APR based on lock duration and current TVL
     * @param lockDuration The lock duration in seconds
     * @param isLp Whether this is for LP staking (true) or TORQ staking (false)
     * @return apr The APR in basis points
     */
    function _calculateAPR(uint256 lockDuration, bool isLp) internal view returns (uint256) {
        // Get base APR for the token type
        uint256 baseAPR = isLp ? BASE_APR_LP : BASE_APR_TORQ;
        uint256 maxAPR = isLp ? MAX_APR_LP : MAX_APR_TORQ;
        
        // Calculate lock duration multiplier (1x to 3x)
        uint256 lockMultiplier = _calculateLockMultiplier(lockDuration);
        
        // Calculate TVL scaling factor
        uint256 tvlScaling = _calculateTVLScaling(isLp);
        
        // Calculate final APR: baseAPR * lockMultiplier * tvlScaling
        uint256 apr = (baseAPR * lockMultiplier * tvlScaling) / (1e18 * 1e18);
        
        // Cap at maximum APR
        if (apr > maxAPR) {
            apr = maxAPR;
        }
        
        return apr;
    }

    /**
     * @dev Calculate lock duration multiplier (1x to 5.5x)
     * @param lockDuration The lock duration in seconds
     * @return multiplier The lock multiplier (in wei, divide by 1e18)
     */
    function _calculateLockMultiplier(uint256 lockDuration) internal pure returns (uint256) {
        if (lockDuration <= MIN_LOCK_DURATION) {
            return LOCK_MULTIPLIER_MIN; // 1x
        }
        if (lockDuration >= MAX_LOCK_DURATION) {
            return LOCK_MULTIPLIER_MAX; // 5.5x
        }

        // Linear interpolation between 1x and 5.5x based on lock duration
        uint256 durationRange = MAX_LOCK_DURATION - MIN_LOCK_DURATION;
        uint256 multiplierRange = LOCK_MULTIPLIER_MAX - LOCK_MULTIPLIER_MIN;
        
        return LOCK_MULTIPLIER_MIN + ((lockDuration - MIN_LOCK_DURATION) * multiplierRange) / durationRange;
    }

    /**
     * @dev Calculate TVL scaling factor (starts at 1x, decreases as TVL increases)
     * @param isLp Whether this is for LP staking (true) or TORQ staking (false)
     * @return scaling The TVL scaling factor (in wei, divide by 1e18)
     */
    function _calculateTVLScaling(bool isLp) internal view returns (uint256) {
        uint256 totalTVL = isLp ? totalLpStaked : totalTorqStaked;
        
        // If TVL is below minimum, return 1x scaling
        if (totalTVL < MIN_TVL_FOR_DECAY) {
            return 1e18;
        }
        
        // Calculate how many doublings have occurred since minimum TVL
        // log2(totalTVL / MIN_TVL_FOR_DECAY)
        uint256 tvlRatio = (totalTVL * 1e18) / MIN_TVL_FOR_DECAY;
        uint256 doublings = 0;
        
        // Simple log2 approximation
        while (tvlRatio > 2e18) {
            tvlRatio = tvlRatio / 2;
            doublings++;
        }
        
        // Apply decay: 1x * (1 - decay_rate)^doublings
        // For 50% decay per doubling: 1x * 0.5^doublings
        uint256 scaling = 1e18;
        for (uint256 i = 0; i < doublings; i++) {
            scaling = (scaling * (10000 - TVL_DECAY_RATE)) / 10000;
        }
        
        // Minimum scaling of 0.1x (10%)
        if (scaling < 1e17) {
            scaling = 1e17;
        }
        
        return scaling;
    }

    /**
     * @dev Calculate staking multiplier based on lock duration
     * This matches the frontend multiplier display (1x to 5.5x)
     */
    function _calculateStakeMultiplier(uint256 lockDuration) internal pure returns (uint256) {
        if (lockDuration <= MIN_LOCK_DURATION) {
            return MIN_STAKE_MULTIPLIER; // 1x
        }
        if (lockDuration >= MAX_LOCK_DURATION) {
            return MAX_STAKE_MULTIPLIER; // 5.5x
        }

        // Linear interpolation between 1x and 5.5x based on lock duration
        uint256 durationRange = MAX_LOCK_DURATION - MIN_LOCK_DURATION;
        uint256 multiplierRange = MAX_STAKE_MULTIPLIER - MIN_STAKE_MULTIPLIER;
        
        return MIN_STAKE_MULTIPLIER + ((lockDuration - MIN_LOCK_DURATION) * multiplierRange) / durationRange;
    }

    /**
     * @dev Get staking multiplier for a specific lock duration (public function)
     * @param lockDuration The lock duration in seconds
     * @return multiplier The staking multiplier (in wei, divide by 1e18 to get the multiplier value)
     */
    function getStakeMultiplier(uint256 lockDuration) external pure returns (uint256 multiplier) {
        return _calculateStakeMultiplier(lockDuration);
    }

    /**
     * @dev Public function to get early exit penalty (basis points) for a given lock duration
     * @param lockDuration The lock duration in seconds
     * @return penalty The penalty in basis points (e.g., 5000 = 50%)
     */
    function getEarlyExitPenalty(uint256 lockDuration) external pure returns (uint256 penalty) {
        return _calculateEarlyExitPenalty(lockDuration);
    }

    /**
     * @dev Get number of participants for a given lock duration
     * @param lockDuration The lock duration in seconds
     * @return participants The number of unique participants for this lock period
     */
    function getLockPeriodParticipants(uint256 lockDuration) external view returns (uint256 participants) {
        return lockPeriodParticipants[lockDuration];
    }

    /**
     * @dev Get APR for a given lock duration and token type
     * @param lockDuration The lock duration in seconds
     * @param isLp Whether this is for LP staking (true) or TORQ staking (false)
     * @return apr The APR in basis points (e.g., 2000 = 20%)
     */
    function getAPR(uint256 lockDuration, bool isLp) external view returns (uint256 apr) {
        return _calculateAPR(lockDuration, isLp);
    }

    /**
     * @dev Get total staked amount for a given lock duration
     * @param lockDuration The lock duration in seconds
     * @return totalStaked The total amount staked for this lock period
     */
    function getTotalStakedForLockPeriod(uint256 lockDuration) external view returns (uint256 totalStaked) {
        return lockPeriodTotalStaked[lockDuration];
    }

    /**
     * @dev Get current TVL for LP and TORQ staking
     * @return lpTVL Total LP tokens staked
     * @return torqTVL Total TORQ tokens staked
     * @return totalTVL Combined TVL
     */
    function getTVL() external view returns (uint256 lpTVL, uint256 torqTVL, uint256 totalTVL) {
        lpTVL = totalLpStaked;
        torqTVL = totalTorqStaked;
        totalTVL = lpTVL + torqTVL;
    }

    /**
     * @dev Get TVL scaling factor for a given token type
     * @param isLp Whether this is for LP staking (true) or TORQ staking (false)
     * @return scaling The TVL scaling factor (in wei, divide by 1e18)
     */
    function getTVLScaling(bool isLp) external view returns (uint256 scaling) {
        return _calculateTVLScaling(isLp);
    }

    /**
     * @dev Get lock duration multiplier for a given lock duration
     * @param lockDuration The lock duration in seconds
     * @return multiplier The lock multiplier (in wei, divide by 1e18)
     */
    function getLockMultiplier(uint256 lockDuration) external pure returns (uint256 multiplier) {
        return _calculateLockMultiplier(lockDuration);
    }

    /**
     * @dev Get all standard lock periods
     * @return lockPeriods Array of standard lock periods in seconds
     */
    function getStandardLockPeriods() external pure returns (uint256[] memory lockPeriods) {
        lockPeriods = new uint256[](11);
        lockPeriods[0] = LOCK_30_DAYS;
        lockPeriods[1] = LOCK_90_DAYS;
        lockPeriods[2] = LOCK_180_DAYS;
        lockPeriods[3] = LOCK_365_DAYS;
        lockPeriods[4] = LOCK_730_DAYS;
        lockPeriods[5] = LOCK_1095_DAYS;
        lockPeriods[6] = LOCK_1460_DAYS;
        lockPeriods[7] = LOCK_1825_DAYS;
        lockPeriods[8] = LOCK_2190_DAYS;
        lockPeriods[9] = LOCK_2555_DAYS;
    }

    /**
     * @dev Get APR for all standard lock periods
     * @param isLp Whether this is for LP staking (true) or TORQ staking (false)
     * @return lockPeriods Array of lock periods
     * @return aprs Array of corresponding APRs in basis points
     */
    function getStandardLockAPRs(bool isLp) external view returns (uint256[] memory lockPeriods, uint256[] memory aprs) {
        lockPeriods = new uint256[](11);
        aprs = new uint256[](11);
        
        lockPeriods[0] = LOCK_30_DAYS;
        lockPeriods[1] = LOCK_90_DAYS;
        lockPeriods[2] = LOCK_180_DAYS;
        lockPeriods[3] = LOCK_365_DAYS;
        lockPeriods[4] = LOCK_730_DAYS;
        lockPeriods[5] = LOCK_1095_DAYS;
        lockPeriods[6] = LOCK_1460_DAYS;
        lockPeriods[7] = LOCK_1825_DAYS;
        lockPeriods[8] = LOCK_2190_DAYS;
        lockPeriods[9] = LOCK_2555_DAYS;
        
        for (uint256 i = 0; i < 11; i++) {
            aprs[i] = _calculateAPR(lockPeriods[i], isLp);
        }
    }

    /**
     * @dev Check if a lock duration is a standard period
     * @param lockDuration The lock duration to check
     * @return isStandard True if it's a standard lock period
     */
    function isStandardLockPeriod(uint256 lockDuration) external pure returns (bool isStandard) {
        return (
            lockDuration == LOCK_30_DAYS ||
            lockDuration == LOCK_90_DAYS ||
            lockDuration == LOCK_180_DAYS ||
            lockDuration == LOCK_365_DAYS ||
            lockDuration == LOCK_730_DAYS ||
            lockDuration == LOCK_1095_DAYS ||
            lockDuration == LOCK_1460_DAYS ||
            lockDuration == LOCK_1825_DAYS ||
            lockDuration == LOCK_2190_DAYS ||
            lockDuration == LOCK_2555_DAYS
        );
    }

    /**
     * @dev Get daily rewards for a given lock duration and staked amount
     * @param lockDuration The lock duration in seconds
     * @param stakedAmount The amount staked
     * @param isLp Whether this is for LP staking (true) or TORQ staking (false)
     * @return dailyRewards The daily rewards in reward tokens
     */
    function getDailyRewards(uint256 lockDuration, uint256 stakedAmount, bool isLp) external view returns (uint256 dailyRewards) {
        uint256 apr = _calculateAPR(lockDuration, isLp);
        uint256 dailyRate = (apr * APR_PRECISION) / (365 * APR_PRECISION);
        return (stakedAmount * dailyRate) / (1 days * APR_PRECISION);
    }

    /**
     * @dev Get comprehensive pool statistics for a lock period
     * @param lockDuration The lock duration in seconds
     * @param isLp Whether this is for LP staking (true) or TORQ staking (false)
     * @return apr The APR in basis points
     * @return multiplier The staking multiplier (in wei, divide by 1e18)
     * @return participants The number of participants
     * @return earlyExitPenalty The early exit penalty in basis points
     */
    function getPoolStats(uint256 lockDuration, bool isLp) external view returns (
        uint256 apr,
        uint256 multiplier,
        uint256 participants,
        uint256 earlyExitPenalty
    ) {
        apr = _calculateAPR(lockDuration, isLp);
        multiplier = _calculateStakeMultiplier(lockDuration);
        participants = lockPeriodParticipants[lockDuration];
        earlyExitPenalty = _calculateEarlyExitPenalty(lockDuration);
    }

    /**
     * @dev Get user's accumulated rewards without claiming them
     * @param user The user address
     * @param isLp Whether to check LP or TORQ stakes
     * @return rewards The accumulated rewards
     */
    function getAccumulatedRewards(address user, bool isLp) external view returns (uint256 rewards) {
        Stake storage stake = isLp ? lpStakes[user] : torqStakes[user];
        if (stake.amount == 0) return 0;

        uint256 timeElapsed = block.timestamp - stake.lastRewardTime;
        if (timeElapsed == 0) return stake.accumulatedRewards;

        // Calculate APR based on lock duration and current TVL
        uint256 apr = _calculateAPR(stake.lockDuration, isLp);
        
        // Calculate daily reward rate from APR
        uint256 dailyRate = (apr * APR_PRECISION) / (365 * APR_PRECISION);
        
        // Calculate reward
        uint256 reward = (stake.amount * dailyRate * timeElapsed) / (1 days * APR_PRECISION);
        
        return stake.accumulatedRewards + reward;
    }

    /**
     * @dev Get comprehensive user position data
     * @param user The user address
     * @return lpStakedAmount LP tokens staked
     * @return lpLockEnd LP lock end timestamp
     * @return lpAccumulatedRewards LP accumulated rewards
     * @return lpCurrentAPR LP current APR in basis points
     * @return lpMultiplier LP staking multiplier
     * @return torqStakedAmount TORQ tokens staked
     * @return torqLockEnd TORQ lock end timestamp
     * @return torqAccumulatedRewards TORQ accumulated rewards
     * @return torqCurrentAPR TORQ current APR in basis points
     * @return torqMultiplier TORQ staking multiplier
     * @return userVotePower User's total vote power
     */
    function getUserPosition(address user) external view returns (
        uint256 lpStakedAmount,
        uint256 lpLockEnd,
        uint256 lpAccumulatedRewards,
        uint256 lpCurrentAPR,
        uint256 lpMultiplier,
        uint256 torqStakedAmount,
        uint256 torqLockEnd,
        uint256 torqAccumulatedRewards,
        uint256 torqCurrentAPR,
        uint256 torqMultiplier,
        uint256 userVotePower
    ) {
        Stake storage lpStake = lpStakes[user];
        Stake storage torqStake = torqStakes[user];

        lpStakedAmount = lpStake.amount;
        lpLockEnd = lpStake.lockEnd;
        lpCurrentAPR = _calculateAPR(lpStake.lockDuration, true); // true for LP
        lpMultiplier = _calculateStakeMultiplier(lpStake.lockDuration);

        // Calculate LP accumulated rewards
        if (lpStake.amount > 0) {
            uint256 timeElapsed = block.timestamp - lpStake.lastRewardTime;
            if (timeElapsed > 0) {
                uint256 apr = _calculateAPR(lpStake.lockDuration, true); // true for LP
                uint256 dailyRate = (apr * APR_PRECISION) / (365 * APR_PRECISION);
                uint256 reward = (lpStake.amount * dailyRate * timeElapsed) / (1 days * APR_PRECISION);
                lpAccumulatedRewards = lpStake.accumulatedRewards + reward;
            } else {
                lpAccumulatedRewards = lpStake.accumulatedRewards;
            }
        } else {
            lpAccumulatedRewards = 0;
        }

        torqStakedAmount = torqStake.amount;
        torqLockEnd = torqStake.lockEnd;
        torqCurrentAPR = _calculateAPR(torqStake.lockDuration, false); // false for TORQ
        torqMultiplier = _calculateStakeMultiplier(torqStake.lockDuration);

        // Calculate TORQ accumulated rewards
        if (torqStake.amount > 0) {
            uint256 timeElapsed = block.timestamp - torqStake.lastRewardTime;
            if (timeElapsed > 0) {
                uint256 apr = _calculateAPR(torqStake.lockDuration, false); // false for TORQ
                uint256 dailyRate = (apr * APR_PRECISION) / (365 * APR_PRECISION);
                uint256 reward = (torqStake.amount * dailyRate * timeElapsed) / (1 days * APR_PRECISION);
                torqAccumulatedRewards = torqStake.accumulatedRewards + reward;
            } else {
                torqAccumulatedRewards = torqStake.accumulatedRewards;
            }
        } else {
            torqAccumulatedRewards = 0;
        }

        userVotePower = votePower[user];
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
        uint256 lpMultiplier,
        uint256 torqAmount,
        uint256 torqLockEnd,
        uint256 torqRewards,
        uint256 torqApr,
        uint256 torqMultiplier,
        uint256 userVotePower
    ) {
        Stake storage lpStake = lpStakes[user];
        Stake storage torqStake = torqStakes[user];

        lpAmount = lpStake.amount;
        lpLockEnd = lpStake.lockEnd;
        lpRewards = lpStake.accumulatedRewards;
        lpApr = _calculateAPR(lpStake.lockDuration, true); // true for LP
        lpMultiplier = _calculateStakeMultiplier(lpStake.lockDuration);

        torqAmount = torqStake.amount;
        torqLockEnd = torqStake.lockEnd;
        torqRewards = torqStake.accumulatedRewards;
        torqApr = _calculateAPR(torqStake.lockDuration, false); // false for TORQ
        torqMultiplier = _calculateStakeMultiplier(torqStake.lockDuration);

        userVotePower = votePower[user];
    }

    function _processCrossChainStake(CrossChainStakeRequest memory request) internal {
        if (request.isLp) {
            Stake storage stake = lpStakes[request.user];
            stake.amount += request.amount;
            stake.lockEnd = block.timestamp + request.lockDuration;
            stake.lastRewardTime = block.timestamp;
            stake.lockDuration = request.lockDuration;
            _updateVotePower(request.user);
        } else {
            Stake storage stake = torqStakes[request.user];
            stake.amount += request.amount;
            stake.lockEnd = block.timestamp + request.lockDuration;
            stake.lastRewardTime = block.timestamp;
            stake.lockDuration = request.lockDuration;
            _updateVotePower(request.user);
        }

        crossChainStakes[request.sourceChainId][request.user] += request.amount;
        totalCrossChainStakes[request.user] += request.amount;

        emit CrossChainStakeCompleted(
            request.user,
            request.sourceChainId,
            request.amount,
            request.isLp,
            true
        );
    }

    function _processCrossChainUnstake(CrossChainStakeRequest memory request) internal {
        if (request.isLp) {
            Stake storage stake = lpStakes[request.user];
            require(stake.amount >= request.amount, "Insufficient stake");
            stake.amount -= request.amount;
            _updateVotePower(request.user);
        } else {
            Stake storage stake = torqStakes[request.user];
            require(stake.amount >= request.amount, "Insufficient stake");
            stake.amount -= request.amount;
            _updateVotePower(request.user);
        }

        crossChainStakes[request.sourceChainId][request.user] -= request.amount;
        totalCrossChainStakes[request.user] -= request.amount;

        emit CrossChainStakeCompleted(
            request.user,
            request.sourceChainId,
            request.amount,
            request.isLp,
            false
        );
    }

    /**
     * @dev Emergency function to recover stuck tokens
     */
    function emergencyWithdraw(
        address token,
        address to,
        uint256 amount
    ) external onlyOwner {
        IERC20(token).transfer(to, amount);
    }
}
