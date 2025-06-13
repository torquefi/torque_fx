// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "@chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";

contract MockPriceFeed is AggregatorV3Interface {
    uint8 private _decimals;
    int256 private _price;
    uint80 private _roundId;
    uint256 private _timestamp;
    uint80 private _answeredInRound;

    constructor() {
        _decimals = 8;
        _price = 2000 * 10**8; // $2000
        _roundId = 1;
        _timestamp = block.timestamp;
        _answeredInRound = 1;
    }

    function setPrice(int256 price) external {
        _price = price;
        _roundId++;
        _timestamp = block.timestamp;
        _answeredInRound = _roundId;
    }

    function decimals() external view override returns (uint8) {
        return _decimals;
    }

    function description() external pure override returns (string memory) {
        return "Mock Price Feed";
    }

    function version() external pure override returns (uint256) {
        return 1;
    }

    function getRoundData(uint80 _id)
        external
        view
        override
        returns (
            uint80 roundId,
            int256 answer,
            uint256 startedAt,
            uint256 updatedAt,
            uint80 answeredInRound
        )
    {
        return (_id, _price, _timestamp, _timestamp, _answeredInRound);
    }

    function latestRoundData()
        external
        view
        override
        returns (
            uint80 roundId,
            int256 answer,
            uint256 startedAt,
            uint256 updatedAt,
            uint80 answeredInRound
        )
    {
        return (_roundId, _price, _timestamp, _timestamp, _answeredInRound);
    }
} 