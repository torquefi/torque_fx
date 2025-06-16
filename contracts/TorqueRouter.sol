// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";
import "./4337/TorqueAccount.sol";

interface ITorqueAccount {
    function userAccounts(address user, uint256 accountId) external view returns (
        uint256 leverage,
        bool exists,
        bool active,
        string memory username,
        address referrer
    );
    function isValidAccount(address user, uint256 accountId) external view returns (bool);
}

contract TorqueRouter is Ownable {
    struct Pair {
        address token0;
        address token1;
        address priceFeed;
        bool active;
    }

    mapping(bytes32 => Pair) public pairs;
    mapping(address => bool) public allowedTokens;
    mapping(address => bool) public allowedPriceFeeds;

    ITorqueAccount public torqueAccount;

    event PairAdded(bytes32 indexed pairId, address token0, address token1, address priceFeed);
    event PairRemoved(bytes32 indexed pairId);
    event TokenAllowed(address indexed token, bool allowed);
    event PriceFeedAllowed(address indexed feed, bool allowed);

    constructor(address _torqueAccount) {
        torqueAccount = ITorqueAccount(_torqueAccount);
    }

    function addPair(
        bytes32 pairId,
        address token0,
        address token1,
        address priceFeed
    ) external onlyOwner {
        require(token0 != token1, "Same token");
        require(allowedTokens[token0] && allowedTokens[token1], "Token not allowed");
        require(allowedPriceFeeds[priceFeed], "Price feed not allowed");
        require(!pairs[pairId].active, "Pair exists");

        pairs[pairId] = Pair({
            token0: token0,
            token1: token1,
            priceFeed: priceFeed,
            active: true
        });

        emit PairAdded(pairId, token0, token1, priceFeed);
    }

    function removePair(bytes32 pairId) external onlyOwner {
        require(pairs[pairId].active, "Pair not found");
        pairs[pairId].active = false;
        emit PairRemoved(pairId);
    }

    function setTokenAllowed(address token, bool allowed) external onlyOwner {
        allowedTokens[token] = allowed;
        emit TokenAllowed(token, allowed);
    }

    function setPriceFeedAllowed(address feed, bool allowed) external onlyOwner {
        allowedPriceFeeds[feed] = allowed;
        emit PriceFeedAllowed(feed, allowed);
    }

    function getPair(bytes32 pairId) external view returns (Pair memory) {
        require(pairs[pairId].active, "Pair not found");
        return pairs[pairId];
    }

    function getLatestPrice(bytes32 pairId) external view returns (int256) {
        require(pairs[pairId].active, "Pair not found");
        AggregatorV3Interface priceFeed = AggregatorV3Interface(pairs[pairId].priceFeed);
        (, int256 price,,,) = priceFeed.latestRoundData();
        return price;
    }

    function isValidAccount(address user, uint256 accountId) public view returns (bool) {
        (, bool exists, , bool active, , ) = torqueAccount.userAccounts(user, accountId);
        return exists && active;
    }
}
