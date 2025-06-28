// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@layerzerolabs/lz-evm-oapp-v2/contracts/oapp/OApp.sol";
import "./TorqueLP.sol";

contract TorqueDEX is OApp, Ownable, ReentrancyGuard {
    IERC20 public token0;
    IERC20 public token1;
    TorqueLP public lpToken;

    uint256 public totalLiquidity;
    uint256 public feeBps = 4;
    address public feeRecipient;

    // Cross-chain liquidity tracking
    mapping(uint16 => mapping(address => uint256)) public crossChainLiquidity; // chainId => user => liquidity
    mapping(uint16 => bool) public supportedChainIds;
    mapping(uint16 => address) public dexAddresses; // chainId => DEX address on that chain
    
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

    // Cross-chain liquidity request
    struct CrossChainLiquidityRequest {
        address user;
        uint256 amount0;
        uint256 amount1;
        int256 lowerTick;
        int256 upperTick;
        uint16 sourceChainId;
        bool isAdd; // true for add, false for remove
    }

    // Stable pair parameters
    uint256 public constant A = 1000; // Amplification coefficient
    uint256 public constant PRECISION = 1e18;
    bool public isStablePair;

    mapping(int256 => Tick) public ticks;
    mapping(address => mapping(uint256 => Range[])) public userRanges;
    int256 public currentTick;
    uint256 public currentSqrtPriceX96;

    // Events
    event LiquidityAdded(address indexed user, uint256 accountId, uint256 amount0, uint256 amount1, uint256 liquidity);
    event LiquidityRemoved(address indexed user, uint256 accountId, uint256 liquidity, uint256 amount0, uint256 amount1);
    event SwapExecuted(address indexed user, uint256 accountId, address tokenIn, uint256 amountIn, address tokenOut, uint256 amountOut);
    event RangeAdded(address indexed user, uint256 accountId, int256 lowerTick, int256 upperTick, uint256 liquidity);
    event RangeRemoved(address indexed user, uint256 accountId, int256 lowerTick, int256 upperTick, uint256 liquidity);
    
    // Cross-chain events
    event CrossChainLiquidityRequested(
        address indexed user,
        uint16 indexed dstChainId,
        uint256 amount0,
        uint256 amount1,
        int256 lowerTick,
        int256 upperTick,
        bool isAdd
    );
    event CrossChainLiquidityCompleted(
        address indexed user,
        uint16 indexed srcChainId,
        uint256 liquidity,
        uint256 amount0,
        uint256 amount1,
        bool isAdd
    );
    event CrossChainLiquidityFailed(
        address indexed user,
        uint16 indexed srcChainId,
        string reason
    );

    // Errors
    error TorqueDEX__UnsupportedChain();
    error TorqueDEX__InvalidDEXAddress();
    error TorqueDEX__CrossChainLiquidityFailed();

    constructor(
        address _token0,
        address _token1,
        string memory _name,
        string memory _symbol,
        address _feeRecipient,
        bool _isStablePair,
        address _lzEndpoint,
        address _owner
    ) OApp(_lzEndpoint, _owner) Ownable(_owner) {
        token0 = IERC20(_token0);
        token1 = IERC20(_token1);
        feeRecipient = _feeRecipient;
        isStablePair = _isStablePair;
        
        // Deploy LP token as OFT
        lpToken = new TorqueLP(_name, _symbol, _lzEndpoint, _owner);
        lpToken.setDEX(address(this));
        
        // Initialize supported chains (same as TorqueBatchMinter)
        _initializeSupportedChains();
    }

    function _initializeSupportedChains() internal {
        supportedChainIds[1] = true;      // Ethereum
        supportedChainIds[42161] = true;  // Arbitrum
        supportedChainIds[10] = true;     // Optimism
        supportedChainIds[137] = true;    // Polygon
        supportedChainIds[8453] = true;   // Base
        supportedChainIds[146] = true;    // Sonic
        supportedChainIds[2741] = true;   // Abstract
        supportedChainIds[56] = true;     // BSC
        supportedChainIds[999] = true;    // HyperEVM
        supportedChainIds[252] = true;    // Fraxtal
        supportedChainIds[43114] = true;  // Avalanche
    }

    /**
     * @dev Add liquidity to multiple chains in a single transaction
     */
    function addCrossChainLiquidity(
        uint16[] calldata dstChainIds,
        uint256[] calldata amounts0,
        uint256[] calldata amounts1,
        int256[] calldata lowerTicks,
        int256[] calldata upperTicks,
        bytes[] calldata adapterParams
    ) external nonReentrant {
        require(
            dstChainIds.length == amounts0.length &&
            dstChainIds.length == amounts1.length &&
            dstChainIds.length == lowerTicks.length &&
            dstChainIds.length == upperTicks.length &&
            dstChainIds.length == adapterParams.length,
            "Array length mismatch"
        );

        for (uint256 i = 0; i < dstChainIds.length; i++) {
            if (!supportedChainIds[dstChainIds[i]]) {
                revert TorqueDEX__UnsupportedChain();
            }

            // Transfer tokens to this contract first
            token0.transferFrom(msg.sender, address(this), amounts0[i]);
            token1.transferFrom(msg.sender, address(this), amounts1[i]);

            // Send cross-chain liquidity request
            _sendCrossChainLiquidityRequest(
                dstChainIds[i],
                msg.sender,
                amounts0[i],
                amounts1[i],
                lowerTicks[i],
                upperTicks[i],
                true, // isAdd
                adapterParams[i]
            );

            emit CrossChainLiquidityRequested(
                msg.sender,
                dstChainIds[i],
                amounts0[i],
                amounts1[i],
                lowerTicks[i],
                upperTicks[i],
                true
            );
        }
    }

    /**
     * @dev Remove liquidity from multiple chains
     */
    function removeCrossChainLiquidity(
        uint16[] calldata dstChainIds,
        uint256[] calldata liquidityAmounts,
        bytes[] calldata adapterParams
    ) external nonReentrant {
        require(
            dstChainIds.length == liquidityAmounts.length &&
            dstChainIds.length == adapterParams.length,
            "Array length mismatch"
        );

        for (uint256 i = 0; i < dstChainIds.length; i++) {
            if (!supportedChainIds[dstChainIds[i]]) {
                revert TorqueDEX__UnsupportedChain();
            }

            // Send cross-chain liquidity removal request
            _sendCrossChainLiquidityRequest(
                dstChainIds[i],
                msg.sender,
                0, // amount0 (not used for removal)
                0, // amount1 (not used for removal)
                0, // lowerTick (not used for removal)
                0, // upperTick (not used for removal)
                false, // isAdd
                adapterParams[i]
            );

            emit CrossChainLiquidityRequested(
                msg.sender,
                dstChainIds[i],
                0,
                0,
                0,
                0,
                false
            );
        }
    }

    /**
     * @dev Handle incoming cross-chain liquidity requests
     */
    function _nonblockingLzReceive(
        uint16 srcChainId,
        bytes memory srcAddress,
        uint64 nonce,
        bytes memory payload
    ) internal override {
        CrossChainLiquidityRequest memory request = abi.decode(
            payload,
            (CrossChainLiquidityRequest)
        );

        try this._processCrossChainLiquidity(request) {
            emit CrossChainLiquidityCompleted(
                request.user,
                srcChainId,
                request.isAdd ? totalLiquidity : 0,
                request.amount0,
                request.amount1,
                request.isAdd
            );
        } catch Error(string memory reason) {
            emit CrossChainLiquidityFailed(request.user, srcChainId, reason);
        } catch {
            emit CrossChainLiquidityFailed(request.user, srcChainId, "Unknown error");
        }
    }

    /**
     * @dev Process cross-chain liquidity request (external for try-catch)
     */
    function _processCrossChainLiquidity(CrossChainLiquidityRequest memory request) external {
        require(msg.sender == address(this), "Only self");

        if (request.isAdd) {
            // Add liquidity
            uint256 liquidity = _addLiquidityInternal(
                request.amount0,
                request.amount1,
                request.lowerTick,
                request.upperTick,
                request.user
            );
            crossChainLiquidity[request.sourceChainId][request.user] += liquidity;
        } else {
            // Remove liquidity
            uint256 liquidityToRemove = crossChainLiquidity[request.sourceChainId][request.user];
            require(liquidityToRemove > 0, "No cross-chain liquidity to remove");
            
            (uint256 amount0, uint256 amount1) = _removeLiquidityInternal(
                liquidityToRemove,
                request.user
            );
            crossChainLiquidity[request.sourceChainId][request.user] = 0;
        }
    }

    /**
     * @dev Send cross-chain liquidity request
     */
    function _sendCrossChainLiquidityRequest(
        uint16 dstChainId,
        address user,
        uint256 amount0,
        uint256 amount1,
        int256 lowerTick,
        int256 upperTick,
        bool isAdd,
        bytes calldata adapterParams
    ) internal {
        address dstDEX = dexAddresses[dstChainId];
        if (dstDEX == address(0)) {
            revert TorqueDEX__InvalidDEXAddress();
        }

        CrossChainLiquidityRequest memory request = CrossChainLiquidityRequest({
            user: user,
            amount0: amount0,
            amount1: amount1,
            lowerTick: lowerTick,
            upperTick: upperTick,
            sourceChainId: uint16(block.chainid),
            isAdd: isAdd
        });

        bytes memory payload = abi.encode(request);

        _lzSend(
            dstChainId,
            payload,
            payable(msg.sender),
            address(0),
            adapterParams
        );
    }

    /**
     * @dev Internal function to add liquidity
     */
    function _addLiquidityInternal(
        uint256 amount0,
        uint256 amount1,
        int256 lowerTick,
        int256 upperTick,
        address user
    ) internal returns (uint256 liquidity) {
        require(amount0 > 0 && amount1 > 0, "Zero amounts");
        require(lowerTick < upperTick, "Invalid range");

        if (isStablePair) {
            liquidity = _addStableLiquidity(amount0, amount1);
        } else {
            liquidity = _addConcentratedLiquidity(amount0, amount1, lowerTick, upperTick);
        }

        require(liquidity > 0, "Insufficient liquidity minted");
        totalLiquidity += liquidity;

        // Store range information for the user
        userRanges[user][0].push(Range({
            lowerTick: lowerTick,
            upperTick: upperTick,
            liquidity: liquidity,
            amount0: amount0,
            amount1: amount1
        }));

        // Mint LP tokens
        lpToken.mint(user, liquidity);

        emit LiquidityAdded(user, 0, amount0, amount1, liquidity);
        emit RangeAdded(user, 0, lowerTick, upperTick, liquidity);
    }

    /**
     * @dev Internal function to remove liquidity
     */
    function _removeLiquidityInternal(
        uint256 liquidity,
        address user
    ) internal returns (uint256 amount0, uint256 amount1) {
        require(liquidity > 0, "Zero liquidity");

        Range[] storage ranges = userRanges[user][0];
        require(ranges.length > 0, "No ranges found");
        
        Range storage range = ranges[ranges.length - 1];
        amount0 = range.amount0;
        amount1 = range.amount1;

        totalLiquidity -= liquidity;
        ranges.pop();

        lpToken.burn(user, liquidity);
        token0.transfer(user, amount0);
        token1.transfer(user, amount1);

        emit LiquidityRemoved(user, 0, liquidity, amount0, amount1);
        emit RangeRemoved(user, 0, range.lowerTick, range.upperTick, liquidity);
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

    function setFee(uint256 _feeBps) external onlyOwner {
        // CHECKS
        require(_feeBps <= 30, "Max 0.3%");
        
        // EFFECTS
        feeBps = _feeBps;
    }

    /**
     * @dev Set fee recipient address
     */
    function setFeeRecipient(address _feeRecipient) external onlyOwner {
        require(_feeRecipient != address(0), "Invalid fee recipient");
        feeRecipient = _feeRecipient;
    }

    // Cross-chain admin functions

    /**
     * @dev Set DEX address for a specific chain
     */
    function setDEXAddress(uint16 chainId, address dexAddress) external onlyOwner {
        require(supportedChainIds[chainId], "Unsupported chain");
        require(dexAddress != address(0), "Invalid address");
        dexAddresses[chainId] = dexAddress;
    }

    /**
     * @dev Get cross-chain liquidity for a user on a specific chain
     */
    function getCrossChainLiquidity(address user, uint16 chainId) external view returns (uint256) {
        return crossChainLiquidity[chainId][user];
    }

    /**
     * @dev Get total cross-chain liquidity across all chains for a user
     */
    function getTotalCrossChainLiquidity(address user) external view returns (uint256 total) {
        uint16[] memory chainIds = _getSupportedChainIds();
        for (uint256 i = 0; i < chainIds.length; i++) {
            total += crossChainLiquidity[chainIds[i]][user];
        }
    }

    /**
     * @dev Get all supported chain IDs
     */
    function _getSupportedChainIds() internal view returns (uint16[] memory) {
        uint16[] memory chainIds = new uint16[](11);
        chainIds[0] = 1;      // Ethereum
        chainIds[1] = 42161;  // Arbitrum
        chainIds[2] = 10;     // Optimism
        chainIds[3] = 137;    // Polygon
        chainIds[4] = 8453;   // Base
        chainIds[5] = 146;    // Sonic
        chainIds[6] = 2741;   // Abstract
        chainIds[7] = 56;     // BSC
        chainIds[8] = 999;    // HyperEVM
        chainIds[9] = 252;    // Fraxtal
        chainIds[10] = 43114; // Avalanche
        return chainIds;
    }

    /**
     * @dev Emergency function to recover stuck tokens
     */
    function emergencyWithdraw(
        address token,
        address to,
        uint256 amount
    ) external onlyOwner {
        IERC20(token).transfer(to, amount);
    }

    /**
     * @dev Get cross-chain liquidity quote (gas estimation)
     */
    function getCrossChainLiquidityQuote(
        uint16[] calldata dstChainIds,
        bytes[] calldata adapterParams
    ) external view returns (uint256 totalGasEstimate) {
        require(dstChainIds.length == adapterParams.length, "Array length mismatch");
        
        totalGasEstimate = 0;
        for (uint256 i = 0; i < dstChainIds.length; i++) {
            // Estimate gas for each cross-chain message
            uint256 messageGas = _estimateGasForMessage(dstChainIds[i], adapterParams[i]);
            totalGasEstimate += messageGas;
        }
        
        // Add base transaction gas
        totalGasEstimate += 21000;
    }

    /**
     * @dev Estimate gas for a single cross-chain message
     */
    function _estimateGasForMessage(
        uint16 dstChainId,
        bytes calldata adapterParams
    ) internal view returns (uint256) {
        // This would integrate with LayerZero's gas estimation
        // For now, return a conservative estimate
        return 100000; // Conservative estimate per message
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

    function totalSupply() public view returns (uint256) {
        return lpToken.totalSupply();
    }
}
