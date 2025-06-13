// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@layerzerolabs/solidity-examples/contracts/lzApp/NonblockingLzApp.sol";

contract TorqueLP is ERC20, NonblockingLzApp {
    constructor(
        string memory name,
        string memory symbol,
        address _lzEndpoint,
        address _owner
    ) ERC20(name, symbol) NonblockingLzApp(_lzEndpoint) {
        _transferOwnership(_owner);
    }

    function mint(address to, uint256 amount) external onlyOwner {
        _mint(to, amount);
    }

    function burn(address from, uint256 amount) external onlyOwner {
        _burn(from, amount);
    }

    function _nonblockingLzReceive(
        uint16,
        bytes memory,
        uint64,
        bytes memory
    ) internal override {}
}
