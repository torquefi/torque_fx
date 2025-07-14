// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.28;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@chainlink/contracts/src/v0.8/shared/interfaces/AggregatorV3Interface.sol";

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



    event PairAdded(bytes32 indexed pairId, address token0, address token1, address priceFeed);
    event PairRemoved(bytes32 indexed pairId);
    event TokenAllowed(address indexed token, bool allowed);
    event PriceFeedAllowed(address indexed feed, bool allowed);

    constructor() Ownable(msg.sender) {
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
        require(token != address(0), "Invalid token");
        allowedTokens[token] = allowed;
        emit TokenAllowed(token, allowed);
    }

    function setPriceFeedAllowed(address feed, bool allowed) external onlyOwner {
        require(feed != address(0), "Invalid feed");
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
}
