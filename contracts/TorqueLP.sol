// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.30;

import "@layerzerolabs/lz-evm-oapp-v2/contracts/oft/OFT.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

contract TorqueLP is OFT {
    address public dex;

    event DEXUpdated(address indexed oldDex, address indexed newDex);
    event SupplyMinted(address indexed to, uint256 amount, uint256 newTotalSupply);
    event SupplyBurned(address indexed from, uint256 amount, uint256 newTotalSupply);
    
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

    function getLPStats() external view returns (
        uint256 supply,
        string memory tokenName,
        string memory tokenSymbol
    ) {
        supply = _totalSupply;
        tokenName = name();
        tokenSymbol = symbol();
    }

    function getUserLPInfo(address user) external view returns (
        uint256 balance,
        uint256 supply,
        uint256 userShare
    ) {
        balance = balanceOf(user);
        supply = _totalSupply;
        
        if (supply > 0) {
            userShare = (balance * 10000) / supply;
        } else {
            userShare = 0;
        }
    }

    function totalSupply() public view override returns (uint256) {
        return _totalSupply;
    }
}
