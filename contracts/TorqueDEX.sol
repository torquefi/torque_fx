// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "./TorqueLP.sol";

interface ITorqueAccount {
    function userAccounts(address user, uint256 accountId)
        external
        view
        returns (
            uint256 leverage,
            bool exists,
            bool isDemo,
            bool active,
            string memory username,
            address referrer
        );
}

contract TorqueDEX {
    IERC20 public token0;
    IERC20 public token1;
    TorqueLP public lpToken;

    ITorqueAccount public torqueAccount;

    uint256 public totalLiquidity;
    uint256 public feeBps = 4;
    address public feeRecipient;

    event LiquidityAdded(address indexed user, uint256 accountId, uint256 amount0, uint256 amount1, uint256 liquidity);
    event LiquidityRemoved(address indexed user, uint256 accountId, uint256 liquidity, uint256 amount0, uint256 amount1);
    event SwapExecuted(address indexed user, uint256 accountId, address tokenIn, uint256 amountIn, address tokenOut, uint256 amountOut);

    constructor(
        address _token0,
        address _token1,
        string memory _name,
        string memory _symbol,
        address _feeRecipient,
        address _lzEndpoint,
        address _torqueAccount
    ) {
        token0 = IERC20(_token0);
        token1 = IERC20(_token1);
        feeRecipient = _feeRecipient;
        torqueAccount = ITorqueAccount(_torqueAccount);
        lpToken = new TorqueLP(_name, _symbol, _lzEndpoint, address(this));
    }

    function addLiquidity(uint256 amount0, uint256 amount1, uint256 accountId) external returns (uint256 liquidity) {
        require(isValidAccount(msg.sender, accountId), "Invalid account");
        require(amount0 > 0 && amount1 > 0, "Zero amounts");

        token0.transferFrom(msg.sender, address(this), amount0);
        token1.transferFrom(msg.sender, address(this), amount1);

        uint256 balance0 = token0.balanceOf(address(this));
        uint256 balance1 = token1.balanceOf(address(this));

        if (lpToken.totalSupply() == 0) {
            liquidity = sqrt(amount0 * amount1);
        } else {
            uint256 supply = lpToken.totalSupply();
            liquidity = min((amount0 * supply) / (balance0 - amount0), (amount1 * supply) / (balance1 - amount1));
        }

        require(liquidity > 0, "Insufficient liquidity minted");
        lpToken.mint(msg.sender, liquidity);
        totalLiquidity += liquidity;

        emit LiquidityAdded(msg.sender, accountId, amount0, amount1, liquidity);
    }

    function removeLiquidity(uint256 liquidity, uint256 accountId) external returns (uint256 amount0, uint256 amount1) {
        require(isValidAccount(msg.sender, accountId), "Invalid account");
        require(liquidity > 0, "Zero liquidity");

        uint256 balance0 = token0.balanceOf(address(this));
        uint256 balance1 = token1.balanceOf(address(this));
        uint256 totalSupply = lpToken.totalSupply();

        amount0 = (liquidity * balance0) / totalSupply;
        amount1 = (liquidity * balance1) / totalSupply;

        lpToken.burn(msg.sender, liquidity);
        totalLiquidity -= liquidity;

        token0.transfer(msg.sender, amount0);
        token1.transfer(msg.sender, amount1);

        emit LiquidityRemoved(msg.sender, accountId, liquidity, amount0, amount1);
    }

    function swap(address inputToken, uint256 inputAmount, uint256 accountId) external returns (uint256 outputAmount) {
        require(isValidAccount(msg.sender, accountId), "Invalid account");
        require(inputAmount > 0, "Invalid input");
        require(inputToken == address(token0) || inputToken == address(token1), "Invalid token");

        (IERC20 inToken, IERC20 outToken) = inputToken == address(token0) ? (token0, token1) : (token1, token0);

        inToken.transferFrom(msg.sender, address(this), inputAmount);
        uint256 inputBalance = inToken.balanceOf(address(this));
        uint256 outputBalance = outToken.balanceOf(address(this));

        uint256 inputAmountWithFee = (inputAmount * (10000 - feeBps)) / 10000;

        uint256 numerator = inputAmountWithFee * outputBalance;
        uint256 denominator = inputBalance + inputAmountWithFee;
        outputAmount = outputBalance - (numerator / denominator);

        require(outputAmount > 0, "Insufficient output");

        outToken.transfer(msg.sender, outputAmount);

        if (feeBps > 0 && feeRecipient != address(0)) {
            uint256 fee = (inputAmount * feeBps) / 10000;
            inToken.transfer(feeRecipient, fee);
        }

        emit SwapExecuted(msg.sender, accountId, address(inToken), inputAmount, address(outToken), outputAmount);
    }

    function setFee(uint256 _feeBps) external {
        require(msg.sender == feeRecipient, "Not authorized");
        require(_feeBps <= 30, "Max 0.3%");
        feeBps = _feeBps;
    }

    function isValidAccount(address user, uint256 accountId) public view returns (bool) {
        (, bool exists, , bool active, , ) = torqueAccount.userAccounts(user, accountId);
        return exists && active;
    }

    function sqrt(uint256 y) internal pure returns (uint256 z) {
        if (y > 3) {
            z = y;
            uint256 x = y / 2 + 1;
            while (x < z) {
                z = x;
                x = (y / x + x) / 2;
            }
        } else if (y != 0) {
            z = 1;
        }
    }

    function min(uint256 a, uint256 b) internal pure returns (uint256) {
        return a < b ? a : b;
    }
}
