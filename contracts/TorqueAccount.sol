// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "@openzeppelin/contracts/access/Ownable.sol";

contract TorqueAccount is Ownable {
    struct Account {
        uint256 leverage;
        bool exists;
        bool isDemo;
        bool active;
        string username;
        address referrer;
    }

    mapping(address => mapping(uint256 => Account)) public userAccounts;
    mapping(address => uint256) public accountCount;
    mapping(string => bool) public usernames;
    mapping(address => uint256) public referralCount;
    mapping(address => uint256) public referralVolume;

    uint256 public constant MAX_ACCOUNTS = 5;
    uint256 public constant MIN_LEVERAGE = 100;
    uint256 public constant MAX_LEVERAGE = 10000;
    uint256 public constant MAX_USERNAME_LENGTH = 32;

    event AccountCreated(address indexed user, uint256 accountId, uint256 leverage, bool isDemo, string username, address referrer);
    event AccountUpdated(address indexed user, uint256 accountId, uint256 leverage);
    event AccountDisabled(address indexed user, uint256 accountId);
    event UsernameChanged(address indexed user, uint256 accountId, string newUsername);
    event ReferralAdded(address indexed user, address indexed referrer);

    function createAccount(
        uint256 leverage,
        bool isDemo,
        string memory username,
        address referrer
    ) external returns (uint256) {
        require(accountCount[msg.sender] < MAX_ACCOUNTS, "Max accounts reached");
        require(leverage >= MIN_LEVERAGE && leverage <= MAX_LEVERAGE, "Invalid leverage");
        require(bytes(username).length <= MAX_USERNAME_LENGTH, "Username too long");
        require(!usernames[username], "Username taken");
        require(referrer != msg.sender, "Self referral");

        uint256 accountId = accountCount[msg.sender];
        userAccounts[msg.sender][accountId] = Account({
            leverage: leverage,
            exists: true,
            isDemo: isDemo,
            active: true,
            username: username,
            referrer: referrer
        });

        usernames[username] = true;
        accountCount[msg.sender]++;

        if (referrer != address(0)) {
            referralCount[referrer]++;
            emit ReferralAdded(msg.sender, referrer);
        }

        emit AccountCreated(msg.sender, accountId, leverage, isDemo, username, referrer);
        return accountId;
    }

    function updateLeverage(uint256 accountId, uint256 newLeverage) external {
        require(newLeverage >= MIN_LEVERAGE && newLeverage <= MAX_LEVERAGE, "Invalid leverage");
        Account storage account = userAccounts[msg.sender][accountId];
        require(account.exists && account.active, "Invalid account");
        account.leverage = newLeverage;
        emit AccountUpdated(msg.sender, accountId, newLeverage);
    }

    function disableAccount(uint256 accountId) external {
        Account storage account = userAccounts[msg.sender][accountId];
        require(account.exists && account.active, "Invalid account");
        account.active = false;
        emit AccountDisabled(msg.sender, accountId);
    }

    function changeUsername(uint256 accountId, string memory newUsername) external {
        require(bytes(newUsername).length <= MAX_USERNAME_LENGTH, "Username too long");
        require(!usernames[newUsername], "Username taken");
        Account storage account = userAccounts[msg.sender][accountId];
        require(account.exists && account.active, "Invalid account");

        usernames[account.username] = false;
        usernames[newUsername] = true;
        account.username = newUsername;

        emit UsernameChanged(msg.sender, accountId, newUsername);
    }

    function getLeverage(address user, uint256 accountId) external view returns (uint256) {
        Account storage account = userAccounts[user][accountId];
        require(account.exists && account.active, "Invalid account");
        return account.leverage;
    }

    function isValidAccount(address user, uint256 accountId) external view returns (bool) {
        Account storage account = userAccounts[user][accountId];
        return account.exists && account.active;
    }

    function getReferralStats(address user) external view returns (uint256 count, uint256 volume) {
        return (referralCount[user], referralVolume[user]);
    }
}
