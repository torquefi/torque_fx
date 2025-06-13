// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import { OFTCore } from "@layerzerolabs/oft-evm/contracts/OFTCore.sol";

contract TorqueCHF is ERC20, OFTCore {
    constructor(
        string memory name,
        string memory symbol,
        address lzEndpoint
    ) ERC20(name, symbol) OFTCore(lzEndpoint) {}

    function mint(address to, uint256 amount) external returns (bool) {
        _mint(to, amount);
        return true;
    }

    function burn(uint256 amount) external {
        _burn(msg.sender, amount);
    }
} 