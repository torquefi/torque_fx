// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "./TorqueAccount.sol";

contract TorqueAccountUpgrade is Ownable, ReentrancyGuard {
    TorqueAccount public immutable accountContract;
    address public guardian;
    uint256 public constant UPGRADE_DELAY = 1 days;
    uint256 public constant UPGRADE_WINDOW = 1 days;

    struct UpgradeRequest {
        uint256 newLeverage;
        uint256 timestamp;
        uint256 nonce;
    }

    struct UpgradeOperation {
        uint256 accountId;
        uint256 newLeverage;
    }

    mapping(address => mapping(uint256 => UpgradeRequest)) public upgradeRequests;
    mapping(address => bool) public isGuardian;
    mapping(address => uint256) public nonces;

    event UpgradeRequested(address indexed user, uint256 accountId, uint256 newLeverage, uint256 nonce);
    event UpgradeExecuted(address indexed user, uint256 accountId, uint256 newLeverage);
    event GuardianAdded(address indexed guardian);
    event GuardianRemoved(address indexed guardian);

    modifier onlyGuardian() {
        require(isGuardian[msg.sender], "Not guardian");
        _;
    }

    constructor(
        address _accountContract,
        address _guardian
    ) {
        accountContract = TorqueAccount(_accountContract);
        guardian = _guardian;
        isGuardian[_guardian] = true;
    }

    function requestUpgrade(
        uint256 accountId,
        uint256 newLeverage
    ) external nonReentrant {
        require(accountContract.isValidAccount(msg.sender, accountId), "Invalid account");
        require(newLeverage >= 100 && newLeverage <= 10000, "Invalid leverage");

        uint256 nonce = nonces[msg.sender]++;
        upgradeRequests[msg.sender][accountId] = UpgradeRequest({
            newLeverage: newLeverage,
            timestamp: block.timestamp,
            nonce: nonce
        });

        emit UpgradeRequested(msg.sender, accountId, newLeverage, nonce);
    }

    function executeUpgrade(
        address user,
        uint256 accountId,
        uint256 newLeverage,
        uint256 nonce
    ) external onlyGuardian {
        UpgradeRequest storage request = upgradeRequests[user][accountId];
        require(request.nonce == nonce, "Invalid nonce");
        require(block.timestamp >= request.timestamp + UPGRADE_DELAY, "Too early");
        require(block.timestamp <= request.timestamp + UPGRADE_WINDOW, "Too late");

        accountContract.updateLeverage(accountId, newLeverage);
        delete upgradeRequests[user][accountId];

        emit UpgradeExecuted(user, accountId, newLeverage);
    }

    function batchExecuteUpgrades(
        UpgradeOperation[] calldata operations
    ) external onlyGuardian {
        for (uint256 i = 0; i < operations.length; i++) {
            UpgradeOperation calldata op = operations[i];
            accountContract.updateLeverage(op.accountId, op.newLeverage);
            emit UpgradeExecuted(msg.sender, op.accountId, op.newLeverage);
        }
    }

    function addGuardian(address _guardian) external onlyOwner {
        require(!isGuardian[_guardian], "Already guardian");
        isGuardian[_guardian] = true;
        emit GuardianAdded(_guardian);
    }

    function removeGuardian(address _guardian) external onlyOwner {
        require(isGuardian[_guardian], "Not guardian");
        require(_guardian != guardian, "Cannot remove primary guardian");
        isGuardian[_guardian] = false;
        emit GuardianRemoved(_guardian);
    }

    function setPrimaryGuardian(address _guardian) external onlyOwner {
        require(isGuardian[_guardian], "Not guardian");
        guardian = _guardian;
    }
} 