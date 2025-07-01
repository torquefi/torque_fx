// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@layerzerolabs/lz-evm-oapp-v2/contracts/oapp/OApp.sol";
import "./TorqueLP.sol";

contract TorqueDEX is OApp, ReentrancyGuard {
    // Pool management
    mapping(bytes32 => Pool) public pools;
    mapping(address => bool) public isPool;
    address[] public allPools;
    
    // TUSD as quote asset
    address public tusdToken;
    bool public tusdSet = false;
    
    // Default parameters
    address public defaultFeeRecipient;
    uint256 public defaultFeeBps = 4; // 0.04%
    bool public defaultIsStablePair = false;
    
    // Cross-chain DEX addresses
    mapping(uint16 => address) public dexAddresses; // chainId => DEX address on that chain
    mapping(uint16 => bool) public supportedChainIds;
    
    // Pool structure
    struct Pool {
        address baseToken;
        address tusdToken;
        address lpToken;
        uint256 feeBps;
        address feeRecipient;
        bool isStablePair;
        bool active;
        uint256 totalLiquidity;
        mapping(int256 => Tick) ticks;
        mapping(address => mapping(uint256 => Range[])) userRanges;
        int256 currentTick;
        uint256 currentSqrtPriceX96;
    }
    
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
        address baseToken;
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
    uint256 private constant LIQUIDATION_THRESHOLD = 98; // 98% collateral threshold
    uint256 private constant LIQUIDATION_BONUS = 20; // 20% bonus for liquidators
    uint256 private constant MIN_HEALTH_FACTOR = 1e18;

    // Events
    event PoolCreated(
        address indexed baseToken,
        address indexed lpToken,
        string pairName,
        string pairSymbol,
        uint256 feeBps,
        address feeRecipient
    );
    event PoolDeactivated(address indexed baseToken);
    event LiquidityAdded(address indexed user, address indexed baseToken, uint256 amount0, uint256 amount1, uint256 liquidity);
    event LiquidityRemoved(address indexed user, address indexed baseToken, uint256 liquidity, uint256 amount0, uint256 amount1);
    event SwapExecuted(address indexed user, address indexed baseToken, address tokenIn, uint256 amountIn, address tokenOut, uint256 amountOut);
    event RangeAdded(address indexed user, address indexed baseToken, int256 lowerTick, int256 upperTick, uint256 liquidity);
    event RangeRemoved(address indexed user, address indexed baseToken, int256 lowerTick, int256 upperTick, uint256 liquidity);
    event TUSDTokenSet(address indexed oldTUSD, address indexed newTUSD);
    event DefaultFeeRecipientUpdated(address indexed oldRecipient, address indexed newRecipient);
    event DefaultFeeBpsUpdated(uint256 oldFeeBps, uint256 newFeeBps);
    event DefaultIsStablePairUpdated(bool oldIsStable, bool newIsStable);
    
    // Cross-chain events
    event CrossChainLiquidityRequested(
        address indexed user,
        address indexed baseToken,
        uint16 indexed dstChainId,
        uint256 amount0,
        uint256 amount1,
        int256 lowerTick,
        int256 upperTick,
        bool isAdd
    );
    event CrossChainLiquidityCompleted(
        address indexed user,
        address indexed baseToken,
        uint16 indexed srcChainId,
        uint256 liquidity,
        uint256 amount0,
        uint256 amount1,
        bool isAdd
    );
    event CrossChainLiquidityFailed(
        address indexed user,
        address indexed baseToken,
        uint16 indexed srcChainId,
        string reason
    );

    // Errors
    error TorqueDEX__PairAlreadyExists();
    error TorqueDEX__InvalidTokens();
    error TorqueDEX__InvalidFeeRecipient();
    error TorqueDEX__InvalidFeeBps();
    error TorqueDEX__TUSDNotSet();
    error TorqueDEX__BaseTokenCannotBeTUSD();
    error TorqueDEX__TUSDAlreadySet();
    error TorqueDEX__PoolNotFound();
    error TorqueDEX__PoolInactive();
    error TorqueDEX__UnsupportedChain();
    error TorqueDEX__InvalidDEXAddress();
    error TorqueDEX__CrossChainLiquidityFailed();
    error TorqueDEX__InsufficientLiquidity();
    error TorqueDEX__SlippageExceeded();

    constructor(
        address _lzEndpoint,
        address _owner,
        address _defaultFeeRecipient
    ) OApp(_lzEndpoint, _owner) Ownable(_owner) {
        defaultFeeRecipient = _defaultFeeRecipient;
        _initializeSupportedChains();
    }
    
    /**
     * @dev Set TUSD token address (can only be set once)
     */
    function setTUSDToken(address _tusdToken) external onlyOwner {
        if (tusdSet) {
            revert TorqueDEX__TUSDAlreadySet();
        }
        if (_tusdToken == address(0)) {
            revert TorqueDEX__InvalidTokens();
        }
        
        address oldTUSD = tusdToken;
        tusdToken = _tusdToken;
        tusdSet = true;
        
        emit TUSDTokenSet(oldTUSD, _tusdToken);
    }
    
    /**
     * @dev Create a new trading pool for a trading pair with TUSD as quote asset
     */
    function createPool(
        address baseToken,
        string memory pairName,
        string memory pairSymbol,
        address feeRecipient,
        bool isStablePair
    ) external onlyOwner returns (address lpTokenAddress) {
        // Validations
        if (!tusdSet) {
            revert TorqueDEX__TUSDNotSet();
        }
        if (baseToken == address(0) || baseToken == tusdToken) {
            revert TorqueDEX__BaseTokenCannotBeTUSD();
        }
        if (feeRecipient == address(0)) {
            revert TorqueDEX__InvalidFeeRecipient();
        }
        
        // Check if pair already exists
        bytes32 pairHash = keccak256(abi.encodePacked(baseToken, tusdToken));
        if (pools[pairHash].active) {
            revert TorqueDEX__PairAlreadyExists();
        }
        
        // Create unique LP token name and symbol
        string memory lpName = string(abi.encodePacked("Torque ", pairName, " LP"));
        string memory lpSymbol = string(abi.encodePacked("T", pairSymbol));
        
        // Deploy LP token
        TorqueLP lpToken = new TorqueLP(lpName, lpSymbol, address(endpoint), owner());
        lpToken.setDEX(address(this));
        
        // Create pool
        pools[pairHash] = Pool({
            baseToken: baseToken,
            tusdToken: tusdToken,
            lpToken: address(lpToken),
            feeBps: defaultFeeBps,
            feeRecipient: feeRecipient,
            isStablePair: isStablePair,
            active: true,
            totalLiquidity: 0,
            currentTick: 0,
            currentSqrtPriceX96: 0
        });
        
        isPool[address(lpToken)] = true;
        allPools.push(address(lpToken));
        
        emit PoolCreated(
            baseToken,
            address(lpToken),
            pairName,
            pairSymbol,
            defaultFeeBps,
            feeRecipient
        );
        
        return address(lpToken);
    }
    
    /**
     * @dev Create pool with default parameters
     */
    function createPoolWithDefaults(
        address baseToken,
        string memory pairName,
        string memory pairSymbol
    ) external onlyOwner returns (address lpTokenAddress) {
        return this.createPool(
            baseToken,
            pairName,
            pairSymbol,
            defaultFeeRecipient,
            defaultIsStablePair
        );
    }
    
    /**
     * @dev Get pool for a base token (TUSD is always the quote asset)
     */
    function getPool(address baseToken) external view returns (Pool memory) {
        if (!tusdSet) {
            revert TorqueDEX__TUSDNotSet();
        }
        bytes32 pairHash = keccak256(abi.encodePacked(baseToken, tusdToken));
        Pool storage pool = pools[pairHash];
        if (!pool.active) {
            revert TorqueDEX__PoolNotFound();
        }
        return pool;
    }
    
    /**
     * @dev Get pool address for a base token
     */
    function getPoolAddress(address baseToken) external view returns (address) {
        if (!tusdSet) {
            revert TorqueDEX__TUSDNotSet();
        }
        bytes32 pairHash = keccak256(abi.encodePacked(baseToken, tusdToken));
        Pool storage pool = pools[pairHash];
        if (!pool.active) {
            revert TorqueDEX__PoolNotFound();
        }
        return pool.lpToken;
    }
    
    /**
     * @dev Get all pool addresses
     */
    function getAllPools() external view returns (address[] memory) {
        return allPools;
    }
    
    /**
     * @dev Get total number of pools
     */
    function getPoolCount() external view returns (uint256) {
        return allPools.length;
    }
    
    /**
     * @dev Check if a base token has a pool
     */
    function hasPool(address baseToken) external view returns (bool) {
        if (!tusdSet) {
            return false;
        }
        bytes32 pairHash = keccak256(abi.encodePacked(baseToken, tusdToken));
        return pools[pairHash].active;
    }
    
    /**
     * @dev Deactivate a pool
     */
    function deactivatePool(address baseToken) external onlyOwner {
        bytes32 pairHash = keccak256(abi.encodePacked(baseToken, tusdToken));
        Pool storage pool = pools[pairHash];
        if (!pool.active) {
            revert TorqueDEX__PoolNotFound();
        }
        pool.active = false;
        emit PoolDeactivated(baseToken);
    }
    
    /**
     * @dev Swap tokens in a pool
     */
    function swap(
        address baseToken,
        address tokenIn,
        uint256 amountIn,
        uint256 minAmountOut
    ) external nonReentrant returns (uint256 amountOut) {
        bytes32 pairHash = keccak256(abi.encodePacked(baseToken, tusdToken));
        Pool storage pool = pools[pairHash];
        if (!pool.active) {
            revert TorqueDEX__PoolNotFound();
        }
        
        // Validate tokens
        if (tokenIn != pool.baseToken && tokenIn != pool.tusdToken) {
            revert TorqueDEX__InvalidTokens();
        }
        
        address tokenOut = tokenIn == pool.baseToken ? pool.tusdToken : pool.baseToken;
        
        // Transfer tokens in
        IERC20(tokenIn).transferFrom(msg.sender, address(this), amountIn);
        
        // Calculate swap amount (simplified - would need proper AMM math)
        amountOut = _calculateSwapAmount(pool, tokenIn, amountIn);
        
        if (amountOut < minAmountOut) {
            revert TorqueDEX__SlippageExceeded();
        }
        
        // Transfer tokens out
        IERC20(tokenOut).transfer(msg.sender, amountOut);
        
        // Collect fees
        uint256 fee = (amountIn * pool.feeBps) / 10000;
        if (fee > 0) {
            IERC20(tokenIn).transfer(pool.feeRecipient, fee);
        }
        
        emit SwapExecuted(msg.sender, baseToken, tokenIn, amountIn, tokenOut, amountOut);
        
        return amountOut;
    }
    
    /**
     * @dev Add liquidity to a pool
     */
    function addLiquidity(
        address baseToken,
        uint256 amount0,
        uint256 amount1,
        int256 lowerTick,
        int256 upperTick
    ) external nonReentrant returns (uint256 liquidity) {
        bytes32 pairHash = keccak256(abi.encodePacked(baseToken, tusdToken));
        Pool storage pool = pools[pairHash];
        if (!pool.active) {
            revert TorqueDEX__PoolNotFound();
        }
        
        // Transfer tokens
        IERC20(pool.baseToken).transferFrom(msg.sender, address(this), amount0);
        IERC20(pool.tusdToken).transferFrom(msg.sender, address(this), amount1);
        
        // Calculate liquidity (simplified)
        liquidity = _calculateLiquidity(amount0, amount1, lowerTick, upperTick);
        
        // Update pool state
        pool.totalLiquidity += liquidity;
        pool.ticks[lowerTick].liquidityGross += liquidity;
        pool.ticks[upperTick].liquidityGross += liquidity;
        
        // Add user range
        Range memory newRange = Range({
            lowerTick: lowerTick,
            upperTick: upperTick,
            liquidity: liquidity,
            amount0: amount0,
            amount1: amount1
        });
        pool.userRanges[msg.sender][pool.userRanges[msg.sender].length] = newRange;
        
        // Mint LP tokens
        TorqueLP(pool.lpToken).mint(msg.sender, liquidity);
        
        emit LiquidityAdded(msg.sender, baseToken, amount0, amount1, liquidity);
        emit RangeAdded(msg.sender, baseToken, lowerTick, upperTick, liquidity);
        
        return liquidity;
    }
    
    /**
     * @dev Remove liquidity from a pool
     */
    function removeLiquidity(
        address baseToken,
        uint256 liquidity,
        uint256 rangeIndex
    ) external nonReentrant returns (uint256 amount0, uint256 amount1) {
        bytes32 pairHash = keccak256(abi.encodePacked(baseToken, tusdToken));
        Pool storage pool = pools[pairHash];
        if (!pool.active) {
            revert TorqueDEX__PoolNotFound();
        }
        
        // Burn LP tokens
        TorqueLP(pool.lpToken).burnFrom(msg.sender, liquidity);
        
        // Get user range
        Range storage range = pool.userRanges[msg.sender][rangeIndex];
        require(range.liquidity >= liquidity, "Insufficient liquidity");
        
        // Calculate amounts (simplified)
        amount0 = (range.amount0 * liquidity) / range.liquidity;
        amount1 = (range.amount1 * liquidity) / range.liquidity;
        
        // Update pool state
        pool.totalLiquidity -= liquidity;
        pool.ticks[range.lowerTick].liquidityGross -= liquidity;
        pool.ticks[range.upperTick].liquidityGross -= liquidity;
        
        // Update range
        range.liquidity -= liquidity;
        range.amount0 -= amount0;
        range.amount1 -= amount1;
        
        // Transfer tokens
        IERC20(pool.baseToken).transfer(msg.sender, amount0);
        IERC20(pool.tusdToken).transfer(msg.sender, amount1);
        
        emit LiquidityRemoved(msg.sender, baseToken, liquidity, amount0, amount1);
        emit RangeRemoved(msg.sender, baseToken, range.lowerTick, range.upperTick, liquidity);
        
        return (amount0, amount1);
    }

    /**
     * @dev Add liquidity to multiple chains in a single transaction
     */
    function addCrossChainLiquidity(
        address baseToken,
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

        bytes32 pairHash = keccak256(abi.encodePacked(baseToken, tusdToken));
        Pool storage pool = pools[pairHash];
        if (!pool.active) {
            revert TorqueDEX__PoolNotFound();
        }

        for (uint256 i = 0; i < dstChainIds.length; i++) {
            if (!supportedChainIds[dstChainIds[i]]) {
                revert TorqueDEX__UnsupportedChain();
            }

            // Transfer tokens to this contract first
            IERC20(pool.baseToken).transferFrom(msg.sender, address(this), amounts0[i]);
            IERC20(pool.tusdToken).transferFrom(msg.sender, address(this), amounts1[i]);

            // Send cross-chain liquidity request
            _sendCrossChainLiquidityRequest(
                dstChainIds[i],
                msg.sender,
                baseToken,
                amounts0[i],
                amounts1[i],
                lowerTicks[i],
                upperTicks[i],
                true, // isAdd
                adapterParams[i]
            );

            emit CrossChainLiquidityRequested(
                msg.sender,
                baseToken,
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
        address baseToken,
        uint16[] calldata dstChainIds,
        uint256[] calldata liquidityAmounts,
        bytes[] calldata adapterParams
    ) external nonReentrant {
        require(
            dstChainIds.length == liquidityAmounts.length &&
            dstChainIds.length == adapterParams.length,
            "Array length mismatch"
        );

        bytes32 pairHash = keccak256(abi.encodePacked(baseToken, tusdToken));
        Pool storage pool = pools[pairHash];
        if (!pool.active) {
            revert TorqueDEX__PoolNotFound();
        }

        for (uint256 i = 0; i < dstChainIds.length; i++) {
            if (!supportedChainIds[dstChainIds[i]]) {
                revert TorqueDEX__UnsupportedChain();
            }

            // Send cross-chain liquidity removal request
            _sendCrossChainLiquidityRequest(
                dstChainIds[i],
                msg.sender,
                baseToken,
                0,
                0,
                0,
                0,
                false, // isRemove
                adapterParams[i]
            );

            emit CrossChainLiquidityRequested(
                msg.sender,
                baseToken,
                dstChainIds[i],
                0,
                0,
                0,
                0,
                false
            );
        }
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

    function _sendCrossChainLiquidityRequest(
        uint16 dstChainId,
        address user,
        address baseToken,
        uint256 amount0,
        uint256 amount1,
        int256 lowerTick,
        int256 upperTick,
        bool isAdd,
        bytes calldata adapterParams
    ) internal {
        CrossChainLiquidityRequest memory request = CrossChainLiquidityRequest({
            user: user,
            baseToken: baseToken,
            amount0: amount0,
            amount1: amount1,
            lowerTick: lowerTick,
            upperTick: upperTick,
            sourceChainId: 0, // Will be set by destination
            isAdd: isAdd
        });

        _lzSend(
            dstChainId,
            abi.encode(request),
            payable(msg.sender),
            address(0),
            adapterParams
        );
    }

    function _lzReceive(
        Origin calldata _origin,
        bytes32 _guid,
        bytes calldata _message,
        address _executor,
        bytes calldata _extraData
    ) internal override {
        CrossChainLiquidityRequest memory request = abi.decode(_message, (CrossChainLiquidityRequest));
        request.sourceChainId = _origin.srcEid;

        // Process cross-chain liquidity request
        if (request.isAdd) {
            _processCrossChainLiquidityAdd(request);
        } else {
            _processCrossChainLiquidityRemove(request);
        }
    }



    function _processCrossChainLiquidityAdd(CrossChainLiquidityRequest memory request) internal {
        bytes32 pairHash = keccak256(abi.encodePacked(request.baseToken, tusdToken));
        Pool storage pool = pools[pairHash];
        
        if (!pool.active) {
            emit CrossChainLiquidityFailed(
                request.user,
                request.baseToken,
                request.sourceChainId,
                "Pool not found"
            );
            return;
        }

        // Calculate liquidity
        uint256 liquidity = _calculateLiquidity(
            request.amount0,
            request.amount1,
            request.lowerTick,
            request.upperTick
        );

        // Update pool state
        pool.totalLiquidity += liquidity;
        pool.ticks[request.lowerTick].liquidityGross += liquidity;
        pool.ticks[request.upperTick].liquidityGross += liquidity;

        // Mint LP tokens to user
        TorqueLP(pool.lpToken).mint(request.user, liquidity);

        emit CrossChainLiquidityCompleted(
            request.user,
            request.baseToken,
            request.sourceChainId,
            liquidity,
            request.amount0,
            request.amount1,
            true
        );
    }

    function _processCrossChainLiquidityRemove(CrossChainLiquidityRequest memory request) internal {
        bytes32 pairHash = keccak256(abi.encodePacked(request.baseToken, tusdToken));
        Pool storage pool = pools[pairHash];
        
        if (!pool.active) {
            emit CrossChainLiquidityFailed(
                request.user,
                request.baseToken,
                request.sourceChainId,
                "Pool not found"
            );
            return;
        }

        // This would need more complex logic to handle specific user ranges
        // For now, we'll emit the event
        emit CrossChainLiquidityCompleted(
            request.user,
            request.baseToken,
            request.sourceChainId,
            0,
            0,
            0,
            false
        );
    }

    // Helper functions (simplified implementations)
    function _calculateSwapAmount(Pool storage pool, address tokenIn, uint256 amountIn) internal view returns (uint256) {
        // Simplified AMM calculation - would need proper math
        if (pool.totalLiquidity == 0) {
            revert TorqueDEX__InsufficientLiquidity();
        }
        
        // Basic constant product formula
        uint256 fee = (amountIn * pool.feeBps) / 10000;
        uint256 amountInAfterFee = amountIn - fee;
        
        // Simplified calculation - in reality would use proper AMM math
        return amountInAfterFee;
    }

    function _calculateLiquidity(uint256 amount0, uint256 amount1, int256 lowerTick, int256 upperTick) internal pure returns (uint256) {
        // Simplified liquidity calculation - would need proper math
        return amount0 + amount1;
    }

    // Admin functions
    function setDefaultFeeRecipient(address _defaultFeeRecipient) external onlyOwner {
        if (_defaultFeeRecipient == address(0)) {
            revert TorqueDEX__InvalidFeeRecipient();
        }
        address oldRecipient = defaultFeeRecipient;
        defaultFeeRecipient = _defaultFeeRecipient;
        emit DefaultFeeRecipientUpdated(oldRecipient, _defaultFeeRecipient);
    }

    function setDefaultFeeBps(uint256 _defaultFeeBps) external onlyOwner {
        if (_defaultFeeBps > 1000) { // Max 10%
            revert TorqueDEX__InvalidFeeBps();
        }
        uint256 oldFeeBps = defaultFeeBps;
        defaultFeeBps = _defaultFeeBps;
        emit DefaultFeeBpsUpdated(oldFeeBps, _defaultFeeBps);
    }

    function setDefaultIsStablePair(bool _defaultIsStablePair) external onlyOwner {
        bool oldIsStable = defaultIsStablePair;
        defaultIsStablePair = _defaultIsStablePair;
        emit DefaultIsStablePairUpdated(oldIsStable, _defaultIsStablePair);
    }

    function setDexAddress(uint16 chainId, address dexAddress) external onlyOwner {
        if (!supportedChainIds[chainId]) {
            revert TorqueDEX__UnsupportedChain();
        }
        dexAddresses[chainId] = dexAddress;
    }

    // Emergency functions
    function emergencyWithdraw(address token, address to, uint256 amount) external onlyOwner {
        IERC20(token).transfer(to, amount);
    }
}
