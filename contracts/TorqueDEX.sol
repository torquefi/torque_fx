// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "./4337/TorqueAccount.sol";
import "./TorqueLP.sol";

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

    // Concentrated liquidity parameters
    struct Tick {
        uint256 liquidityNet;
        uint256 liquidityGross;
        int256 tickIdx;
        uint256 sqrtPriceX96;
    }

    struct Range {
        int256 lowerTick;
        int256 upperTick;
        uint256 liquidity;
        uint256 amount0;
        uint256 amount1;
    }

    // Stable pair parameters
    uint256 public constant A = 1000; // Amplification coefficient
    uint256 public constant PRECISION = 1e18;
    bool public isStablePair;

    mapping(int256 => Tick) public ticks;
    mapping(address => mapping(uint256 => Range[])) public userRanges;
    int256 public currentTick;
    uint256 public currentSqrtPriceX96;

    event LiquidityAdded(address indexed user, uint256 accountId, uint256 amount0, uint256 amount1, uint256 liquidity);
    event LiquidityRemoved(address indexed user, uint256 accountId, uint256 liquidity, uint256 amount0, uint256 amount1);
    event SwapExecuted(address indexed user, uint256 accountId, address tokenIn, uint256 amountIn, address tokenOut, uint256 amountOut);
    event RangeAdded(address indexed user, uint256 accountId, int256 lowerTick, int256 upperTick, uint256 liquidity);
    event RangeRemoved(address indexed user, uint256 accountId, int256 lowerTick, int256 upperTick, uint256 liquidity);

    constructor(
        address _token0,
        address _token1,
        string memory _name,
        string memory _symbol,
        address _feeRecipient,
        address _torqueAccount,
        bool _isStablePair
    ) {
        token0 = IERC20(_token0);
        token1 = IERC20(_token1);
        feeRecipient = _feeRecipient;
        torqueAccount = ITorqueAccount(_torqueAccount);
        isStablePair = _isStablePair;
        
        // Deploy LP token
        lpToken = new TorqueLP(_name, _symbol);
        lpToken.setDEX(address(this));
    }

    function addLiquidity(
        uint256 amount0,
        uint256 amount1,
        uint256 accountId,
        int256 lowerTick,
        int256 upperTick
    ) external returns (uint256 liquidity) {
        require(isValidAccount(msg.sender, accountId), "Invalid account");
        require(amount0 > 0 && amount1 > 0, "Zero amounts");
        require(lowerTick < upperTick, "Invalid range");

        // Transfer tokens from user
        token0.transferFrom(msg.sender, address(this), amount0);
        token1.transferFrom(msg.sender, address(this), amount1);

        if (isStablePair) {
            liquidity = _addStableLiquidity(amount0, amount1);
        } else {
            liquidity = _addConcentratedLiquidity(amount0, amount1, lowerTick, upperTick);
        }

        require(liquidity > 0, "Insufficient liquidity minted");
        totalLiquidity += liquidity;

        // Mint LP tokens to user
        lpToken.mint(msg.sender, liquidity);

        // Store range information
        userRanges[msg.sender][accountId].push(Range({
            lowerTick: lowerTick,
            upperTick: upperTick,
            liquidity: liquidity,
            amount0: amount0,
            amount1: amount1
        }));

        emit LiquidityAdded(msg.sender, accountId, amount0, amount1, liquidity);
        emit RangeAdded(msg.sender, accountId, lowerTick, upperTick, liquidity);
    }

    function _addStableLiquidity(uint256 amount0, uint256 amount1) internal returns (uint256) {
        uint256 balance0 = token0.balanceOf(address(this));
        uint256 balance1 = token1.balanceOf(address(this));

        if (totalSupply() == 0) {
            return sqrt(amount0 * amount1);
        }

        uint256 supply = totalSupply();
        uint256 d0 = balance0 - amount0;
        uint256 d1 = balance1 - amount1;

        // Stable pair invariant: (x + y) * (x + y) = k
        uint256 k = (d0 + d1) * (d0 + d1);
        uint256 newK = (balance0 + balance1) * (balance0 + balance1);
        
        return (supply * (newK - k)) / k;
    }

    function _addConcentratedLiquidity(
        uint256 amount0,
        uint256 amount1,
        int256 lowerTick,
        int256 upperTick
    ) internal returns (uint256) {
        uint256 sqrtPriceLower = _getSqrtPriceAtTick(lowerTick);
        uint256 sqrtPriceUpper = _getSqrtPriceAtTick(upperTick);
        uint256 currentSqrtPrice = currentSqrtPriceX96;

        uint256 liquidity;
        if (currentSqrtPrice <= sqrtPriceLower) {
            liquidity = _getLiquidityForAmount0(amount0, sqrtPriceLower, sqrtPriceUpper);
        } else if (currentSqrtPrice >= sqrtPriceUpper) {
            liquidity = _getLiquidityForAmount1(amount1, sqrtPriceLower, sqrtPriceUpper);
        } else {
            uint256 liquidity0 = _getLiquidityForAmount0(amount0, currentSqrtPrice, sqrtPriceUpper);
            uint256 liquidity1 = _getLiquidityForAmount1(amount1, sqrtPriceLower, currentSqrtPrice);
            liquidity = liquidity0 < liquidity1 ? liquidity0 : liquidity1;
        }

        _updateTicks(lowerTick, upperTick, liquidity, true);
        return liquidity;
    }

    function _getSqrtPriceAtTick(int256 tick) internal pure returns (uint256) {
        return uint256(1.0001 ** uint256(tick)) * PRECISION;
    }

    function _getLiquidityForAmount0(
        uint256 amount0,
        uint256 sqrtPriceA,
        uint256 sqrtPriceB
    ) internal pure returns (uint256) {
        return (amount0 * (sqrtPriceA * sqrtPriceB)) / (sqrtPriceB - sqrtPriceA);
    }

    function _getLiquidityForAmount1(
        uint256 amount1,
        uint256 sqrtPriceA,
        uint256 sqrtPriceB
    ) internal pure returns (uint256) {
        return (amount1 * PRECISION) / (sqrtPriceB - sqrtPriceA);
    }

    function _updateTicks(
        int256 lowerTick,
        int256 upperTick,
        uint256 liquidity,
        bool isAdd
    ) internal {
        if (isAdd) {
            ticks[lowerTick].liquidityNet += int256(liquidity);
            ticks[upperTick].liquidityNet -= int256(liquidity);
        } else {
            ticks[lowerTick].liquidityNet -= int256(liquidity);
            ticks[upperTick].liquidityNet += int256(liquidity);
        }
    }

    function getPrice(address baseToken, address quoteToken) external view returns (uint256) {
        require(baseToken == address(token0) || baseToken == address(token1), "Invalid base token");
        require(quoteToken == address(token0) || quoteToken == address(token1), "Invalid quote token");
        require(baseToken != quoteToken, "Same token");

        if (isStablePair) {
            return _getStablePrice(baseToken, quoteToken);
        }

        uint256 balance0 = token0.balanceOf(address(this));
        uint256 balance1 = token1.balanceOf(address(this));

        if (baseToken == address(token0)) {
            return (balance1 * PRECISION) / balance0;
        } else {
            return (balance0 * PRECISION) / balance1;
        }
    }

    function _getStablePrice(address baseToken, address quoteToken) internal view returns (uint256) {
        uint256 balance0 = token0.balanceOf(address(this));
        uint256 balance1 = token1.balanceOf(address(this));

        // Stable pair price calculation with amplification
        uint256 sum = balance0 + balance1;
        uint256 product = balance0 * balance1;
        
        if (baseToken == address(token0)) {
            return (balance1 * PRECISION * A) / (sum + (product * A) / PRECISION);
        } else {
            return (balance0 * PRECISION * A) / (sum + (product * A) / PRECISION);
        }
    }

    function removeLiquidity(uint256 liquidity, uint256 accountId) external returns (uint256 amount0, uint256 amount1) {
        require(isValidAccount(msg.sender, accountId), "Invalid account");
        require(liquidity > 0, "Zero liquidity");

        // Find the range to remove
        Range[] storage ranges = userRanges[msg.sender][accountId];
        require(ranges.length > 0, "No ranges found");
        
        Range storage range = ranges[ranges.length - 1];
        amount0 = range.amount0;
        amount1 = range.amount1;

        // Burn LP tokens
        lpToken.burn(msg.sender, liquidity);

        // Transfer tokens back to user
        token0.transfer(msg.sender, amount0);
        token1.transfer(msg.sender, amount1);

        // Update state
        totalLiquidity -= liquidity;
        ranges.pop();

        emit LiquidityRemoved(msg.sender, accountId, liquidity, amount0, amount1);
        emit RangeRemoved(msg.sender, accountId, range.lowerTick, range.upperTick, liquidity);
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
