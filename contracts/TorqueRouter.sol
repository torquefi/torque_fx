// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.30;

import "@openzeppelin/contracts/access/Ownable.sol";

contract TorqueRouter is Ownable {
    struct Pair {
        address token0;
        address token1;
        bool active;
    }

    mapping(bytes32 => Pair) public pairs;
    mapping(address => bool) public allowedTokens;

    event PairAdded(bytes32 indexed pairId, address token0, address token1);
    event PairRemoved(bytes32 indexed pairId);
    event TokenAllowed(address indexed token, bool allowed);

    constructor() Ownable(msg.sender) {
    }

    function addPair(
        bytes32 pairId,
        address token0,
        address token1
    ) external onlyOwner {
        require(token0 != token1, "Same token");
        require(allowedTokens[token0] && allowedTokens[token1], "Token not allowed");
        require(!pairs[pairId].active, "Pair exists");

        pairs[pairId] = Pair({
            token0: token0,
            token1: token1,
            active: true
        });

        emit PairAdded(pairId, token0, token1);
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

    function getPair(bytes32 pairId) external view returns (Pair memory) {
        require(pairs[pairId].active, "Pair not found");
        return pairs[pairId];
    }
}
