// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "@layerzerolabs/lz-evm-oapp-v2/contracts/oft/OFT.sol";

contract TorqueLP is OFT {
    address public dex;

    event DEXUpdated(address indexed oldDex, address indexed newDex);

    constructor(
        string memory _name,
        string memory _symbol,
        address _lzEndpoint,
        address _owner
    ) OFT(_name, _symbol, _lzEndpoint, _owner) {}

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
}
