// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.28;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@layerzerolabs/lz-evm-oapp-v2/contracts/oapp/OApp.sol";
import "./TorqueLP.sol";

contract TorqueDEX is OApp, ReentrancyGuard {
    // Pool management
    mapping(bytes32 => Pool) public pools;
    mapping(address => bool) public isPool;
    address[] public allPools;
    // Track number of ranges per user
    mapping(address => uint256) public userRangeCount;
    
    address public defaultQuoteAsset;
    bool public defaultQuoteAssetSet = false;
    
    // Default parameters
    address public defaultFeeRecipient;
    uint256 public defaultFeeBps = 4; // 0.04%
    bool public defaultIsStablePair = false;
    
    // Cross-chain DEX addresses
    mapping(uint16 => address) public dexAddresses;
    mapping(uint16 => bool) public supportedChainIds;
    
    // Pool structure
    struct Pool {
        address baseToken;
        address quoteToken;
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

    struct CrossChainLiquidityRequest {
        address user;
        address baseToken;
        address quoteToken;
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
        address indexed quoteToken,
        address indexed lpToken,
        string pairName,
        string pairSymbol,
        uint256 feeBps,
        address feeRecipient
    );
    event PoolDeactivated(address indexed baseToken, address indexed quoteToken);
    event LiquidityAdded(address indexed user, address indexed baseToken, address indexed quoteToken, uint256 amount0, uint256 amount1, uint256 liquidity);
    event LiquidityRemoved(address indexed user, address indexed baseToken, address indexed quoteToken, uint256 liquidity, uint256 amount0, uint256 amount1);
    event SwapExecuted(address indexed user, address indexed baseToken, address indexed quoteToken, address tokenIn, uint256 amountIn, address tokenOut, uint256 amountOut);
    event RangeAdded(address indexed user, address indexed baseToken, address indexed quoteToken, int256 lowerTick, int256 upperTick, uint256 liquidity);
    event RangeRemoved(address indexed user, address indexed baseToken, address indexed quoteToken, int256 lowerTick, int256 upperTick, uint256 liquidity);
    event DefaultQuoteAssetSet(address indexed oldQuoteAsset, address indexed newQuoteAsset);
    event DefaultFeeRecipientUpdated(address indexed oldRecipient, address indexed newRecipient);
    event DefaultFeeBpsUpdated(uint256 oldFeeBps, uint256 newFeeBps);
    event DefaultIsStablePairUpdated(bool oldIsStable, bool newIsStable);
    
    // Cross-chain events
    event CrossChainLiquidityRequested(
        address indexed user,
        address indexed baseToken,
        address indexed quoteToken,
        uint16 dstChainId,
        uint256 amount0,
        uint256 amount1,
        int256 lowerTick,
        int256 upperTick,
        bool isAdd
    );
    event CrossChainLiquidityCompleted(
        address indexed user,
        address indexed baseToken,
        address indexed quoteToken,
        uint16 srcChainId,
        uint256 liquidity,
        uint256 amount0,
        uint256 amount1,
        bool isAdd
    );
    event CrossChainLiquidityFailed(
        address indexed user,
        address indexed baseToken,
        address indexed quoteToken,
        uint16 srcChainId,
        string reason
    );

    // Errors
    error TorqueDEX__DefaultQuoteAssetNotSet();
    error TorqueDEX__InvalidTokens();
    error TorqueDEX__InvalidFeeRecipient();
    error TorqueDEX__PairAlreadyExists();
    error TorqueDEX__PoolNotFound();
    error TorqueDEX__InsufficientLiquidity();
    error TorqueDEX__SlippageExceeded();
    error TorqueDEX__UnsupportedChain();
    error TorqueDEX__CrossChainLiquidityFailed();

    constructor(address _lzEndpoint, address _owner) OApp(_lzEndpoint, _owner) Ownable(_owner) {}

    /**
     * @dev Set the default quote asset (e.g., TUSD)
     */
    function setDefaultQuoteAsset(address _defaultQuoteAsset) external onlyOwner {
        if (_defaultQuoteAsset == address(0)) {
            revert TorqueDEX__InvalidTokens();
        }
        
        address oldQuoteAsset = defaultQuoteAsset;
        defaultQuoteAsset = _defaultQuoteAsset;
        defaultQuoteAssetSet = true;
        
        emit DefaultQuoteAssetSet(oldQuoteAsset, _defaultQuoteAsset);
    }
    
    /**
     * @dev Create a new trading pool for any token pair
     */
    function createPool(
        address baseToken,
        address quoteToken,
        string memory pairName,
        string memory pairSymbol,
        address feeRecipient,
        bool isStablePair
    ) external onlyOwner returns (address lpTokenAddress) {
        // Validations
        if (baseToken == address(0) || quoteToken == address(0)) {
            revert TorqueDEX__InvalidTokens();
        }
        if (baseToken == quoteToken) {
            revert TorqueDEX__InvalidTokens();
        }
        if (feeRecipient == address(0)) {
            revert TorqueDEX__InvalidFeeRecipient();
        }
        
        // Check if pair already exists
        bytes32 pairHash = keccak256(abi.encodePacked(baseToken, quoteToken));
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
        Pool storage pool = pools[pairHash];
        pool.baseToken = baseToken;
        pool.quoteToken = quoteToken;
        pool.lpToken = address(lpToken);
        pool.feeBps = defaultFeeBps;
        pool.feeRecipient = feeRecipient;
        pool.isStablePair = isStablePair;
        pool.active = true;
        pool.totalLiquidity = 0;
        pool.currentTick = 0;
        pool.currentSqrtPriceX96 = 0;
        
        isPool[address(lpToken)] = true;
        allPools.push(address(lpToken));
        
        emit PoolCreated(
            baseToken,
            quoteToken,
            address(lpToken),
            pairName,
            pairSymbol,
            defaultFeeBps,
            feeRecipient
        );
        
        return address(lpToken);
    }
    
    /**
     * @dev Create pool with default quote asset (TUSD)
     */
    function createPoolWithDefaultQuote(
        address baseToken,
        string memory pairName,
        string memory pairSymbol
    ) external onlyOwner returns (address lpTokenAddress) {
        if (!defaultQuoteAssetSet) {
            revert TorqueDEX__DefaultQuoteAssetNotSet();
        }
        return this.createPool(
            baseToken,
            defaultQuoteAsset,
            pairName,
            pairSymbol,
            defaultFeeRecipient,
            defaultIsStablePair
        );
    }
    
    /**
     * @dev Get pool info for a token pair
     * Returns only non-mapping fields.
     */
    function getPool(address baseToken, address quoteToken) external view returns (
        address baseToken_,
        address quoteToken_,
        address lpToken_,
        uint256 feeBps_,
        address feeRecipient_,
        bool isStablePair_,
        bool active_,
        uint256 totalLiquidity_,
        int256 currentTick_,
        uint256 currentSqrtPriceX96_
    ) {
        bytes32 pairHash = keccak256(abi.encodePacked(baseToken, quoteToken));
        Pool storage pool = pools[pairHash];
        if (!pool.active) {
            revert TorqueDEX__PoolNotFound();
        }
        return (
            pool.baseToken,
            pool.quoteToken,
            pool.lpToken,
            pool.feeBps,
            pool.feeRecipient,
            pool.isStablePair,
            pool.active,
            pool.totalLiquidity,
            pool.currentTick,
            pool.currentSqrtPriceX96
        );
    }
    
    /**
     * @dev Get pool address for a token pair
     */
    function getPoolAddress(address baseToken, address quoteToken) external view returns (address) {
        bytes32 pairHash = keccak256(abi.encodePacked(baseToken, quoteToken));
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
     * @dev Check if a token pair has a pool
     */
    function hasPool(address baseToken, address quoteToken) external view returns (bool) {
        bytes32 pairHash = keccak256(abi.encodePacked(baseToken, quoteToken));
        return pools[pairHash].active;
    }
    
    /**
     * @dev Deactivate a pool
     */
    function deactivatePool(address baseToken, address quoteToken) external onlyOwner {
        bytes32 pairHash = keccak256(abi.encodePacked(baseToken, quoteToken));
        Pool storage pool = pools[pairHash];
        if (!pool.active) {
            revert TorqueDEX__PoolNotFound();
        }
        pool.active = false;
        emit PoolDeactivated(baseToken, quoteToken);
    }
    
    /**
     * @dev Swap tokens in a pool
     */
    function swap(
        address baseToken,
        address quoteToken,
        address tokenIn,
        uint256 amountIn,
        uint256 minAmountOut
    ) external nonReentrant returns (uint256 amountOut) {
        bytes32 pairHash = keccak256(abi.encodePacked(baseToken, quoteToken));
        Pool storage pool = pools[pairHash];
        if (!pool.active) {
            revert TorqueDEX__PoolNotFound();
        }
        
        // Validate tokens
        if (tokenIn != pool.baseToken && tokenIn != pool.quoteToken) {
            revert TorqueDEX__InvalidTokens();
        }
        
        address tokenOut = tokenIn == pool.baseToken ? pool.quoteToken : pool.baseToken;
        
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
        
        emit SwapExecuted(msg.sender, baseToken, quoteToken, tokenIn, amountIn, tokenOut, amountOut);
        
        return amountOut;
    }
    
    /**
     * @dev Add liquidity to a pool
     */
    function addLiquidity(
        address baseToken,
        address quoteToken,
        uint256 amount0,
        uint256 amount1,
        int256 lowerTick,
        int256 upperTick
    ) external nonReentrant returns (uint256 liquidity) {
        bytes32 pairHash = keccak256(abi.encodePacked(baseToken, quoteToken));
        Pool storage pool = pools[pairHash];
        if (!pool.active) {
            revert TorqueDEX__PoolNotFound();
        }
        
        // Transfer tokens
        IERC20(pool.baseToken).transferFrom(msg.sender, address(this), amount0);
        IERC20(pool.quoteToken).transferFrom(msg.sender, address(this), amount1);
        
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
        uint256 rangeIndex = userRangeCount[msg.sender];
        pool.userRanges[msg.sender][rangeIndex].push(newRange);
        userRangeCount[msg.sender]++;
        
        // Mint LP tokens
        TorqueLP(pool.lpToken).mint(msg.sender, liquidity);
        
        emit LiquidityAdded(msg.sender, baseToken, quoteToken, amount0, amount1, liquidity);
        emit RangeAdded(msg.sender, baseToken, quoteToken, lowerTick, upperTick, liquidity);
        
        return liquidity;
    }
    
    /**
     * @dev Remove liquidity from a pool
     */
    function removeLiquidity(
        address baseToken,
        address quoteToken,
        uint256 liquidity,
        uint256 rangeIndex
    ) external nonReentrant returns (uint256 amount0, uint256 amount1) {
        bytes32 pairHash = keccak256(abi.encodePacked(baseToken, quoteToken));
        Pool storage pool = pools[pairHash];
        if (!pool.active) {
            revert TorqueDEX__PoolNotFound();
        }
        
        // Burn LP tokens
        TorqueLP(pool.lpToken).burn(msg.sender, liquidity);
        
        // Get user range
        Range[] storage ranges = pool.userRanges[msg.sender][rangeIndex];
        require(ranges.length > 0, "No ranges found");
        Range storage range = ranges[0]; // For now, use the first range
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
        IERC20(pool.quoteToken).transfer(msg.sender, amount1);
        
        emit LiquidityRemoved(msg.sender, baseToken, quoteToken, liquidity, amount0, amount1);
        emit RangeRemoved(msg.sender, baseToken, quoteToken, range.lowerTick, range.upperTick, liquidity);
        
        return (amount0, amount1);
    }

    /**
     * @dev Add liquidity to multiple chains in a single transaction
     */
    function addCrossChainLiquidity(
        address baseToken,
        address quoteToken,
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

        bytes32 pairHash = keccak256(abi.encodePacked(baseToken, quoteToken));
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
            IERC20(pool.quoteToken).transferFrom(msg.sender, address(this), amounts1[i]);

            // Send cross-chain liquidity request
            _sendCrossChainLiquidityRequest(
                dstChainIds[i],
                msg.sender,
                baseToken,
                quoteToken,
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
                quoteToken,
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
        address quoteToken,
        uint16[] calldata dstChainIds,
        uint256[] calldata liquidityAmounts,
        bytes[] calldata adapterParams
    ) external nonReentrant {
        require(
            dstChainIds.length == liquidityAmounts.length &&
            dstChainIds.length == adapterParams.length,
            "Array length mismatch"
        );

        bytes32 pairHash = keccak256(abi.encodePacked(baseToken, quoteToken));
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
                quoteToken,
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
                quoteToken,
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
     * @dev Send cross-chain liquidity request
     */
    function _sendCrossChainLiquidityRequest(
        uint16 dstChainId,
        address user,
        address baseToken,
        address quoteToken,
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
            quoteToken: quoteToken,
            amount0: amount0,
            amount1: amount1,
            lowerTick: lowerTick,
            upperTick: upperTick,
            sourceChainId: 0, // Will be set in _lzReceive
            isAdd: isAdd
        });

        _lzSend(
            dstChainId,
            abi.encode(request),
            adapterParams,
            MessagingFee(0, 0),
            payable(msg.sender)
        );
    }

    /**
     * @dev Handle cross-chain liquidity requests
     */
    function _lzReceive(
        Origin calldata _origin,
        bytes32 _guid,
        bytes calldata _message,
        address _executor,
        bytes calldata _extraData
    ) internal override {
        CrossChainLiquidityRequest memory request = abi.decode(_message, (CrossChainLiquidityRequest));
        request.sourceChainId = uint16(_origin.srcEid);

        // Process cross-chain liquidity request
        if (request.isAdd) {
            _processCrossChainLiquidityAdd(request);
        } else {
            _processCrossChainLiquidityRemove(request);
        }
    }

    function _processCrossChainLiquidityAdd(CrossChainLiquidityRequest memory request) internal {
        bytes32 pairHash = keccak256(abi.encodePacked(request.baseToken, request.quoteToken));
        Pool storage pool = pools[pairHash];
        
        if (!pool.active) {
            emit CrossChainLiquidityFailed(
                request.user,
                request.baseToken,
                request.quoteToken,
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
            request.quoteToken,
            request.sourceChainId,
            liquidity,
            request.amount0,
            request.amount1,
            true
        );
    }

    function _processCrossChainLiquidityRemove(CrossChainLiquidityRequest memory request) internal {
        bytes32 pairHash = keccak256(abi.encodePacked(request.baseToken, request.quoteToken));
        Pool storage pool = pools[pairHash];
        
        if (!pool.active) {
            emit CrossChainLiquidityFailed(
                request.user,
                request.baseToken,
                request.quoteToken,
                request.sourceChainId,
                "Pool not found"
            );
            return;
        }

        // This will need more complex logic to handle specific user ranges
        // For now, we'll emit the event
        emit CrossChainLiquidityCompleted(
            request.user,
            request.baseToken,
            request.quoteToken,
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
    function setDefaultFeeRecipient(address _feeRecipient) external onlyOwner {
        if (_feeRecipient == address(0)) {
            revert TorqueDEX__InvalidFeeRecipient();
        }
        address oldRecipient = defaultFeeRecipient;
        defaultFeeRecipient = _feeRecipient;
        emit DefaultFeeRecipientUpdated(oldRecipient, _feeRecipient);
    }

    function setDefaultFeeBps(uint256 _feeBps) external onlyOwner {
        require(_feeBps <= 1000, "Fee too high"); // Max 10%
        uint256 oldFeeBps = defaultFeeBps;
        defaultFeeBps = _feeBps;
        emit DefaultFeeBpsUpdated(oldFeeBps, _feeBps);
    }

    function setDefaultIsStablePair(bool _isStablePair) external onlyOwner {
        bool oldIsStable = defaultIsStablePair;
        defaultIsStablePair = _isStablePair;
        emit DefaultIsStablePairUpdated(oldIsStable, _isStablePair);
    }

    function addSupportedChain(uint16 chainId, address dexAddress) external onlyOwner {
        supportedChainIds[chainId] = true;
        dexAddresses[chainId] = dexAddress;
    }

    function removeSupportedChain(uint16 chainId) external onlyOwner {
        supportedChainIds[chainId] = false;
        delete dexAddresses[chainId];
    }
}
