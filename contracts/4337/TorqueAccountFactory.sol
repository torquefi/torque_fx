// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.28;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "./TorqueAccount.sol";

contract TorqueAccountFactory is Ownable, ReentrancyGuard {
    TorqueAccount public immutable accountContract;
    IEntryPoint public immutable entryPoint;
    IERC20 public immutable usdc;
    address public guardian;

    event AccountCreated(address indexed user, uint256 accountId, uint256 leverage);
    event GuardianUpdated(address indexed oldGuardian, address indexed newGuardian);

    constructor(
        address _accountContract,
        address _entryPoint,
        address _usdc,
        address _guardian
    ) Ownable(msg.sender) {
        accountContract = TorqueAccount(_accountContract);
        entryPoint = IEntryPoint(_entryPoint);
        usdc = IERC20(_usdc);
        guardian = _guardian;
    }

    function createAccount(
        uint256 leverage,
        string memory username,
        address referrer
    ) external nonReentrant returns (uint256) {
        uint256 accountId = accountContract.createAccount(
            leverage,
            username,
            referrer
        );
        
        emit AccountCreated(msg.sender, accountId, leverage);
        return accountId;
    }

    function batchCreateAccounts(
        uint256[] calldata leverages,
        string[] calldata usernames,
        address[] calldata referrers
    ) external nonReentrant returns (uint256[] memory) {
        require(
            leverages.length == usernames.length &&
            usernames.length == referrers.length,
            "Array lengths mismatch"
        );

        uint256[] memory accountIds = new uint256[](leverages.length);
        
        for (uint256 i = 0; i < leverages.length; i++) {
            accountIds[i] = accountContract.createAccount(
                leverages[i],
                usernames[i],
                referrers[i]
            );
            
            emit AccountCreated(msg.sender, accountIds[i], leverages[i]);
        }

        return accountIds;
    }

    function setGuardian(address _guardian) external onlyOwner {
        address oldGuardian = guardian;
        guardian = _guardian;
        emit GuardianUpdated(oldGuardian, _guardian);
    }

    function getAccountCount(address user) external view returns (uint256) {
        return accountContract.accountCount(user);
    }

    function isValidAccount(address user, uint256 accountId) external view returns (bool) {
        return accountContract.isValidAccount(user, accountId);
    }
} 