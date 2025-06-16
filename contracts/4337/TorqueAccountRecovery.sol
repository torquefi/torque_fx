// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import "./TorqueAccount.sol";

contract TorqueAccountRecovery is Ownable, ReentrancyGuard {
    using ECDSA for bytes32;

    TorqueAccount public immutable accountContract;
    address public guardian;
    uint256 public constant RECOVERY_DELAY = 7 days;
    uint256 public constant RECOVERY_WINDOW = 2 days;

    struct RecoveryRequest {
        address newOwner;
        uint256 timestamp;
        bool executed;
    }

    mapping(address => mapping(uint256 => RecoveryRequest)) public recoveryRequests;
    mapping(address => bool) public isGuardian;

    event RecoveryRequested(
        address indexed oldOwner,
        address indexed newOwner,
        uint256 indexed accountId,
        uint256 timestamp
    );
    event RecoveryExecuted(
        address indexed oldOwner,
        address indexed newOwner,
        uint256 indexed accountId
    );
    event GuardianAdded(address indexed guardian);
    event GuardianRemoved(address indexed guardian);

    modifier onlyGuardian() {
        require(isGuardian[msg.sender], "Not guardian");
        _;
    }

    constructor(address _accountContract, address _guardian) {
        accountContract = TorqueAccount(_accountContract);
        guardian = _guardian;
        isGuardian[_guardian] = true;
    }

    function requestRecovery(
        address oldOwner,
        address newOwner,
        uint256 accountId,
        bytes memory signature
    ) external onlyGuardian {
        require(accountContract.isValidAccount(oldOwner, accountId), "Invalid account");
        require(recoveryRequests[oldOwner][accountId].timestamp == 0, "Recovery already requested");

        bytes32 messageHash = keccak256(
            abi.encodePacked(
                "Recover account",
                oldOwner,
                newOwner,
                accountId,
                block.chainid
            )
        );
        bytes32 ethSignedMessageHash = messageHash.toEthSignedMessageHash();
        address signer = ethSignedMessageHash.recover(signature);
        require(signer == oldOwner, "Invalid signature");

        recoveryRequests[oldOwner][accountId] = RecoveryRequest({
            newOwner: newOwner,
            timestamp: block.timestamp,
            executed: false
        });

        emit RecoveryRequested(oldOwner, newOwner, accountId, block.timestamp);
    }

    function executeRecovery(address oldOwner, uint256 accountId) external nonReentrant {
        RecoveryRequest storage request = recoveryRequests[oldOwner][accountId];
        require(request.timestamp > 0, "No recovery requested");
        require(!request.executed, "Recovery already executed");
        require(
            block.timestamp >= request.timestamp + RECOVERY_DELAY &&
            block.timestamp <= request.timestamp + RECOVERY_DELAY + RECOVERY_WINDOW,
            "Outside recovery window"
        );

        request.executed = true;
        accountContract.recoverAccount(oldOwner, request.newOwner, accountId);

        emit RecoveryExecuted(oldOwner, request.newOwner, accountId);
    }

    function cancelRecovery(uint256 accountId) external {
        RecoveryRequest storage request = recoveryRequests[msg.sender][accountId];
        require(request.timestamp > 0, "No recovery requested");
        require(!request.executed, "Recovery already executed");
        require(
            block.timestamp < request.timestamp + RECOVERY_DELAY,
            "Recovery window started"
        );

        delete recoveryRequests[msg.sender][accountId];
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