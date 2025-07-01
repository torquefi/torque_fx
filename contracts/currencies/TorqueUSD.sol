// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import { OFTCore } from "@layerzerolabs/lz-evm-oapp-v2/contracts/oft/OFTCore.sol";

contract TorqueUSD is ERC20, OFTCore {
    constructor(
        string memory name,
        string memory symbol,
        address lzEndpoint
    ) ERC20(name, symbol) OFTCore(18, lzEndpoint, msg.sender) Ownable(msg.sender) {}

    function mint(address to, uint256 amount) external returns (bool) {
        _mint(to, amount);
        return true;
    }

    function burn(uint256 amount) external {
        _burn(msg.sender, amount);
    }

    // OFT implementation
    function _debit(
        address _from,
        uint256 _amountLD,
        uint256 _minAmountLD,
        uint32 _dstEid
    ) internal virtual override returns (uint256 amountSentLD, uint256 amountReceivedLD) {
        amountSentLD = _removeDust(_amountLD);
        amountReceivedLD = amountSentLD;
        
        // Check for slippage
        if (amountReceivedLD < _minAmountLD) {
            revert SlippageExceeded(amountReceivedLD, _minAmountLD);
        }
        
        // Burn tokens from the sender
        _burn(_from, amountSentLD);
    }

    function _credit(
        address _to,
        uint256 _amountLD,
        uint32 _srcEid
    ) internal virtual override returns (uint256 amountReceivedLD) {
        amountReceivedLD = _amountLD;
        _mint(_to, amountReceivedLD);
    }

    function token() external view override returns (address) {
        return address(this);
    }

    function approvalRequired() external pure override returns (bool) {
        return false;
    }
} 