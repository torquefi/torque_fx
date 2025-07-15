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
        bool isLp; // true for LP, false for TORQ
        uint16 sourceChainId;
        bool isStake; // true for stake, false for unstake
    }

    // Staking parameters
    uint256 public constant MIN_LOCK_DURATION = 7 days;
    uint256 public constant MAX_LOCK_DURATION = 7 * 365 days; // 7 years
    uint256 public constant EARLY_EXIT_PENALTY = 5000; // 50% in basis points
    uint256 public constant VOTE_POWER_MULTIPLIER = 2e18; // 2x vote power for max lock

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
        uint256 lockDuration;
    }

    mapping(address => Stake) public lpStakes;
    mapping(address => Stake) public torqStakes;
    mapping(address => uint256) public votePower;

    // Reward parameters
    uint256 public lastUpdateTime;

    // Events
    event Staked(address indexed user, uint256 amount, uint256 lockDuration, bool isLp);
    event Unstaked(address indexed user, uint256 amount, bool isLp, bool isEarly);
    event RewardPaid(address indexed user, uint256 reward, bool isLp);
    event VotePowerUpdated(address indexed user, uint256 newPower);
    event TreasuryFeeRecipientUpdated(address indexed newRecipient);
    event EarlyExitPenaltyPaid(address indexed user, uint256 amount, bool isLp);
    
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
        bytes[] calldata adapterParams
    ) external nonReentrant {
        require(
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
                false, // isLp (not used for unstake)
                false, // isStake
                adapterParams[i]
            );

            emit CrossChainStakeRequested(
                msg.sender,
                dstChainIds[i],
                0,
                0,
                false,
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

        stake.amount += amount;
        stake.lockEnd = block.timestamp + lockDuration;
        stake.lastRewardTime = block.timestamp;
        stake.lockDuration = lockDuration;

        _updateVotePower(user);
        emit Staked(user, amount, lockDuration, false);
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
            penalty = (amount * EARLY_EXIT_PENALTY) / 10000;
            amount -= penalty;
        }

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
            penalty = (amount * EARLY_EXIT_PENALTY) / 10000;
            amount -= penalty;
        }

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
