// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "./TorqueLP.sol";

contract TorqueDEX {
    IERC20 public token0;
    IERC20 public token1;
    TorqueLP public lpToken;

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
        bool _isStablePair
    ) {
        token0 = IERC20(_token0);
        token1 = IERC20(_token1);
        feeRecipient = _feeRecipient;
        isStablePair = _isStablePair;
        
        // Deploy LP token
        lpToken = new TorqueLP(_name, _symbol);
        lpToken.setDEX(address(this));
    }

    function addLiquidity(
        uint256 amount0,
        uint256 amount1,
        int256 lowerTick,
        int256 upperTick
    ) external returns (uint256 liquidity) {
        // CHECKS
        require(amount0 > 0 && amount1 > 0, "Zero amounts");
        require(lowerTick < upperTick, "Invalid range");

        // EFFECTS
        if (isStablePair) {
            liquidity = _addStableLiquidity(amount0, amount1);
        } else {
            liquidity = _addConcentratedLiquidity(amount0, amount1, lowerTick, upperTick);
        }

        require(liquidity > 0, "Insufficient liquidity minted");
        totalLiquidity += liquidity;

        // Store range information for the user
        userRanges[msg.sender][0].push(Range({
            lowerTick: lowerTick,
            upperTick: upperTick,
            liquidity: liquidity,
            amount0: amount0,
            amount1: amount1
        }));

        // INTERACTIONS
        token0.transferFrom(msg.sender, address(this), amount0);
        token1.transferFrom(msg.sender, address(this), amount1);
        lpToken.mint(msg.sender, liquidity);

        emit LiquidityAdded(msg.sender, 0, amount0, amount1, liquidity);
        emit RangeAdded(msg.sender, 0, lowerTick, upperTick, liquidity);
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

    function removeLiquidity(uint256 liquidity) external returns (uint256 amount0, uint256 amount1) {
        // CHECKS
        require(liquidity > 0, "Zero liquidity");

        // Find the range to remove
        Range[] storage ranges = userRanges[msg.sender][0];
        require(ranges.length > 0, "No ranges found");
        
        Range storage range = ranges[ranges.length - 1];
        amount0 = range.amount0;
        amount1 = range.amount1;

        // EFFECTS
        totalLiquidity -= liquidity;
        ranges.pop();

        // INTERACTIONS
        lpToken.burn(msg.sender, liquidity);
        token0.transfer(msg.sender, amount0);
        token1.transfer(msg.sender, amount1);

        emit LiquidityRemoved(msg.sender, 0, liquidity, amount0, amount1);
        emit RangeRemoved(msg.sender, 0, range.lowerTick, range.upperTick, liquidity);
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
        uint256 amountIn
    ) external returns (uint256 amountOut) {
        // CHECKS
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

        emit SwapExecuted(msg.sender, 0, address(inToken), amountIn, address(outToken), amountOut);
    }

    function setFee(uint256 _feeBps) external {
        // CHECKS
        require(msg.sender == feeRecipient, "Not authorized");
        require(_feeBps <= 30, "Max 0.3%");
        
        // EFFECTS
        feeBps = _feeBps;
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
