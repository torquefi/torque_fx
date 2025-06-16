// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "@layerzerolabs/lz-evm-oapp-v2/contracts/oft/OFT.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Burnable.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Permit.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Votes.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

contract Torque is ERC20Burnable, ERC20Permit, ERC20Votes, OFT, Ownable {
    event Minted(address indexed to, uint256 amount);
    event Burned(address indexed from, uint256 amount);

    constructor(
        string memory _name,
        string memory _symbol,
        address _lzEndpoint,
        address _owner
    ) 
        OFT(_name, _symbol, _lzEndpoint, _owner)
        ERC20Permit(_name)
        Ownable(_owner)
    {
        uint256 initialSupply = 1_000_000_000 * 10 ** decimals();
        _mint(_owner, initialSupply);
        emit Minted(_owner, initialSupply);
    }

    function _afterTokenTransfer(
        address from,
        address to,
        uint256 amount
    ) internal override(ERC20, ERC20Votes) {
        super._afterTokenTransfer(from, to, amount);
    }

    function _mint(address to, uint256 amount) internal override(ERC20, ERC20Votes, OFT) {
        super._mint(to, amount);
        emit Minted(to, amount);
    }

    function _burn(address account, uint256 amount) internal override(ERC20, ERC20Votes, OFT) {
        super._burn(account, amount);
        emit Burned(account, amount);
    }
}
