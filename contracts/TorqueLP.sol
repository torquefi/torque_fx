// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.30;

import "@layerzerolabs/lz-evm-oapp-v2/contracts/oft/OFT.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

contract TorqueLP is OFT {
    address public dex;

    event DEXUpdated(address indexed oldDex, address indexed newDex);

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
        _mint(to, amount);
    }

    function burn(address from, uint256 amount) external {
        require(msg.sender == dex, "Only DEX can burn");
        _burn(from, amount);
    }

    /**
     * @dev Get LP token statistics for frontend
     */
    function getLPStats() external view returns (
        uint256 supply,
        uint256 totalHolders,
        string memory tokenName,
        string memory tokenSymbol
    ) {
        supply = totalSupply();
        tokenName = name();
        tokenSymbol = symbol();
        
        // Note: totalHolders would require additional tracking
        // For now, return 0 as it's not easily calculable without events
        totalHolders = 0;
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
        supply = totalSupply();
        
        if (supply > 0) {
            userShare = (balance * 10000) / supply; // In basis points
        } else {
            userShare = 0;
        }
    }
}
