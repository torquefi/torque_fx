// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.28;

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
        bool isAdd;
    }

    // Stable pair parameters
    uint256 public constant A = 1000;
    uint256 public constant PRECISION = 1e18;
    uint256 private constant LIQUIDATION_THRESHOLD = 98;
    uint256 private constant LIQUIDATION_BONUS = 20;
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


    constructor(address _lzEndpoint, address _owner) OApp(_lzEndpoint, _owner) Ownable(_owner) ReentrancyGuard() {}

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
        bool isStablePair,
        uint256 customFeeBps
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
        if (customFeeBps > 1000) { // Max 10%
            revert("Fee too high");
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
        pool.feeBps = customFeeBps;
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
            customFeeBps,
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
            defaultIsStablePair,
            defaultFeeBps
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
        
        // Calculate swap amount with proper AMM math
        if (pool.isStablePair) {
            amountOut = _calculateStableSwapAmount(pool, tokenIn, amountIn);
        } else {
            amountOut = _calculateSwapAmount(pool, tokenIn, amountIn);
        }
        
        // Calculate price impact for monitoring
        uint256 priceImpact = _calculatePriceImpact(pool, tokenIn, amountIn, amountOut);
        
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
        
        // Find the range with sufficient liquidity
        uint256 rangeIndex = 0;
        bool rangeFound = false;
        for (uint256 i = 0; i < ranges.length; i++) {
            if (ranges[i].liquidity >= liquidity) {
                rangeIndex = i;
                rangeFound = true;
                break;
            }
        }
        require(rangeFound, "Insufficient liquidity in any range");
        Range storage range = ranges[rangeIndex];
        
        // Calculate amounts based on liquidity proportion
        amount0 = (range.amount0 * liquidity) / range.liquidity;
        amount1 = (range.amount1 * liquidity) / range.liquidity;
        
        // Validate amounts
        if (amount0 == 0 && amount1 == 0) {
            revert("No tokens to remove");
        }
        
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

    /**
     * @dev Process cross-chain liquidity removal with specific range matching
     * This function handles the complex logic to find and remove specific user ranges
     */
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

        // Find and remove the user's liquidity ranges
        uint256 totalLiquidityRemoved = 0;
        uint256 totalAmount0Removed = 0;
        uint256 totalAmount1Removed = 0;
        bool liquidityFound = false;

        // Determine removal strategy based on request parameters
        bool removeAllLiquidity = (request.amount0 == 0 && request.amount1 == 0 && 
                                  request.lowerTick == 0 && request.upperTick == 0);
        bool removeSpecificRange = !removeAllLiquidity && 
                                 (request.lowerTick != 0 || request.upperTick != 0);

        // Iterate through all range indices for this user
        uint256 userRangeCountValue = userRangeCount[request.user];
        for (uint256 rangeIndex = 0; rangeIndex < userRangeCountValue; rangeIndex++) {
            Range[] storage userRanges = pool.userRanges[request.user][rangeIndex];
            
            // Iterate through all ranges in this index
            for (uint256 i = 0; i < userRanges.length; i++) {
                Range storage range = userRanges[i];
                
                // Skip if no liquidity in this range
                if (range.liquidity == 0) {
                    continue;
                }

                bool shouldRemoveRange = false;
                uint256 liquidityToRemove = 0;
                uint256 amount0ToRemove = 0;
                uint256 amount1ToRemove = 0;

                if (removeAllLiquidity) {
                    // Remove all liquidity from all ranges
                    shouldRemoveRange = true;
                    liquidityToRemove = range.liquidity;
                    amount0ToRemove = range.amount0;
                    amount1ToRemove = range.amount1;
                } else if (removeSpecificRange) {
                    // Remove liquidity from specific tick range
                    if (range.lowerTick == request.lowerTick && range.upperTick == request.upperTick) {
                        shouldRemoveRange = true;
                        liquidityToRemove = range.liquidity;
                        amount0ToRemove = range.amount0;
                        amount1ToRemove = range.amount1;
                    }
                } else {
                    // Remove liquidity based on amount criteria
                    if (request.amount0 > 0 && request.amount1 > 0) {
                        // Remove proportional liquidity based on amounts
                        uint256 liquidityRatio = _calculateLiquidityRatio(range, request.amount0, request.amount1);
                        if (liquidityRatio > 0) {
                            shouldRemoveRange = true;
                            liquidityToRemove = (range.liquidity * liquidityRatio) / 10000;
                            amount0ToRemove = (range.amount0 * liquidityRatio) / 10000;
                            amount1ToRemove = (range.amount1 * liquidityRatio) / 10000;
                        }
                    }
                }

                if (shouldRemoveRange && liquidityToRemove > 0) {
                    // Update pool state
                    pool.totalLiquidity -= liquidityToRemove;
                    pool.ticks[range.lowerTick].liquidityGross -= liquidityToRemove;
                    pool.ticks[range.upperTick].liquidityGross -= liquidityToRemove;
                    
                    // Update range
                    range.liquidity -= liquidityToRemove;
                    range.amount0 -= amount0ToRemove;
                    range.amount1 -= amount1ToRemove;
                    
                    // Accumulate totals
                    totalLiquidityRemoved += liquidityToRemove;
                    totalAmount0Removed += amount0ToRemove;
                    totalAmount1Removed += amount1ToRemove;
                    liquidityFound = true;
                }
            }
        }

        if (!liquidityFound) {
            emit CrossChainLiquidityFailed(
                request.user,
                request.baseToken,
                request.quoteToken,
                request.sourceChainId,
                "No liquidity found for user"
            );
            return;
        }

        // Burn LP tokens from the user
        TorqueLP(pool.lpToken).burn(request.user, totalLiquidityRemoved);

        // Transfer tokens back to the user
        if (totalAmount0Removed > 0) {
            IERC20(pool.baseToken).transfer(request.user, totalAmount0Removed);
        }
        if (totalAmount1Removed > 0) {
            IERC20(pool.quoteToken).transfer(request.user, totalAmount1Removed);
        }

        emit CrossChainLiquidityCompleted(
            request.user,
            request.baseToken,
            request.quoteToken,
            request.sourceChainId,
            totalLiquidityRemoved,
            totalAmount0Removed,
            totalAmount1Removed,
            false
        );
    }

    /**
     * @dev Calculate stable swap output amount using Stableswap formula
     * Implements the Stableswap invariant for stable pairs
     * Note: amountIn is already after fees when called from the main swap function
     */
    function _calculateStableSwapAmount(Pool storage pool, address tokenIn, uint256 amountIn) internal view returns (uint256) {
        uint256 reserveIn = tokenIn == pool.baseToken ? 
            IERC20(pool.baseToken).balanceOf(address(this)) : 
            IERC20(pool.quoteToken).balanceOf(address(this));
        uint256 reserveOut = tokenIn == pool.baseToken ? 
            IERC20(pool.quoteToken).balanceOf(address(this)) : 
            IERC20(pool.baseToken).balanceOf(address(this));
        
        if (reserveIn == 0 || reserveOut == 0) {
            revert TorqueDEX__InsufficientLiquidity();
        }
        
        // amountIn is already after fees when called from the main swap function
        uint256 amountInAfterFee = amountIn;
        
        // Stableswap formula: (x + dx) * (y - dy) = x * y with amplification
        uint256 amplification = A;
        uint256 d = _calculateStableInvariant(reserveIn, reserveOut, amplification);
        
        uint256 newReserveIn = reserveIn + amountInAfterFee;
        uint256 newD = _calculateStableInvariant(newReserveIn, reserveOut, amplification);
        
        // Calculate dy using the invariant
        uint256 dy = reserveOut - _calculateStableY(newReserveIn, newD, amplification);
        
        if (dy >= reserveOut) {
            revert TorqueDEX__InsufficientLiquidity();
        }
        
        return dy;
    }
    
    /**
     * @dev Calculate Stableswap invariant
     */
    function _calculateStableInvariant(uint256 x, uint256 y, uint256 amplification) internal pure returns (uint256) {
        uint256 sum = x + y;
        if (sum == 0) return 0;
        
        uint256 product = x * y;
        uint256 amplificationFactor = amplification * PRECISION / 1000;
        
        return (product * amplificationFactor) / (sum * PRECISION);
    }
    
    /**
     * @dev Calculate y from x and invariant for Stableswap
     */
    function _calculateStableY(uint256 x, uint256 d, uint256 amplification) internal pure returns (uint256) {
        if (x == 0) return 0;
        
        uint256 amplificationFactor = amplification * PRECISION / 1000;
        uint256 denominator = amplificationFactor - PRECISION;
        
        if (denominator == 0) return x;
        
        uint256 numerator = d * x * PRECISION;
        uint256 y = numerator / (denominator * x + PRECISION * d);
        
        return y;
    }
    
    /**
     * @dev Calculate swap output amount using constant product AMM formula
     * Implements the x * y = k formula
     * Note: amountIn is already after fees when called from the main swap function
     */
    function _calculateSwapAmount(Pool storage pool, address tokenIn, uint256 amountIn) internal view returns (uint256) {
        if (pool.totalLiquidity == 0) {
            revert TorqueDEX__InsufficientLiquidity();
        }
        
        // Get current reserves
        uint256 reserveIn = tokenIn == pool.baseToken ? 
            IERC20(pool.baseToken).balanceOf(address(this)) : 
            IERC20(pool.quoteToken).balanceOf(address(this));
        uint256 reserveOut = tokenIn == pool.baseToken ? 
            IERC20(pool.quoteToken).balanceOf(address(this)) : 
            IERC20(pool.baseToken).balanceOf(address(this));
        
        if (reserveIn == 0 || reserveOut == 0) {
            revert TorqueDEX__InsufficientLiquidity();
        }
        
        // amountIn is already after fees when called from the main swap function
        uint256 amountInAfterFee = amountIn;
        
        // Constant product formula: (x + dx) * (y - dy) = x * y
        // dy = (y * dx) / (x + dx)
        uint256 amountOut = (reserveOut * amountInAfterFee) / (reserveIn + amountInAfterFee);
        
        // Ensure minimum output
        if (amountOut >= reserveOut) {
            revert TorqueDEX__InsufficientLiquidity();
        }
        
        return amountOut;
    }

    /**
     * @dev Calculate liquidity based on amounts and tick range
     * Uses the geometric mean formula for concentrated liquidity
     */
    function _calculateLiquidity(uint256 amount0, uint256 amount1, int256 lowerTick, int256 upperTick) internal pure returns (uint256) {
        if (lowerTick >= upperTick) {
            revert("Invalid tick range");
        }
        
        if (amount0 == 0 && amount1 == 0) {
            return 0;
        }
        
        // Calculate sqrt prices for the tick range
        uint256 sqrtPriceLower = _getSqrtPriceAtTick(lowerTick);
        uint256 sqrtPriceUpper = _getSqrtPriceAtTick(upperTick);
        
        if (sqrtPriceLower >= sqrtPriceUpper) {
            revert("Invalid sqrt prices");
        }
        
        // Calculate liquidity using the formula:
        // L = sqrt(amount0 * amount1) / (sqrt(P_upper) - sqrt(P_lower))
        uint256 liquidity;
        
        if (amount0 > 0 && amount1 > 0) {
            // Both amounts provided - use geometric mean
            uint256 product = amount0 * amount1;
            uint256 sqrtProduct = _sqrt(product);
            uint256 priceDiff = sqrtPriceUpper - sqrtPriceLower;
            liquidity = (sqrtProduct * 2**96) / priceDiff;
        } else if (amount0 > 0) {
            // Only amount0 provided
            liquidity = (amount0 * 2**96) / (sqrtPriceUpper - sqrtPriceLower);
        } else {
            // Only amount1 provided
            liquidity = (amount1 * 2**96) / (sqrtPriceUpper - sqrtPriceLower);
        }
        
        return liquidity;
    }
    
    /**
     * @dev Calculate square root using Babylonian method
     */
    function _sqrt(uint256 x) internal pure returns (uint256) {
        if (x == 0) return 0;
        
        uint256 z = (x + 1) / 2;
        uint256 y = x;
        
        while (z < y) {
            y = z;
            z = (x / z + z) / 2;
        }
        
        return y;
    }
    
    /**
     * @dev Get sqrt price at a given tick using proper Uniswap V3 math
     * Uses the formula: sqrt(1.0001^tick) * 2^96
     */
    function _getSqrtPriceAtTick(int256 tick) internal pure returns (uint256) {
        require(tick >= -887272 && tick <= 887272, "Tick out of bounds");
        
        uint256 absTick = tick < 0 ? uint256(-tick) : uint256(tick);
        require(absTick <= uint256(uint128(887272)), "Tick out of bounds");
        
        uint256 ratio = absTick & 0x1 != 0 ? 0xfffcb933bd6fad37aa2d162d1a594001 : 0x100000000000000000000000000000000;
        if (absTick & 0x2 != 0) ratio = (ratio * 0xfff97272373d413259a46990580e213a) >> 128;
        if (absTick & 0x4 != 0) ratio = (ratio * 0xfff2e50f5f656932ef12357cf3c7fdcc) >> 128;
        if (absTick & 0x8 != 0) ratio = (ratio * 0xffe5caca7e10e4e61c3624eaa0941cd0) >> 128;
        if (absTick & 0x10 != 0) ratio = (ratio * 0xffcb9843d60f6159c9db58835c926644) >> 128;
        if (absTick & 0x20 != 0) ratio = (ratio * 0xff973b41fa98c081472e6896dfb254c0) >> 128;
        if (absTick & 0x40 != 0) ratio = (ratio * 0xff2ea16466c96a3843ec78b326b52861) >> 128;
        if (absTick & 0x80 != 0) ratio = (ratio * 0xfe5dee046a99a2a811c461f1969c3053) >> 128;
        if (absTick & 0x100 != 0) ratio = (ratio * 0xfcbe86c7900a88aedcffc83b479aa3a4) >> 128;
        if (absTick & 0x200 != 0) ratio = (ratio * 0xf987a7253ac413176f2b074cf7815e54) >> 128;
        if (absTick & 0x400 != 0) ratio = (ratio * 0xf3392b0822b70005940c7a398e4b70f3) >> 128;
        if (absTick & 0x800 != 0) ratio = (ratio * 0xe7159475a2c29b7443b29c7fa6e889d9) >> 128;
        if (absTick & 0x1000 != 0) ratio = (ratio * 0xd097f3bdfd2022b8845ad8f792aa5825) >> 128;
        if (absTick & 0x2000 != 0) ratio = (ratio * 0xa9f746462d870fdf8a65dc1f90e061e5) >> 128;
        if (absTick & 0x4000 != 0) ratio = (ratio * 0x70d869a1562d1a5940005d97686c0) >> 128;
        if (absTick & 0x8000 != 0) ratio = (ratio * 0x31be135f97d08fd981231505542fcfa6) >> 128;
        if (absTick & 0x10000 != 0) ratio = (ratio * 0x9aa508b5b7a84e1c677de54f3e99bc9) >> 128;
        if (absTick & 0x20000 != 0) ratio = (ratio * 0x5d6af8dedb81196699c329225ee604) >> 128;
        if (absTick & 0x40000 != 0) ratio = (ratio * 0x2216e584f5fa1ea926041bedfe98) >> 128;
        if (absTick & 0x80000 != 0) ratio = (ratio * 0x48a170391f7dc42444e8fa2) >> 128;
        
        if (tick > 0) ratio = type(uint256).max / ratio;
        
        return uint256(uint128(ratio));
    }
    
    /**
     * @dev Get tick from sqrt price using proper Uniswap V3 math
     * Inverse of _getSqrtPriceAtTick
     */
    function _getTickAtSqrtPrice(uint256 sqrtPriceX96) internal pure returns (int256) {
        require(sqrtPriceX96 >= 4295128739, "Price too low");
        require(sqrtPriceX96 <= 1461446703485210103287273052203988822378723970342, "Price too high");
        
        uint256 ratio = uint256(sqrtPriceX96) << 32;
        
        uint256 r = ratio;
        uint256 msb = 0;
        
        assembly {
            let f := shl(7, gt(r, 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF))
            msb := or(msb, f)
            r := shr(f, r)
        }
        assembly {
            let f := shl(6, gt(r, 0xFFFFFFFFFFFFFFFF))
            msb := or(msb, f)
            r := shr(f, r)
        }
        assembly {
            let f := shl(5, gt(r, 0xFFFFFFFF))
            msb := or(msb, f)
            r := shr(f, r)
        }
        assembly {
            let f := shl(4, gt(r, 0xFFFF))
            msb := or(msb, f)
            r := shr(f, r)
        }
        assembly {
            let f := shl(3, gt(r, 0xFF))
            msb := or(msb, f)
            r := shr(f, r)
        }
        assembly {
            let f := shl(2, gt(r, 0xF))
            msb := or(msb, f)
            r := shr(f, r)
        }
        assembly {
            let f := shl(1, gt(r, 0x3))
            msb := or(msb, f)
            r := shr(f, r)
        }
        assembly {
            let f := gt(r, 0x1)
            msb := or(msb, f)
        }
        
        if (msb >= 128) r = ratio >> (msb - 127);
        else r = ratio << (127 - msb);
        
        int256 log_2 = (int256(msb) - 128) << 64;
        
        int256 log_sqrt10001 = log_2;
        log_sqrt10001 = (log_sqrt10001 * 255738958999603826347141) >> 128;
        int256 tickLow = (log_sqrt10001 - 340299295680913241859614010066329721600) >> 128;
        int256 tickHigh = (log_sqrt10001 + 291339464771989622907027621153398088495) >> 128;
        
        tickLow = tickLow == tickHigh ? tickLow : _getSqrtPriceAtTick(tickLow) <= sqrtPriceX96 ? tickLow : tickHigh;
        tickHigh = tickLow == tickHigh ? tickHigh : _getSqrtPriceAtTick(tickHigh) > sqrtPriceX96 ? tickHigh : tickLow;
        
        return tickLow;
    }
    
    /**
     * @dev Calculate price impact of a swap
     */
    function _calculatePriceImpact(Pool storage pool, address tokenIn, uint256 amountIn, uint256 amountOut) internal view returns (uint256) {
        uint256 reserveIn = tokenIn == pool.baseToken ? 
            IERC20(pool.baseToken).balanceOf(address(this)) : 
            IERC20(pool.quoteToken).balanceOf(address(this));
        uint256 reserveOut = tokenIn == pool.baseToken ? 
            IERC20(pool.quoteToken).balanceOf(address(this)) : 
            IERC20(pool.baseToken).balanceOf(address(this));
        
        if (reserveIn == 0 || reserveOut == 0) {
            return 0;
        }
        
        // Calculate price before swap
        uint256 priceBefore = (reserveOut * 1e18) / reserveIn;
        
        // Calculate price after swap
        uint256 newReserveIn = reserveIn + amountIn;
        uint256 newReserveOut = reserveOut - amountOut;
        uint256 priceAfter = (newReserveOut * 1e18) / newReserveIn;
        
        // Calculate price impact as percentage
        if (priceBefore > priceAfter) {
            return ((priceBefore - priceAfter) * 10000) / priceBefore;
        } else {
            return ((priceAfter - priceBefore) * 10000) / priceBefore;
        }
    }

    /**
     * @dev Calculate amounts from liquidity using proper AMM math
     */
    function _calculateAmountsFromLiquidity(
        uint256 liquidity,
        int256 lowerTick,
        int256 upperTick,
        uint256 currentSqrtPriceX96
    ) internal pure returns (uint256 amount0, uint256 amount1) {
        if (liquidity == 0) {
            return (0, 0);
        }
        
        uint256 sqrtPriceLowerX96 = _getSqrtPriceAtTick(lowerTick);
        uint256 sqrtPriceUpperX96 = _getSqrtPriceAtTick(upperTick);
        
        if (currentSqrtPriceX96 <= sqrtPriceLowerX96) {
            // Current price is below range - only token0
            amount0 = _getLiquidityForAmount0(liquidity, sqrtPriceLowerX96, sqrtPriceUpperX96);
        } else if (currentSqrtPriceX96 >= sqrtPriceUpperX96) {
            // Current price is above range - only token1
            amount1 = _getLiquidityForAmount1(liquidity, sqrtPriceLowerX96, sqrtPriceUpperX96);
        } else {
            // Current price is within range - both tokens
            amount0 = _getLiquidityForAmount0(liquidity, currentSqrtPriceX96, sqrtPriceUpperX96);
            amount1 = _getLiquidityForAmount1(liquidity, sqrtPriceLowerX96, currentSqrtPriceX96);
        }
    }
    
    /**
     * @dev Calculate amount0 from liquidity
     */
    function _getLiquidityForAmount0(
        uint256 liquidity,
        uint256 sqrtPriceAX96,
        uint256 sqrtPriceBX96
    ) internal pure returns (uint256) {
        uint256 numerator = liquidity * (sqrtPriceBX96 - sqrtPriceAX96);
        uint256 denominator = sqrtPriceBX96;
        return numerator / denominator;
    }
    
    /**
     * @dev Calculate amount1 from liquidity
     */
    function _getLiquidityForAmount1(
        uint256 liquidity,
        uint256 sqrtPriceAX96,
        uint256 sqrtPriceBX96
    ) internal pure returns (uint256) {
        return liquidity * (sqrtPriceBX96 - sqrtPriceAX96) / 2**96;
    }
    
    /**
     * @dev Calculate liquidity ratio for proportional removal
     */
    function _calculateLiquidityRatio(Range storage range, uint256 targetAmount0, uint256 targetAmount1) internal view returns (uint256) {
        if (range.liquidity == 0) {
            return 0;
        }
        
        // Calculate ratios for both amounts
        uint256 ratio0 = range.amount0 > 0 ? (targetAmount0 * 10000) / range.amount0 : 0;
        uint256 ratio1 = range.amount1 > 0 ? (targetAmount1 * 10000) / range.amount1 : 0;
        
        // Return the minimum ratio to ensure we don't over-remove
        return ratio0 < ratio1 ? ratio0 : ratio1;
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
    
    /**
     * @dev Get user ranges for a specific pool
     */
    function getUserRanges(
        address user,
        address baseToken,
        address quoteToken
    ) external view returns (Range[] memory) {
        bytes32 pairHash = keccak256(abi.encodePacked(baseToken, quoteToken));
        Pool storage pool = pools[pairHash];
        if (!pool.active) {
            revert TorqueDEX__PoolNotFound();
        }
        
        uint256 totalRanges = 0;
        uint256 userRangeCountValue = userRangeCount[user];
        
        // Count total ranges
        for (uint256 i = 0; i < userRangeCountValue; i++) {
            totalRanges += pool.userRanges[user][i].length;
        }
        
        // Create result array
        Range[] memory ranges = new Range[](totalRanges);
        uint256 currentIndex = 0;
        
        // Fill result array
        for (uint256 i = 0; i < userRangeCountValue; i++) {
            Range[] storage userRanges = pool.userRanges[user][i];
            for (uint256 j = 0; j < userRanges.length; j++) {
                ranges[currentIndex] = userRanges[j];
                currentIndex++;
            }
        }
        
        return ranges;
    }
    
    /**
     * @dev Get pool reserves
     */
    function getPoolReserves(address baseToken, address quoteToken) external view returns (uint256 reserve0, uint256 reserve1) {
        bytes32 pairHash = keccak256(abi.encodePacked(baseToken, quoteToken));
        Pool storage pool = pools[pairHash];
        if (!pool.active) {
            revert TorqueDEX__PoolNotFound();
        }
        
        reserve0 = IERC20(pool.baseToken).balanceOf(address(this));
        reserve1 = IERC20(pool.quoteToken).balanceOf(address(this));
    }
    
    /**
     * @dev Get pool fee information
     */
    function getPoolFees(address baseToken, address quoteToken) external view returns (uint256 feeBps, address feeRecipient) {
        bytes32 pairHash = keccak256(abi.encodePacked(baseToken, quoteToken));
        Pool storage pool = pools[pairHash];
        if (!pool.active) {
            revert TorqueDEX__PoolNotFound();
        }
        
        feeBps = pool.feeBps;
        feeRecipient = pool.feeRecipient;
    }
    
    /**
     * @dev Get current price for a token pair
     * Returns price in quote token units per base token (scaled by 1e18)
     */
    function getPrice(address baseToken, address quoteToken) external view returns (uint256 price) {
        bytes32 pairHash = keccak256(abi.encodePacked(baseToken, quoteToken));
        Pool storage pool = pools[pairHash];
        if (!pool.active) {
            revert TorqueDEX__PoolNotFound();
        }
        
        uint256 reserve0 = IERC20(pool.baseToken).balanceOf(address(this));
        uint256 reserve1 = IERC20(pool.quoteToken).balanceOf(address(this));
        
        if (reserve0 == 0 || reserve1 == 0) {
            revert TorqueDEX__InsufficientLiquidity();
        }
        
        // Calculate price: quote token per base token
        if (pool.baseToken == baseToken) {
            // Base token is token0, quote token is token1
            price = (reserve1 * 1e18) / reserve0;
        } else {
            // Base token is token1, quote token is token0
            price = (reserve0 * 1e18) / reserve1;
        }
        
        return price;
    }
}
