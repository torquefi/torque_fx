// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "./TorqueLP.sol";
import "./4337/TorqueAccount.sol";

interface ITorqueAccount {
    function userAccounts(address user, uint256 accountId) external view returns (
        uint256 leverage,
        bool exists,
        bool active,
        string memory username,
        address referrer
    );
    function isValidAccount(address user, uint256 accountId) external view returns (bool);
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

    function getPrice(address baseToken, address quoteToken) external view returns (uint256) {
        require(baseToken == address(token0) || baseToken == address(token1), "Invalid base token");
        require(quoteToken == address(token0) || quoteToken == address(token1), "Invalid quote token");
        require(baseToken != quoteToken, "Same token");

        uint256 balance0 = token0.balanceOf(address(this));
        uint256 balance1 = token1.balanceOf(address(this));

        if (baseToken == address(token0)) {
            return (balance1 * 1e18) / balance0;
        } else {
            return (balance0 * 1e18) / balance1;
        }
    }

    function getAmountOut(
        uint256 amountIn,
        uint256 reserveIn,
        uint256 reserveOut
    ) public pure returns (uint256) {
        require(amountIn > 0, "Insufficient input");
        require(reserveIn > 0 && reserveOut > 0, "Insufficient liquidity");

        uint256 amountInWithFee = amountIn * (10000 - feeBps);
        uint256 numerator = amountInWithFee * reserveOut;
        uint256 denominator = reserveIn * 10000 + amountInWithFee;
        return numerator / denominator;
    }

    function getAmountIn(
        uint256 amountOut,
        uint256 reserveIn,
        uint256 reserveOut
    ) public pure returns (uint256) {
        require(amountOut > 0, "Insufficient output");
        require(reserveIn > 0 && reserveOut > 0, "Insufficient liquidity");

        uint256 numerator = reserveIn * amountOut * 10000;
        uint256 denominator = (reserveOut - amountOut) * (10000 - feeBps);
        return (numerator / denominator) + 1;
    }

    function swap(
        address tokenIn,
        uint256 amountIn,
        uint256 accountId
    ) external returns (uint256 amountOut) {
        // CHECKS
        require(isValidAccount(msg.sender, accountId), "Invalid account");
        require(amountIn > 0, "Invalid input");
        require(tokenIn == address(token0) || tokenIn == address(token1), "Invalid token");

        (IERC20 inToken, IERC20 outToken) = tokenIn == address(token0) ? (token0, token1) : (token1, token0);

        uint256 reserveIn = inToken.balanceOf(address(this));
        uint256 reserveOut = outToken.balanceOf(address(this));

        amountOut = getAmountOut(amountIn, reserveIn, reserveOut);
        require(amountOut > 0, "Insufficient output");

        // EFFECTS
        uint256 fee = 0;
        if (feeBps > 0 && feeRecipient != address(0)) {
            fee = (amountIn * feeBps) / 10000;
        }

        // INTERACTIONS
        inToken.transferFrom(msg.sender, address(this), amountIn);
        outToken.transfer(msg.sender, amountOut);

        if (fee > 0) {
            inToken.transfer(feeRecipient, fee);
        }

        emit SwapExecuted(msg.sender, accountId, address(inToken), amountIn, address(outToken), amountOut);
    }

    function setFee(uint256 _feeBps) external {
        require(msg.sender == feeRecipient, "Not authorized");
        require(_feeBps <= 30, "Max 0.3%");
        feeBps = _feeBps;
    }

    function isValidAccount(address user, uint256 accountId) public view returns (bool) {
        (, bool exists, bool active, , ) = torqueAccount.userAccounts(user, accountId);
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
