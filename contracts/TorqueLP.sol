// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.30;

import "@layerzerolabs/lz-evm-oapp-v2/contracts/oft/OFT.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

contract TorqueLP is OFT {
    address public dex;

    event DEXUpdated(address indexed oldDex, address indexed newDex);

    // Events for tracking supply changes
    event SupplyMinted(address indexed to, uint256 amount, uint256 newTotalSupply);
    event SupplyBurned(address indexed from, uint256 amount, uint256 newTotalSupply);
    
    // Internal tracking of total supply
    uint256 private _totalSupply;

    constructor(
        string memory _name,
        string memory _symbol,
        address _lzEndpoint,
        address _owner
    ) OFT(_name, _symbol, _lzEndpoint, _owner) Ownable(_owner) {}

    function setDEX(address _dex) external onlyOwner {
        require(_dex != address(0), "Invalid DEX address");
        address oldDex = dex;
        dex = _dex;
        emit DEXUpdated(oldDex, _dex);
    }

    function mint(address to, uint256 amount) external {
        require(msg.sender == dex, "Only DEX can mint");
        super._mint(to, amount);
        _totalSupply += amount;
        emit SupplyMinted(to, amount, _totalSupply);
    }

    function burn(address from, uint256 amount) external {
        require(msg.sender == dex, "Only DEX can burn");
        super._burn(from, amount);
        _totalSupply -= amount;
        emit SupplyBurned(from, amount, _totalSupply);
    }

    /**
     * @dev Get LP token statistics for frontend
     */
    function getLPStats() external view returns (
        uint256 supply,
        string memory tokenName,
        string memory tokenSymbol
    ) {
        supply = _totalSupply;
        tokenName = name();
        tokenSymbol = symbol();
    }

    /**
     * @dev Get user's LP token information
     */
    function getUserLPInfo(address user) external view returns (
        uint256 balance,
        uint256 supply,
        uint256 userShare
    ) {
        balance = balanceOf(user);
        supply = _totalSupply;
        
        if (supply > 0) {
            userShare = (balance * 10000) / supply; // In basis points
        } else {
            userShare = 0;
        }
    }

    /**
     * @dev Override totalSupply to use our tracked value
     */
    function totalSupply() public view override returns (uint256) {
        return _totalSupply;
    }

    /**
     * @dev Get total supply from events (for historical tracking)
     * This function can be used to verify our tracked supply against events
     */
    function getTotalSupplyFromEvents() external view returns (uint256) {
        // This would require querying events from the blockchain
        // For now, return our tracked value
        return _totalSupply;
    }

    /**
     * @dev Get cross-chain supply information
     */
    function getCrossChainSupplyInfo() external view returns (
        uint256 localSupply,
        uint256 crossChainTotalSupply,
        bool isCrossChainEnabled
    ) {
        localSupply = _totalSupply;
        crossChainTotalSupply = _totalSupply; // For now, same as local. Could be enhanced for cross-chain tracking
        isCrossChainEnabled = true; // OFT enables cross-chain functionality
    }
}
