// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.30;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@layerzerolabs/lz-evm-oapp-v2/contracts/oapp/OApp.sol";
import "./TorqueLP.sol";

contract TorqueDEX is OApp, ReentrancyGuard {
    
    mapping(bytes32 => Pool) public pools;
    mapping(address => bool) public isPool;
    address[] public allPools;
    mapping(address => uint256) public userRangeCount;
    
    address public defaultQuoteAsset;
    bool public defaultQuoteAssetSet = false;
    
    address public defaultFeeRecipient;
    uint256 public defaultFeeBps = 4;
    bool public defaultIsStablePair = false;
    
    mapping(uint16 => address) public dexAddresses;
    mapping(uint16 => bool) public supportedChainIds;
    
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
        
        uint256 volume24h;
        uint256 volume7d;
        uint256 volume30d;
        uint256 fees24h;
        uint256 fees7d;
        uint256 fees30d;
        uint256 lastVolumeUpdate;
        uint256 lastFeeUpdate;
        
        uint256 totalParticipants;
        mapping(address => bool) participants;
    }
    
    struct Tick {
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

    uint256 public constant A = 1000;
    uint256 public constant PRECISION = 1e18;

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

    event VolumeUpdated(address indexed baseToken, address indexed quoteToken, uint256 volume24h, uint256 volume7d, uint256 volume30d);
    event FeesUpdated(address indexed baseToken, address indexed quoteToken, uint256 fees24h, uint256 fees7d, uint256 fees30d);
    event ParticipantAdded(address indexed baseToken, address indexed quoteToken, address indexed participant);

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

    function setDefaultQuoteAsset(address _defaultQuoteAsset) external onlyOwner {
        if (_defaultQuoteAsset == address(0)) {
            revert TorqueDEX__InvalidTokens();
        }
        
        address oldQuoteAsset = defaultQuoteAsset;
        defaultQuoteAsset = _defaultQuoteAsset;
        defaultQuoteAssetSet = true;
        
        emit DefaultQuoteAssetSet(oldQuoteAsset, _defaultQuoteAsset);
    }
    
    function createPool(
        address baseToken,
        address quoteToken,
        string memory pairName,
        string memory pairSymbol,
        address feeRecipient,
        bool isStablePair,
        uint256 customFeeBps
    ) external onlyOwner returns (address lpTokenAddress) {
        if (baseToken == address(0) || quoteToken == address(0)) {
            revert TorqueDEX__InvalidTokens();
        }
        if (baseToken == quoteToken) {
            revert TorqueDEX__InvalidTokens();
        }
        if (feeRecipient == address(0)) {
            revert TorqueDEX__InvalidFeeRecipient();
        }
        if (customFeeBps > 1000) {
            revert("Fee too high");
        }
        
        bytes32 pairHash = keccak256(abi.encodePacked(baseToken, quoteToken));
        if (pools[pairHash].active) {
            revert TorqueDEX__PairAlreadyExists();
        }
        
        string memory lpName = string(abi.encodePacked("Torque ", pairName, " LP"));
        string memory lpSymbol = string(abi.encodePacked("T", pairSymbol));
        
        TorqueLP lpToken = new TorqueLP(lpName, lpSymbol, address(endpoint), owner());
        lpToken.setDEX(address(this));
        
        Pool storage pool = pools[pairHash];
        pool.baseToken = baseToken;
        pool.quoteToken = quoteToken;
        pool.lpToken = address(lpToken);
        pool.feeBps = customFeeBps;
        pool.feeRecipient = feeRecipient;
        pool.isStablePair = isStablePair;
        pool.active = true;
        pool.totalLiquidity = 0;
        
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
    
    function getPool(address baseToken, address quoteToken) external view returns (
        address baseToken_,
        address quoteToken_,
        address lpToken_,
        uint256 feeBps_,
        address feeRecipient_,
        bool isStablePair_,
        bool active_,
        uint256 totalLiquidity_
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
            pool.totalLiquidity
        );
    }
    
    function getPoolAddress(address baseToken, address quoteToken) external view returns (address) {
        bytes32 pairHash = keccak256(abi.encodePacked(baseToken, quoteToken));
        Pool storage pool = pools[pairHash];
        if (!pool.active) {
            revert TorqueDEX__PoolNotFound();
        }
        return pool.lpToken;
    }
    
    function getAllPools() external view returns (address[] memory) {
        return allPools;
    }
    
    function getPoolCount() external view returns (uint256) {
        return allPools.length;
    }
    
    function hasPool(address baseToken, address quoteToken) external view returns (bool) {
        bytes32 pairHash = keccak256(abi.encodePacked(baseToken, quoteToken));
        return pools[pairHash].active;
    }
    
    function deactivatePool(address baseToken, address quoteToken) external onlyOwner {
        bytes32 pairHash = keccak256(abi.encodePacked(baseToken, quoteToken));
        Pool storage pool = pools[pairHash];
        if (!pool.active) {
            revert TorqueDEX__PoolNotFound();
        }
        pool.active = false;
        emit PoolDeactivated(baseToken, quoteToken);
    }
    
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
        
        if (tokenIn != pool.baseToken && tokenIn != pool.quoteToken) {
            revert TorqueDEX__InvalidTokens();
        }
        
        address tokenOut = tokenIn == pool.baseToken ? pool.quoteToken : pool.baseToken;
        
        IERC20(tokenIn).transferFrom(msg.sender, address(this), amountIn);
        
        if (pool.isStablePair) {
            amountOut = _calculateStableSwapAmount(pool, tokenIn, amountIn);
        } else {
            amountOut = _calculateSwapAmount(pool, tokenIn, amountIn);
        }
        
        if (amountOut < minAmountOut) {
            revert TorqueDEX__SlippageExceeded();
        }
        
        IERC20(tokenOut).transfer(msg.sender, amountOut);
        
        uint256 fee = (amountIn * pool.feeBps) / 10000;
        if (fee > 0) {
            IERC20(tokenIn).transfer(pool.feeRecipient, fee);
        }
        
        _updateVolumeStats(pool, amountIn);
        _updateFeeStats(pool, fee);
        
        emit SwapExecuted(msg.sender, baseToken, quoteToken, tokenIn, amountIn, tokenOut, amountOut);
        
        return amountOut;
    }
    
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
        
        IERC20(pool.baseToken).transferFrom(msg.sender, address(this), amount0);
        IERC20(pool.quoteToken).transferFrom(msg.sender, address(this), amount1);
        
        liquidity = _calculateLiquidity(amount0, amount1, lowerTick, upperTick);
        
        pool.totalLiquidity += liquidity;
        pool.ticks[lowerTick].liquidityGross += liquidity;
        pool.ticks[upperTick].liquidityGross += liquidity;
        
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
        
        _addParticipant(pool, msg.sender);
        
        TorqueLP(pool.lpToken).mint(msg.sender, liquidity);
        
        emit LiquidityAdded(msg.sender, baseToken, quoteToken, amount0, amount1, liquidity);
        emit RangeAdded(msg.sender, baseToken, quoteToken, lowerTick, upperTick, liquidity);
        
        return liquidity;
    }
    
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
        
        TorqueLP(pool.lpToken).burn(msg.sender, liquidity);
        
        Range[] storage ranges = pool.userRanges[msg.sender][rangeIndex];
        require(ranges.length > 0, "No ranges found");
        
        uint256 foundRangeIndex = 0;
        bool rangeFound = false;
        for (uint256 i = 0; i < ranges.length; i++) {
            if (ranges[i].liquidity >= liquidity) {
                foundRangeIndex = i;
                rangeFound = true;
                break;
            }
        }
        require(rangeFound, "Insufficient liquidity in any range");
        Range storage range = ranges[foundRangeIndex];
        
        amount0 = (range.amount0 * liquidity) / range.liquidity;
        amount1 = (range.amount1 * liquidity) / range.liquidity;
        
        if (amount0 == 0 && amount1 == 0) {
            revert("No tokens to remove");
        }
        
        pool.totalLiquidity -= liquidity;
        pool.ticks[range.lowerTick].liquidityGross -= liquidity;
        pool.ticks[range.upperTick].liquidityGross -= liquidity;
        
        range.liquidity -= liquidity;
        range.amount0 -= amount0;
        range.amount1 -= amount1;
        
        IERC20(pool.baseToken).transfer(msg.sender, amount0);
        IERC20(pool.quoteToken).transfer(msg.sender, amount1);
        
        emit LiquidityRemoved(msg.sender, baseToken, quoteToken, liquidity, amount0, amount1);
        emit RangeRemoved(msg.sender, baseToken, quoteToken, range.lowerTick, range.upperTick, liquidity);
        
        return (amount0, amount1);
    }

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

            IERC20(pool.baseToken).transferFrom(msg.sender, address(this), amounts0[i]);
            IERC20(pool.quoteToken).transferFrom(msg.sender, address(this), amounts1[i]);

            _sendCrossChainLiquidityRequest(
                dstChainIds[i],
                msg.sender,
                baseToken,
                quoteToken,
                amounts0[i],
                amounts1[i],
                lowerTicks[i],
                upperTicks[i],
                true,
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

            _sendCrossChainLiquidityRequest(
                dstChainIds[i],
                msg.sender,
                baseToken,
                quoteToken,
                0,
                0,
                0,
                0,
                false,
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
            sourceChainId: 0,
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

    function _lzReceive(
        Origin calldata _origin,
        bytes32 _guid,
        bytes calldata _message,
        address _executor,
        bytes calldata _extraData
    ) internal override {
        CrossChainLiquidityRequest memory request = abi.decode(_message, (CrossChainLiquidityRequest));
        request.sourceChainId = uint16(_origin.srcEid);

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

        uint256 liquidity = _calculateLiquidity(
            request.amount0,
            request.amount1,
            request.lowerTick,
            request.upperTick
        );

        pool.totalLiquidity += liquidity;
        pool.ticks[request.lowerTick].liquidityGross += liquidity;
        pool.ticks[request.upperTick].liquidityGross += liquidity;

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

        uint256 totalLiquidityRemoved = 0;
        uint256 totalAmount0Removed = 0;
        uint256 totalAmount1Removed = 0;
        bool liquidityFound = false;

        bool removeAllLiquidity = (request.amount0 == 0 && request.amount1 == 0 && 
                                  request.lowerTick == 0 && request.upperTick == 0);
        bool removeSpecificRange = !removeAllLiquidity && 
                                 (request.lowerTick != 0 || request.upperTick != 0);

        uint256 userRangeCountValue = userRangeCount[request.user];
        for (uint256 rangeIndex = 0; rangeIndex < userRangeCountValue; rangeIndex++) {
            Range[] storage userRanges = pool.userRanges[request.user][rangeIndex];
            
            for (uint256 i = 0; i < userRanges.length; i++) {
                Range storage range = userRanges[i];
                
                if (range.liquidity == 0) {
                    continue;
                }

                bool shouldRemoveRange = false;
                uint256 liquidityToRemove = 0;
                uint256 amount0ToRemove = 0;
                uint256 amount1ToRemove = 0;

                if (removeAllLiquidity) {
                    shouldRemoveRange = true;
                    liquidityToRemove = range.liquidity;
                    amount0ToRemove = range.amount0;
                    amount1ToRemove = range.amount1;
                } else if (removeSpecificRange) {
                    if (range.lowerTick == request.lowerTick && range.upperTick == request.upperTick) {
                        shouldRemoveRange = true;
                        liquidityToRemove = range.liquidity;
                        amount0ToRemove = range.amount0;
                        amount1ToRemove = range.amount1;
                    }
                } else {
                    if (request.amount0 > 0 && request.amount1 > 0) {
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
                    pool.totalLiquidity -= liquidityToRemove;
                    pool.ticks[range.lowerTick].liquidityGross -= liquidityToRemove;
                    pool.ticks[range.upperTick].liquidityGross -= liquidityToRemove;
                    
                    range.liquidity -= liquidityToRemove;
                    range.amount0 -= amount0ToRemove;
                    range.amount1 -= amount1ToRemove;
                    
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

        TorqueLP(pool.lpToken).burn(request.user, totalLiquidityRemoved);

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
        
        uint256 amountInAfterFee = amountIn;
        
        uint256 amplification = A;
        uint256 d = _calculateStableInvariant(reserveIn, reserveOut, amplification);
        
        uint256 newReserveIn = reserveIn + amountInAfterFee;
        uint256 newD = _calculateStableInvariant(newReserveIn, reserveOut, amplification);
        
        uint256 dy = reserveOut - _calculateStableY(newReserveIn, newD, amplification);
        
        if (dy >= reserveOut) {
            revert TorqueDEX__InsufficientLiquidity();
        }
        
        return dy;
    }
    
    function _calculateStableInvariant(uint256 x, uint256 y, uint256 amplification) internal pure returns (uint256) {
        uint256 sum = x + y;
        if (sum == 0) return 0;
        
        uint256 product = x * y;
        uint256 amplificationFactor = amplification * PRECISION / 1000;
        
        return (product * amplificationFactor) / (sum * PRECISION);
    }
    
    function _calculateStableY(uint256 x, uint256 d, uint256 amplification) internal pure returns (uint256) {
        if (x == 0) return 0;
        
        uint256 amplificationFactor = amplification * PRECISION / 1000;
        uint256 denominator = amplificationFactor - PRECISION;
        
        if (denominator == 0) return x;
        
        uint256 numerator = d * x * PRECISION;
        uint256 y = numerator / (denominator * x + PRECISION * d);
        
        return y;
    }
    
    function _calculateSwapAmount(Pool storage pool, address tokenIn, uint256 amountIn) internal view returns (uint256) {
        if (pool.totalLiquidity == 0) {
            revert TorqueDEX__InsufficientLiquidity();
        }
        
        uint256 reserveIn = tokenIn == pool.baseToken ? 
            IERC20(pool.baseToken).balanceOf(address(this)) : 
            IERC20(pool.quoteToken).balanceOf(address(this));
        uint256 reserveOut = tokenIn == pool.baseToken ? 
            IERC20(pool.quoteToken).balanceOf(address(this)) : 
            IERC20(pool.baseToken).balanceOf(address(this));
        
        if (reserveIn == 0 || reserveOut == 0) {
            revert TorqueDEX__InsufficientLiquidity();
        }
        
        uint256 amountInAfterFee = amountIn;
        
        uint256 amountOut = (reserveOut * amountInAfterFee) / (reserveIn + amountInAfterFee);
        
        if (amountOut >= reserveOut) {
            revert TorqueDEX__InsufficientLiquidity();
        }
        
        return amountOut;
    }

    function _calculateLiquidity(uint256 amount0, uint256 amount1, int256 lowerTick, int256 upperTick) internal pure returns (uint256) {
        if (lowerTick >= upperTick) {
            revert("Invalid tick range");
        }
        
        if (amount0 == 0 && amount1 == 0) {
            return 0;
        }
        
        uint256 sqrtPriceLower = _getSqrtPriceAtTick(lowerTick);
        uint256 sqrtPriceUpper = _getSqrtPriceAtTick(upperTick);
        
        if (sqrtPriceLower >= sqrtPriceUpper) {
            revert("Invalid sqrt prices");
        }
        
        uint256 liquidity;
        
        if (amount0 > 0 && amount1 > 0) {
            uint256 product = amount0 * amount1;
            uint256 sqrtProduct = _sqrt(product);
            uint256 priceDiff = sqrtPriceUpper - sqrtPriceLower;
            liquidity = (sqrtProduct * 2**96) / priceDiff;
        } else if (amount0 > 0) {
            liquidity = (amount0 * 2**96) / (sqrtPriceUpper - sqrtPriceLower);
        } else {
            liquidity = (amount1 * 2**96) / (sqrtPriceUpper - sqrtPriceLower);
        }
        
        return liquidity;
    }
    
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
    
    function _calculateLiquidityRatio(Range storage range, uint256 targetAmount0, uint256 targetAmount1) internal view returns (uint256) {
        if (range.liquidity == 0) {
            return 0;
        }
        
        uint256 ratio0 = range.amount0 > 0 ? (targetAmount0 * 10000) / range.amount0 : 0;
        uint256 ratio1 = range.amount1 > 0 ? (targetAmount1 * 10000) / range.amount1 : 0;
        
        return ratio0 < ratio1 ? ratio0 : ratio1;
    }

    function setDefaultFeeRecipient(address _feeRecipient) external onlyOwner {
        if (_feeRecipient == address(0)) {
            revert TorqueDEX__InvalidFeeRecipient();
        }
        address oldRecipient = defaultFeeRecipient;
        defaultFeeRecipient = _feeRecipient;
        emit DefaultFeeRecipientUpdated(oldRecipient, _feeRecipient);
    }

    function setDefaultFeeBps(uint256 _feeBps) external onlyOwner {
        require(_feeBps <= 1000, "Fee too high");
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
    
    function _getUserRanges(
        address user,
        address baseToken,
        address quoteToken
    ) internal view returns (Range[] memory) {
        bytes32 pairHash = keccak256(abi.encodePacked(baseToken, quoteToken));
        Pool storage pool = pools[pairHash];
        if (!pool.active) {
            revert TorqueDEX__PoolNotFound();
        }
        uint256 totalRanges = 0;
        uint256 userRangeCountValue = userRangeCount[user];
        for (uint256 i = 0; i < userRangeCountValue; i++) {
            totalRanges += pool.userRanges[user][i].length;
        }
        Range[] memory ranges = new Range[](totalRanges);
        uint256 currentIndex = 0;
        for (uint256 i = 0; i < userRangeCountValue; i++) {
            Range[] storage userRanges = pool.userRanges[user][i];
            for (uint256 j = 0; j < userRanges.length; j++) {
                ranges[currentIndex] = userRanges[j];
                currentIndex++;
            }
        }
        return ranges;
    }
    function getUserRanges(
        address user,
        address baseToken,
        address quoteToken
    ) external view returns (Range[] memory) {
        return _getUserRanges(user, baseToken, quoteToken);
    }
    function _getPrice(address baseToken, address quoteToken) internal view returns (uint256 price) {
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
        if (pool.baseToken == baseToken) {
            price = (reserve1 * 1e18) / reserve0;
        } else {
            price = (reserve0 * 1e18) / reserve1;
        }
        return price;
    }
    function getPrice(address baseToken, address quoteToken) external view returns (uint256 price) {
        return _getPrice(baseToken, quoteToken);
    }
    
    function getPoolReserves(address baseToken, address quoteToken) external view returns (uint256 reserve0, uint256 reserve1) {
        bytes32 pairHash = keccak256(abi.encodePacked(baseToken, quoteToken));
        Pool storage pool = pools[pairHash];
        if (!pool.active) {
            revert TorqueDEX__PoolNotFound();
        }
        
        reserve0 = IERC20(pool.baseToken).balanceOf(address(this));
        reserve1 = IERC20(pool.quoteToken).balanceOf(address(this));
    }
    
    function getPoolFees(address baseToken, address quoteToken) external view returns (uint256 feeBps, address feeRecipient) {
        bytes32 pairHash = keccak256(abi.encodePacked(baseToken, quoteToken));
        Pool storage pool = pools[pairHash];
        if (!pool.active) {
            revert TorqueDEX__PoolNotFound();
        }
        
        feeBps = pool.feeBps;
        feeRecipient = pool.feeRecipient;
    }
    
    function _updateVolumeStats(
        Pool storage pool,
        uint256 volumeAmount
    ) internal {
        uint256 currentTime = block.timestamp;
        
        if (currentTime - pool.lastVolumeUpdate >= 1 days) {
            pool.volume24h = volumeAmount;
        } else {
            pool.volume24h += volumeAmount;
        }
        
        if (currentTime - pool.lastVolumeUpdate >= 7 days) {
            pool.volume7d = volumeAmount;
        } else {
            pool.volume7d += volumeAmount;
        }
        
        if (currentTime - pool.lastVolumeUpdate >= 30 days) {
            pool.volume30d = volumeAmount;
        } else {
            pool.volume30d += volumeAmount;
        }
        
        pool.lastVolumeUpdate = currentTime;
        
        emit VolumeUpdated(pool.baseToken, pool.quoteToken, pool.volume24h, pool.volume7d, pool.volume30d);
    }

    function _updateFeeStats(
        Pool storage pool,
        uint256 feeAmount
    ) internal {
        uint256 currentTime = block.timestamp;
        
        if (currentTime - pool.lastFeeUpdate >= 1 days) {
            pool.fees24h = feeAmount;
        } else {
            pool.fees24h += feeAmount;
        }
        
        if (currentTime - pool.lastFeeUpdate >= 7 days) {
            pool.fees7d = feeAmount;
        } else {
            pool.fees7d += feeAmount;
        }
        
        if (currentTime - pool.lastFeeUpdate >= 30 days) {
            pool.fees30d = feeAmount;
        } else {
            pool.fees30d += feeAmount;
        }
        
        pool.lastFeeUpdate = currentTime;
        
        emit FeesUpdated(pool.baseToken, pool.quoteToken, pool.fees24h, pool.fees7d, pool.fees30d);
    }

    function _addParticipant(
        Pool storage pool,
        address participant
    ) internal {
        if (!pool.participants[participant]) {
            pool.participants[participant] = true;
            pool.totalParticipants++;
            emit ParticipantAdded(pool.baseToken, pool.quoteToken, participant);
        }
    }

    function getPoolStats(address baseToken, address quoteToken) external view returns (
        uint256 volume24h,
        uint256 volume7d,
        uint256 volume30d,
        uint256 fees24h,
        uint256 fees7d,
        uint256 fees30d,
        uint256 totalParticipants,
        uint256 currentPrice,
        uint256 totalLiquidity
    ) {
        bytes32 pairHash = keccak256(abi.encodePacked(baseToken, quoteToken));
        Pool storage pool = pools[pairHash];
        if (!pool.active) {
            revert TorqueDEX__PoolNotFound();
        }
        
        volume24h = pool.volume24h;
        volume7d = pool.volume7d;
        volume30d = pool.volume30d;
        fees24h = pool.fees24h;
        fees7d = pool.fees7d;
        fees30d = pool.fees30d;
        totalParticipants = pool.totalParticipants;
        totalLiquidity = pool.totalLiquidity;
        
        uint256 reserve0 = IERC20(pool.baseToken).balanceOf(address(this));
        uint256 reserve1 = IERC20(pool.quoteToken).balanceOf(address(this));
        
        if (reserve0 > 0 && reserve1 > 0) {
            if (pool.baseToken == baseToken) {
                currentPrice = (reserve1 * 1e18) / reserve0;
            } else {
                currentPrice = (reserve0 * 1e18) / reserve1;
            }
        }
    }

    function isPoolParticipant(address baseToken, address quoteToken, address user) external view returns (bool) {
        bytes32 pairHash = keccak256(abi.encodePacked(baseToken, quoteToken));
        Pool storage pool = pools[pairHash];
        if (!pool.active) {
            revert TorqueDEX__PoolNotFound();
        }
        return pool.participants[user];
    }



    function getPoolAPR(
        address baseToken,
        address quoteToken,
        uint256 period
    ) external view returns (uint256 apr) {
        bytes32 pairHash = keccak256(abi.encodePacked(baseToken, quoteToken));
        Pool storage pool = pools[pairHash];
        if (!pool.active) {
            revert TorqueDEX__PoolNotFound();
        }
        
        uint256 fees;
        uint256 volume;
        
        if (period == 7 days) {
            fees = pool.fees7d;
            volume = pool.volume7d;
        } else if (period == 30 days) {
            fees = pool.fees30d;
            volume = pool.volume30d;
        } else {
            fees = pool.fees24h;
            volume = pool.volume24h;
        }
        
        if (volume == 0 || pool.totalLiquidity == 0) {
            return 0;
        }
        
        apr = (fees * 365 days * 10000) / (pool.totalLiquidity * period);
    }

    function getCrossChainLiquidityDistribution(
        address user,
        address baseToken,
        address quoteToken
    ) external view returns (
        uint16[] memory chainIds,
        uint256[] memory amounts,
        uint256 totalAmount
    ) {
        uint256 supportedChainCount = 0;
        for (uint16 i = 1; i <= 1000; i++) {
            if (supportedChainIds[i]) {
                supportedChainCount++;
            }
        }
        
        chainIds = new uint16[](supportedChainCount);
        amounts = new uint256[](supportedChainCount);
        
        uint256 index = 0;
        for (uint16 i = 1; i <= 1000; i++) {
            if (supportedChainIds[i]) {
                chainIds[index] = i;
                amounts[index] = 0;
                totalAmount += amounts[index];
                index++;
            }
        }
    }

    function getSupportedChains() external view returns (
        uint16[] memory chainIds,
        address[] memory chainDexAddresses
    ) {
        uint256 supportedChainCount = 0;
        for (uint16 i = 1; i <= 1000; i++) {
            if (supportedChainIds[i]) {
                supportedChainCount++;
            }
        }
        
        chainIds = new uint16[](supportedChainCount);
        chainDexAddresses = new address[](supportedChainCount);
        
        uint256 index = 0;
        for (uint16 i = 1; i <= 1000; i++) {
            if (supportedChainIds[i]) {
                chainIds[index] = i;
                chainDexAddresses[index] = dexAddresses[i];
                index++;
            }
        }
    }

    function getPoolRiskAssessment(
        address baseToken,
        address quoteToken
    ) external view returns (
        string memory riskLevel,
        uint256 volatilityRisk,
        uint256 liquidityRisk
    ) {
        bytes32 pairHash = keccak256(abi.encodePacked(baseToken, quoteToken));
        Pool storage pool = pools[pairHash];
        if (!pool.active) {
            revert TorqueDEX__PoolNotFound();
        }
        
        if (pool.isStablePair) {
            riskLevel = "Low";
            volatilityRisk = 500;
            liquidityRisk = 200;
        } else {
            riskLevel = "High";
            volatilityRisk = 2000;
            liquidityRisk = 1000;
        }
        
        if (pool.totalLiquidity < 1000e18) {
            liquidityRisk = 1500;
        }
    }

    function getUserPosition(
        address baseToken,
        address quoteToken,
        address user
    ) external view returns (
        uint256 totalLiquidity,
        uint256 lpTokens,
        uint256 token0Balance,
        uint256 token1Balance,
        Range[] memory ranges,
        bool isParticipant
    ) {
        bytes32 pairHash = keccak256(abi.encodePacked(baseToken, quoteToken));
        Pool storage pool = pools[pairHash];
        if (!pool.active) {
            revert TorqueDEX__PoolNotFound();
        }
        
        ranges = _getUserRanges(user, baseToken, quoteToken);
        
        totalLiquidity = 0;
        token0Balance = 0;
        token1Balance = 0;
        
        for (uint256 i = 0; i < ranges.length; i++) {
            totalLiquidity += ranges[i].liquidity;
            token0Balance += ranges[i].amount0;
            token1Balance += ranges[i].amount1;
        }
        
        lpTokens = TorqueLP(pool.lpToken).balanceOf(user);
        isParticipant = pool.participants[user];
    }

    function getUserTotalLiquidity(address user) external view returns (
        uint256 totalLiquidity,
        uint256 totalLpTokens,
        address[] memory poolAddresses,
        uint256[] memory poolLiquidity
    ) {
        uint256 poolCount = allPools.length;
        poolAddresses = new address[](poolCount);
        poolLiquidity = new uint256[](poolCount);
        
        for (uint256 i = 0; i < poolCount; i++) {
            address lpToken = allPools[i];
            poolAddresses[i] = lpToken;
            
            uint256 userLpBalance = TorqueLP(lpToken).balanceOf(user);
            poolLiquidity[i] = userLpBalance;
            totalLpTokens += userLpBalance;
            
            totalLiquidity += userLpBalance;
        }
    }

    function getPoolPriceRange(
        address baseToken,
        address quoteToken
    ) external view returns (
        uint256 minPrice,
        uint256 maxPrice,
        uint256 currentPrice,
        bool isStablePair
    ) {
        bytes32 pairHash = keccak256(abi.encodePacked(baseToken, quoteToken));
        Pool storage pool = pools[pairHash];
        if (!pool.active) {
            revert TorqueDEX__PoolNotFound();
        }
        
        isStablePair = pool.isStablePair;
        currentPrice = _getPrice(baseToken, quoteToken);
        
        if (isStablePair) {
            minPrice = (currentPrice * 95) / 100;
            maxPrice = (currentPrice * 105) / 100;
        } else {
            minPrice = (currentPrice * 80) / 100;
            maxPrice = (currentPrice * 120) / 100;
        }
    }
}
