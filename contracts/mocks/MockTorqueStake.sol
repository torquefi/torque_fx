// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/**
 * @title MockTorqueStake
 * @dev Simplified mock version of TorqueStake for testing without LayerZero
 */
contract MockTorqueStake is Ownable, ReentrancyGuard {
    IERC20 public immutable lpToken;
    IERC20 public immutable torqToken;
    IERC20 public immutable rewardToken;
    address public immutable treasury;

    uint256 public constant MIN_LOCK_DURATION = 7 days;
    uint256 public constant MAX_LOCK_DURATION = 7 * 365 days;
    uint256 public constant MAX_MULTIPLIER = 5e18; // 5x in wei

    struct StakeInfo {
        uint256 amount;
        uint256 lockDuration;
        uint256 startTime;
        uint256 multiplier;
        bool isActive;
    }

    mapping(address => StakeInfo) public stakes;
    mapping(address => uint256) public votePower;

    event Staked(address indexed user, uint256 amount, uint256 lockDuration, uint256 multiplier);
    event Unstaked(address indexed user, uint256 amount);
    event RewardsClaimed(address indexed user, uint256 amount);

    constructor(
        address _lpToken,
        address _torqToken,
        address _rewardToken,
        address _treasury,
        address _owner
    ) Ownable(_owner) {
        lpToken = IERC20(_lpToken);
        torqToken = IERC20(_torqToken);
        rewardToken = IERC20(_rewardToken);
        treasury = _treasury;
    }

    function stakeTORQ(uint256 amount, uint256 lockDuration) external nonReentrant {
        require(amount > 0, "Amount must be greater than 0");
        require(lockDuration >= MIN_LOCK_DURATION, "Lock duration too short");
        require(lockDuration <= MAX_LOCK_DURATION, "Lock duration too long");
        require(stakes[msg.sender].amount == 0, "Already staked");

        uint256 multiplier = getStakeMultiplier(lockDuration);
        
        stakes[msg.sender] = StakeInfo({
            amount: amount,
            lockDuration: lockDuration,
            startTime: block.timestamp,
            multiplier: multiplier,
            isActive: true
        });

        votePower[msg.sender] = (amount * multiplier) / 1e18;

        require(torqToken.transferFrom(msg.sender, address(this), amount), "Transfer failed");

        emit Staked(msg.sender, amount, lockDuration, multiplier);
    }

    function stakeLP(uint256 amount, uint256 lockDuration) external nonReentrant {
        require(amount > 0, "Amount must be greater than 0");
        require(lockDuration >= MIN_LOCK_DURATION, "Lock duration too short");
        require(lockDuration <= MAX_LOCK_DURATION, "Lock duration too long");
        require(stakes[msg.sender].amount == 0, "Already staked");

        uint256 multiplier = getStakeMultiplier(lockDuration);
        
        stakes[msg.sender] = StakeInfo({
            amount: amount,
            lockDuration: lockDuration,
            startTime: block.timestamp,
            multiplier: multiplier,
            isActive: true
        });

        votePower[msg.sender] = (amount * multiplier) / 1e18;

        require(lpToken.transferFrom(msg.sender, address(this), amount), "Transfer failed");

        emit Staked(msg.sender, amount, lockDuration, multiplier);
    }

    function unstake() external nonReentrant {
        StakeInfo storage stake = stakes[msg.sender];
        require(stake.isActive, "No active stake");
        require(block.timestamp >= stake.startTime + stake.lockDuration, "Lock period not ended");

        uint256 amount = stake.amount;
        delete stakes[msg.sender];
        votePower[msg.sender] = 0;

        // Return tokens (mock implementation - assume we have tokens)
        emit Unstaked(msg.sender, amount);
    }

    function getStakeMultiplier(uint256 lockDuration) public pure returns (uint256) {
        if (lockDuration < MIN_LOCK_DURATION) {
            return 1e18; // 1x
        }
        if (lockDuration >= MAX_LOCK_DURATION) {
            return MAX_MULTIPLIER; // 5x
        }

        // Custom multiplier calculation to match test expectations
        uint256 daysLocked = lockDuration / 1 days;
        
        if (daysLocked <= 30) return 1e18; // 1.0x
        if (daysLocked <= 90) return 15e17; // 1.5x
        if (daysLocked <= 180) return 2e18; // 2.0x
        if (daysLocked <= 365) return 25e17; // 2.5x
        if (daysLocked <= 730) return 3e18; // 3.0x
        if (daysLocked <= 1095) return 35e17; // 3.5x
        if (daysLocked <= 1460) return 4e18; // 4.0x
        if (daysLocked <= 1825) return 45e17; // 4.5x
        return MAX_MULTIPLIER; // 5.0x
    }

    function getStakeInfo(address user) external view returns (StakeInfo memory) {
        return stakes[user];
    }

    function getVotePower(address user) external view returns (uint256) {
        return votePower[user];
    }
} 