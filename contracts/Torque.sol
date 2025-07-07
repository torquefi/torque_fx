// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.28;

import "@layerzerolabs/lz-evm-oapp-v2/contracts/oft/OFT.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Burnable.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Permit.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Votes.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/Nonces.sol";

contract Torque is ERC20Burnable, ERC20Permit, ERC20Votes, OFT {
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

    function _update(address from, address to, uint256 value) internal virtual override(ERC20, ERC20Votes) {
        super._update(from, to, value);
    }

    function nonces(address owner) public view virtual override(ERC20Permit, Nonces) returns (uint256) {
        return super.nonces(owner);
    }
}
