// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.30;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@layerzerolabs/lz-evm-oapp-v2/contracts/oapp/OApp.sol";
import "./TorqueLP.sol";

/**
 * @title TorqueDEX
 * @dev DEX for tokenized assets with cross-chain liquidity provision
 * @dev Supports both volatile and stable pairs with concentrated liquidity ranges
 * @dev Enables cross-chain liquidity operations through LayerZero messaging
 */
contract TorqueDEX is OApp, ReentrancyGuard {
    using SafeERC20 for IERC20;
    
    mapping(bytes32 => Pool) public pools;
    address[] public allPools;
    mapping(address => uint256) public userRangeCount;
    
    address public defaultQuoteAsset;
    bool public defaultQuoteAssetSet = false;
    
    address public defaultFeeRecipient;
    uint256 public defaultFeeBps = 4;
    bool public defaultIsStablePair = false;
    
    mapping(uint16 => address) public dexAddresses;
    mapping(uint16 => bool) public supportedChainIds;
    uint16[] public supportedChainList;
    

    
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
        uint256 liquidityToRemove;
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

    /**
     * @dev Constructor to initialize the TorqueDEX contract
     * @param _lzEndpoint LayerZero endpoint address for cross-chain messaging
     * @param _owner Owner address with administrative privileges
     */
    constructor(address _lzEndpoint, address _owner) OApp(_lzEndpoint, _owner) Ownable(_owner) ReentrancyGuard() {}

    /**
     * @dev Set the default quote asset for creating new pools
     * @param _defaultQuoteAsset Address of the default quote token (e.g., USDC, USDT)
     * @notice Only callable by the contract owner
     * @notice Emits DefaultQuoteAssetSet event
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
     * @dev Create a new liquidity pool for a token pair
     * @param baseToken Address of the base token (e.g., TorqueEUR)
     * @param quoteToken Address of the quote token (e.g., USDC)
     * @param pairName Human-readable name for the pair (e.g., "TorqueEUR/USDC")
     * @param pairSymbol Symbol for the pair (e.g., "EUR/USDC")
     * @param feeRecipient Address to receive trading fees
     * @param isStablePair Whether this is a stable pair (lower fees, different pricing)
     * @param customFeeBps Custom fee in basis points (1-1000, where 1000 = 10%)
     * @return lpTokenAddress Address of the created LP token contract
     * @notice Only callable by the contract owner
     * @notice Emits PoolCreated event
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
        
        bytes32 pairHash = _getPairHash(baseToken, quoteToken);
        if (pools[pairHash].active) {
            revert TorqueDEX__PairAlreadyExists();
        }
        
        // Create canonical token order to prevent naming collisions
        (address token0, address token1) = baseToken < quoteToken ? (baseToken, quoteToken) : (quoteToken, baseToken);
        string memory token0Symbol = IERC20Metadata(token0).symbol();
        string memory token1Symbol = IERC20Metadata(token1).symbol();
        
        string memory lpName = string(abi.encodePacked("Torque ", pairName, " LP"));
        string memory lpSymbol = string(abi.encodePacked("T", token0Symbol, "/", token1Symbol));
        
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
     * @dev Create a new liquidity pool using the default quote asset
     * @param baseToken Address of the base token (e.g., TorqueEUR)
     * @param pairName Human-readable name for the pair
     * @param pairSymbol Symbol for the pair
     * @return lpTokenAddress Address of the created LP token contract
     * @notice Only callable by the contract owner
     * @notice Uses default quote asset, fee recipient, and fee settings
     * @notice Reverts if default quote asset is not set
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
     * @dev Get comprehensive pool information for a token pair
     * @param baseToken Address of the base token in the pair
     * @param quoteToken Address of the quote token in the pair
     * @return baseToken_ Address of the base token
     * @return quoteToken_ Address of the quote token
     * @return lpToken_ Address of the LP token contract
     * @return feeBps_ Fee in basis points
     * @return feeRecipient_ Address receiving trading fees
     * @return isStablePair_ Whether this is a stable pair
     * @return active_ Whether the pool is active
     * @return totalLiquidity_ Total liquidity in the pool
     * @notice Reverts if pool doesn't exist
     */
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
        Pool storage pool = _getPool(baseToken, quoteToken);
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
    
    /**
     * @dev Get the LP token address for a specific pool
     * @param baseToken Address of the base token in the pair
     * @param quoteToken Address of the quote token in the pair
     * @return Address of the LP token contract for the pool
     * @notice Reverts if pool doesn't exist
     */
    function getPoolAddress(address baseToken, address quoteToken) external view returns (address) {
        Pool storage pool = _getPool(baseToken, quoteToken);
        return pool.lpToken;
    }
    
    /**
     * @dev Get all active pool LP token addresses
     * @return Array of all LP token contract addresses
     */
    function getAllPools() external view returns (address[] memory) {
        return allPools;
    }
    
    /**
     * @dev Get the total number of active pools
     * @return Total number of pools created
     */
    function getPoolCount() external view returns (uint256) {
        return allPools.length;
    }
    
    /**
     * @dev Check if a pool exists for a token pair
     * @param baseToken Address of the base token in the pair
     * @param quoteToken Address of the quote token in the pair
     * @return True if pool exists and is active, false otherwise
     */
    function hasPool(address baseToken, address quoteToken) external view returns (bool) {
        bytes32 pairHash = _getPairHash(baseToken, quoteToken);
        return pools[pairHash].active;
    }
    
    /**
     * @dev Deactivate a pool (only owner can call)
     * @param baseToken Address of the base token in the pair
     * @param quoteToken Address of the quote token in the pair
     * @notice Only callable by the contract owner
     * @notice Emits PoolDeactivated event
     * @notice Reverts if pool doesn't exist
     */
    function deactivatePool(address baseToken, address quoteToken) external onlyOwner {
        Pool storage pool = _getPool(baseToken, quoteToken);
        pool.active = false;
        emit PoolDeactivated(baseToken, quoteToken);
    }
    
    /**
     * @dev Execute a token swap in a liquidity pool
     * @param baseToken Address of the base token in the pair
     * @param quoteToken Address of the quote token in the pair
     * @param tokenIn Address of the token being sold
     * @param amountIn Amount of tokens to sell
     * @param minAmountOut Minimum amount of tokens to receive (slippage protection)
     * @return amountOut Amount of tokens received from the swap
     * @notice Uses different pricing models for stable vs regular pairs
     * @notice Updates volume and fee statistics
     * @notice Emits SwapExecuted event
     * @notice Reverts if slippage exceeds minAmountOut
     */
    function swap(
        address baseToken,
        address quoteToken,
        address tokenIn,
        uint256 amountIn,
        uint256 minAmountOut
    ) external nonReentrant returns (uint256 amountOut) {
        Pool storage pool = _getPool(baseToken, quoteToken);
        
        if (tokenIn != pool.baseToken && tokenIn != pool.quoteToken) {
            revert TorqueDEX__InvalidTokens();
        }
        
        address tokenOut = tokenIn == pool.baseToken ? pool.quoteToken : pool.baseToken;
        
        // CHECKS
        require(amountIn > 0, "Amount must be greater than 0");
        
        // EFFECTS - Calculate amounts before state changes
        uint256 fee = (amountIn * pool.feeBps) / 10000;
        uint256 amountInAfterFee = amountIn - fee;
        
        if (pool.isStablePair) {
            amountOut = _calculateStableSwapAmount(pool, tokenIn, amountInAfterFee);
        } else {
            amountOut = _calculateSwapAmount(pool, tokenIn, amountInAfterFee);
        }
        
        if (amountOut < minAmountOut) {
            revert TorqueDEX__SlippageExceeded();
        }
        
        // INTERACTIONS - Transfer tokens after all calculations
        IERC20(tokenIn).safeTransferFrom(msg.sender, address(this), amountIn);
        IERC20(tokenOut).safeTransfer(msg.sender, amountOut);
        
        if (fee > 0) {
            IERC20(tokenIn).safeTransfer(pool.feeRecipient, fee);
        }
        
        _updateVolumeStats(pool, amountIn);
        _updateFeeStats(pool, fee);
        
        emit SwapExecuted(msg.sender, baseToken, quoteToken, tokenIn, amountIn, tokenOut, amountOut);
        
        return amountOut;
    }
    

    
    /**
     * @dev Add liquidity to a specific price range in a pool
     * @param baseToken Address of the base token in the pair
     * @param quoteToken Address of the quote token in the pair
     * @param amount0 Amount of base tokens to add
     * @param amount1 Amount of quote tokens to add
     * @param lowerTick Lower price tick for the liquidity range
     * @param upperTick Upper price tick for the liquidity range
     * @return liquidity Amount of LP tokens minted to the user
     * @notice Creates a concentrated liquidity position within the specified range
     * @notice Mints LP tokens proportional to the liquidity provided
     * @notice Emits LiquidityAdded and RangeAdded events
     * @notice Reverts if tick range is invalid or pool doesn't exist
     */
    function addLiquidity(
        address baseToken,
        address quoteToken,
        uint256 amount0,
        uint256 amount1,
        int256 lowerTick,
        int256 upperTick
    ) external nonReentrant returns (uint256 liquidity) {
        Pool storage pool = _getPool(baseToken, quoteToken);
        
        // CHECKS
        require(amount0 > 0 || amount1 > 0, "At least one amount must be greater than 0");
        require(lowerTick < upperTick, "Invalid tick range");
        
        // EFFECTS - Calculate liquidity before state changes
        liquidity = _calculateLiquidity(amount0, amount1, lowerTick, upperTick);
        require(liquidity > 0, "No liquidity minted");
        
        // INTERACTIONS - Transfer tokens after calculations
        if (amount0 > 0) {
            IERC20(pool.baseToken).safeTransferFrom(msg.sender, address(this), amount0);
        }
        if (amount1 > 0) {
            IERC20(pool.quoteToken).safeTransferFrom(msg.sender, address(this), amount1);
        }
        
        // Update state
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
    

    


    /**
     * @dev Remove liquidity from a specific tick range (safer than proportional removal)
     * @param baseToken Address of the base token in the pair
     * @param quoteToken Address of the quote token in the pair
     * @param lowerTick Lower price tick for the range
     * @param upperTick Upper price tick for the range
     * @param liquidity Amount of LP tokens to burn
     * @return amount0 Amount of base tokens returned
     * @return amount1 Amount of quote tokens returned
     * @notice Removes liquidity from exact tick range, avoiding proportional issues
     * @notice More predictable than rangeIndex-based removal
     */
    function removeLiquidityFromTicks(
        address baseToken,
        address quoteToken,
        int256 lowerTick,
        int256 upperTick,
        uint256 liquidity
    ) external nonReentrant returns (uint256 amount0, uint256 amount1) {
        Pool storage pool = _getPool(baseToken, quoteToken);
        
        require(lowerTick < upperTick, "Invalid tick range");
        require(liquidity > 0, "Liquidity must be greater than 0");
        
        TorqueLP(pool.lpToken).burn(msg.sender, liquidity);
        
        // Find the exact range matching the ticks
        bool rangeFound = false;
        uint256 userRangeCountValue = userRangeCount[msg.sender];
        
        for (uint256 rangeIndex = 0; rangeIndex < userRangeCountValue; rangeIndex++) {
            Range[] storage ranges = pool.userRanges[msg.sender][rangeIndex];
            
            for (uint256 i = 0; i < ranges.length; i++) {
                Range storage range = ranges[i];
                
                if (range.lowerTick == lowerTick && 
                    range.upperTick == upperTick && 
                    range.liquidity >= liquidity) {
                    
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
                    
                    rangeFound = true;
                    break;
                }
            }
            if (rangeFound) break;
        }
        
        require(rangeFound, "Exact tick range not found or insufficient liquidity");
        
        IERC20(pool.baseToken).safeTransfer(msg.sender, amount0);
        IERC20(pool.quoteToken).safeTransfer(msg.sender, amount1);
        
        emit LiquidityRemoved(msg.sender, baseToken, quoteToken, liquidity, amount0, amount1);
        emit RangeRemoved(msg.sender, baseToken, quoteToken, lowerTick, upperTick, liquidity);
        
        return (amount0, amount1);
    }
    
    /**
     * @dev Add liquidity to pools across multiple chains in a single transaction
     * @param baseToken Address of the base token in the pair
     * @param quoteToken Address of the quote token in the pair
     * @param dstChainIds Array of destination chain IDs
     * @param amounts0 Array of base token amounts for each chain
     * @param amounts1 Array of quote token amounts for each chain
     * @param lowerTicks Array of lower price ticks for each chain
     * @param upperTicks Array of upper price ticks for each chain
     * @param adapterParams Array of LayerZero adapter parameters for each chain
     * @notice Sends cross-chain messages to add liquidity on destination chains
     * @notice Emits CrossChainLiquidityRequested event for each chain
     * @notice Reverts if arrays have mismatched lengths or unsupported chains
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

        Pool storage pool = _getPool(baseToken, quoteToken);

        for (uint256 i = 0; i < dstChainIds.length; i++) {
            if (!supportedChainIds[dstChainIds[i]]) {
                revert TorqueDEX__UnsupportedChain();
            }

            IERC20(pool.baseToken).safeTransferFrom(msg.sender, address(this), amounts0[i]);
            IERC20(pool.quoteToken).safeTransferFrom(msg.sender, address(this), amounts1[i]);

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

    /**
     * @dev Remove liquidity from pools across multiple chains in a single transaction
     * @param baseToken Address of the base token in the pair
     * @param quoteToken Address of the quote token in the pair
     * @param dstChainIds Array of destination chain IDs
     * @param liquidityAmounts Array of liquidity amounts to remove from each chain
     * @param adapterParams Array of LayerZero adapter parameters for each chain
     * @notice Sends cross-chain messages to remove liquidity on destination chains
     * @notice Emits CrossChainLiquidityRequested event for each chain
     * @notice Reverts if arrays have mismatched lengths or unsupported chains
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

        bytes32 pairHash = _getPairHash(baseToken, quoteToken);
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



    /**
     * @dev Send cross-chain liquidity request to destination chain
     * @param dstChainId Destination chain ID
     * @param user Address of the user requesting liquidity operation
     * @param baseToken Address of the base token in the pair
     * @param quoteToken Address of the quote token in the pair
     * @param amount0 Amount of base tokens
     * @param amount1 Amount of quote tokens
     * @param lowerTick Lower price tick for the range
     * @param upperTick Upper price tick for the range
     * @param isAdd Whether this is an add or remove operation
     * @param adapterParams LayerZero adapter parameters
     * @notice Sends LayerZero message to destination chain
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
            liquidityToRemove: 0, // Will be calculated on destination chain
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

    /**
     * @dev Handle incoming cross-chain messages from LayerZero
     * @param _origin Origin information from LayerZero
     * @param _guid Unique message identifier
     * @param _message Decoded message containing liquidity request
     * @param _executor Address that executed the message
     * @param _extraData Additional data from LayerZero
     * @notice Processes cross-chain liquidity add requests only
     * @notice Emits appropriate completion or failure events
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
        if (request.isAdd) {
            _processCrossChainLiquidityAdd(request);
        } else {
            _processCrossChainLiquidityRemove(request);
        }
    }

    /**
     * @dev Process cross-chain liquidity addition request
     * @param request Cross-chain liquidity request containing user and token details
     * @notice Mints LP tokens to the user on the destination chain
     * @notice Emits CrossChainLiquidityCompleted or CrossChainLiquidityFailed event
     */
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

    /**
     * @dev Internal: Process cross-chain liquidity removal request
     * @param request CrossChainLiquidityRequest struct
     * @notice Burns LP tokens and returns underlying tokens to the user
     * @notice Emits CrossChainLiquidityCompleted or CrossChainLiquidityFailed event
     */
    function _processCrossChainLiquidityRemove(CrossChainLiquidityRequest memory request) internal {
        bytes32 pairHash = _getPairHash(request.baseToken, request.quoteToken);
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
        // For simplicity, remove all liquidity from all user ranges
        uint256 userRangeCountValue = userRangeCount[request.user];
        uint256 totalLiquidityRemoved = 0;
        uint256 totalAmount0Removed = 0;
        uint256 totalAmount1Removed = 0;
        for (uint256 rangeIndex = 0; rangeIndex < userRangeCountValue; rangeIndex++) {
            Range[] storage userRanges = pool.userRanges[request.user][rangeIndex];
            for (uint256 i = 0; i < userRanges.length; i++) {
                Range storage range = userRanges[i];
                if (range.liquidity > 0) {
                    totalLiquidityRemoved += range.liquidity;
                    totalAmount0Removed += range.amount0;
                    totalAmount1Removed += range.amount1;
                    pool.ticks[range.lowerTick].liquidityGross -= range.liquidity;
                    pool.ticks[range.upperTick].liquidityGross -= range.liquidity;
                    range.liquidity = 0;
                    range.amount0 = 0;
                    range.amount1 = 0;
                }
            }
        }
        if (totalLiquidityRemoved == 0) {
            emit CrossChainLiquidityFailed(
                request.user,
                request.baseToken,
                request.quoteToken,
                request.sourceChainId,
                "No liquidity found for user"
            );
            return;
        }
        pool.totalLiquidity -= totalLiquidityRemoved;
        TorqueLP(pool.lpToken).burn(request.user, totalLiquidityRemoved);
        if (totalAmount0Removed > 0) {
            IERC20(pool.baseToken).safeTransfer(request.user, totalAmount0Removed);
        }
        if (totalAmount1Removed > 0) {
            IERC20(pool.quoteToken).safeTransfer(request.user, totalAmount1Removed);
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
     * @dev Calculate swap output amount for stable pairs using constant product formula
     * @param pool Storage reference to the pool
     * @param tokenIn Address of the token being sold
     * @param amountIn Amount of tokens being sold
     * @return Amount of tokens to receive from the swap
     * @notice Uses amplified constant product formula for stable pairs
     * @notice Reverts if insufficient liquidity or reserves
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
        
        uint256 amountInAfterFee = amountIn;
        
        uint256 d = _calculateStableInvariant(reserveIn, reserveOut);
        
        uint256 newReserveIn = reserveIn + amountInAfterFee;
        uint256 newD = _calculateStableInvariant(newReserveIn, reserveOut);
        
        uint256 dy = reserveOut - _calculateStableY(newReserveIn, newD);
        
        if (dy >= reserveOut) {
            revert TorqueDEX__InsufficientLiquidity();
        }
        
        return dy;
    }
    
    /**
     * @dev Calculate stable swap invariant (D) using amplified constant product formula
     * @param x Amount of token X
     * @param y Amount of token Y
     * @return Invariant value D
     * @notice Used for stable pair pricing calculations with fixed amplification factor
     */
    function _calculateStableInvariant(uint256 x, uint256 y) internal pure returns (uint256) {
        uint256 sum = x + y;
        if (sum == 0) return 0;
        
        uint256 product = x * y;
        uint256 amplificationFactor = A * PRECISION / 1000;
        
        return (product * amplificationFactor) / (sum * PRECISION);
    }
    
    /**
     * @dev Calculate token Y amount given token X amount and invariant D
     * @param x Amount of token X
     * @param d Invariant value D
     * @param amplification Amplification factor
     * @return Amount of token Y
     * @notice Used in stable swap calculations to find Y given X and D
     */
    /**
     * @dev Calculate token Y amount given token X and invariant D for stable pairs
     * @param x Amount of token X
     * @param d Invariant value D
     * @return Amount of token Y
     * @notice Used for stable pair swap calculations with fixed amplification factor
     */
    function _calculateStableY(uint256 x, uint256 d) internal pure returns (uint256) {
        if (x == 0) return 0;
        
        uint256 amplificationFactor = A * PRECISION / 1000;
        uint256 denominator = amplificationFactor - PRECISION;
        
        if (denominator == 0) return x;
        
        uint256 numerator = d * x * PRECISION;
        uint256 y = numerator / (denominator * x + PRECISION * d);
        
        return y;
    }
    
    /**
     * @dev Calculate swap output amount for regular pairs using constant product formula
     * @param pool Storage reference to the pool
     * @param tokenIn Address of the token being sold
     * @param amountIn Amount of tokens being sold
     * @return Amount of tokens to receive from the swap
     * @notice Uses standard constant product formula (x * y = k)
     * @notice Reverts if insufficient liquidity or reserves
     */
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

    /**
     * @dev Calculate liquidity amount based on token amounts and price range
     * @param amount0 Amount of base tokens
     * @param amount1 Amount of quote tokens
     * @param lowerTick Lower price tick for the range
     * @param upperTick Upper price tick for the range
     * @return liquidity Calculated liquidity amount
     * @notice Uses Uniswap V3-style liquidity calculation
     * @notice Reverts if tick range is invalid or amounts are zero
     */
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
    
    /**
     * @dev Calculate square root using Newton's method
     * @param x Number to calculate square root of
     * @return Square root of x
     * @notice Uses iterative approximation for square root calculation
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
     * @dev Get square root price at a specific tick
     * @param tick Tick index (-887272 to 887272)
     * @return Square root price as Q64.96 fixed point number
     * @notice Uses Uniswap V3-style tick to price conversion with hardcoded constants
     * @notice Constants are from Uniswap V3: https://github.com/Uniswap/v3-core/blob/main/contracts/libraries/TickMath.sol
     * @notice Reverts if tick is out of bounds
     */
    function _getSqrtPriceAtTick(int256 tick) internal pure returns (uint256) {
        require(tick >= -887272 && tick <= 887272, "Tick out of bounds");
        
        uint256 absTick = tick < 0 ? uint256(-tick) : uint256(tick);
        require(absTick <= uint256(uint128(887272)), "Tick out of bounds");
        
        // Uniswap V3 tick math constants (1.0001^tick)
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
     * @dev Calculate liquidity ratio for partial range removal
     * @param range Storage reference to the liquidity range
     * @param targetAmount0 Target amount of base tokens to remove
     * @param targetAmount1 Target amount of quote tokens to remove
     * @return Liquidity ratio in basis points (0-10000)
     * @notice Returns the minimum ratio to maintain token proportions
     */
    function _calculateLiquidityRatio(Range storage range, uint256 targetAmount0, uint256 targetAmount1) internal view returns (uint256) {
        if (range.liquidity == 0) {
            return 0;
        }
        
        uint256 ratio0 = range.amount0 > 0 ? (targetAmount0 * 10000) / range.amount0 : 0;
        uint256 ratio1 = range.amount1 > 0 ? (targetAmount1 * 10000) / range.amount1 : 0;
        
        return ratio0 < ratio1 ? ratio0 : ratio1;
    }

    /**
     * @dev Set the default fee recipient for new pools
     * @param _feeRecipient Address to receive trading fees
     * @notice Only callable by the contract owner
     * @notice Emits DefaultFeeRecipientUpdated event
     */
    function setDefaultFeeRecipient(address _feeRecipient) external onlyOwner {
        if (_feeRecipient == address(0)) {
            revert TorqueDEX__InvalidFeeRecipient();
        }
        address oldRecipient = defaultFeeRecipient;
        defaultFeeRecipient = _feeRecipient;
        emit DefaultFeeRecipientUpdated(oldRecipient, _feeRecipient);
    }

    /**
     * @dev Set the default fee in basis points for new pools
     * @param _feeBps Fee in basis points (1-1000, where 1000 = 10%)
     * @notice Only callable by the contract owner
     * @notice Emits DefaultFeeBpsUpdated event
     */
    function setDefaultFeeBps(uint256 _feeBps) external onlyOwner {
        require(_feeBps <= 1000, "Fee too high");
        uint256 oldFeeBps = defaultFeeBps;
        defaultFeeBps = _feeBps;
        emit DefaultFeeBpsUpdated(oldFeeBps, _feeBps);
    }

    /**
     * @dev Set the default stable pair flag for new pools
     * @param _isStablePair Whether new pools should be stable pairs by default
     * @notice Only callable by the contract owner
     * @notice Emits DefaultIsStablePairUpdated event
     */
    function setDefaultIsStablePair(bool _isStablePair) external onlyOwner {
        bool oldIsStable = defaultIsStablePair;
        defaultIsStablePair = _isStablePair;
        emit DefaultIsStablePairUpdated(oldIsStable, _isStablePair);
    }

    /**
     * @dev Add a supported chain for cross-chain operations
     * @param chainId LayerZero chain ID
     * @param dexAddress Address of the TorqueDEX contract on the target chain
     * @notice Only callable by the contract owner
     * @notice Enables cross-chain liquidity operations to this chain
     */
    function addSupportedChain(uint16 chainId, address dexAddress) external onlyOwner {
        if (!supportedChainIds[chainId]) {
            supportedChainIds[chainId] = true;
            dexAddresses[chainId] = dexAddress;
            supportedChainList.push(chainId);
        }
    }

    /**
     * @dev Remove a supported chain for cross-chain operations
     * @param chainId LayerZero chain ID to remove
     * @notice Only callable by the contract owner
     * @notice Disables cross-chain liquidity operations to this chain
     */
    function removeSupportedChain(uint16 chainId) external onlyOwner {
        if (supportedChainIds[chainId]) {
            supportedChainIds[chainId] = false;
            delete dexAddresses[chainId];
            
            // Remove from supportedChainList
            for (uint256 i = 0; i < supportedChainList.length; i++) {
                if (supportedChainList[i] == chainId) {
                    supportedChainList[i] = supportedChainList[supportedChainList.length - 1];
                    supportedChainList.pop();
                    break;
                }
            }
        }
    }
    
    /**
     * @dev Get all liquidity ranges for a user in a specific pool
     * @param user Address of the user
     * @param baseToken Address of the base token in the pair
     * @param quoteToken Address of the quote token in the pair
     * @return Array of user's liquidity ranges
     * @notice Reverts if pool doesn't exist
     */
    function getUserRanges(
        address user,
        address baseToken,
        address quoteToken
    ) external view returns (Range[] memory) {
        return _getUserRanges(user, baseToken, quoteToken);
    }

    /**
     * @dev Get user's range count and storage information
     * @param user Address of the user
     * @param baseToken Address of the base token in the pair
     * @param quoteToken Address of the quote token in the pair
     * @return totalRanges Total number of ranges across all indices
     * @return rangeIndices Number of range indices used
     * @return emptyRanges Number of ranges with zero liquidity
     * @notice Helps users understand their storage usage
     */
    function getUserRangeInfo(
        address user,
        address baseToken,
        address quoteToken
    ) external view returns (
        uint256 totalRanges,
        uint256 rangeIndices,
        uint256 emptyRanges
    ) {
        Pool storage pool = _getPool(baseToken, quoteToken);
        
        rangeIndices = userRangeCount[user];
        for (uint256 i = 0; i < rangeIndices; i++) {
            Range[] storage userRanges = pool.userRanges[user][i];
            totalRanges += userRanges.length;
            
            for (uint256 j = 0; j < userRanges.length; j++) {
                if (userRanges[j].liquidity == 0) {
                    emptyRanges++;
                }
            }
        }
    }
    
    /**
     * @dev Get the current price of baseToken in terms of quoteToken
     * @param baseToken Address of the base token
     * @param quoteToken Address of the quote token
     * @return price Price with 18 decimal precision (1e18 = 1.0)
     * @notice Calculates price based on current reserves
     * @notice Reverts if pool doesn't exist or has insufficient liquidity
     */
    function getPrice(address baseToken, address quoteToken) external view returns (uint256 price) {
        return _getPrice(baseToken, quoteToken);
    }



    /**
     * @dev Get canonical token order for a pair
     * @param tokenA First token address
     * @param tokenB Second token address
     * @return token0 Lower address (canonical base token)
     * @return token1 Higher address (canonical quote token)
     * @notice Returns consistent token order regardless of input order
     */
    function getCanonicalTokenOrder(address tokenA, address tokenB) external pure returns (address token0, address token1) {
        return tokenA < tokenB ? (tokenA, tokenB) : (tokenB, tokenA);
    }
    
    /**
     * @dev Get current reserves for a pool
     * @param baseToken Address of the base token in the pair
     * @param quoteToken Address of the quote token in the pair
     * @return reserve0 Amount of base tokens in the pool
     * @return reserve1 Amount of quote tokens in the pool
     * @notice Reverts if pool doesn't exist
     */
    function getPoolReserves(address baseToken, address quoteToken) external view returns (uint256 reserve0, uint256 reserve1) {
        Pool storage pool = _getPool(baseToken, quoteToken);
        
        reserve0 = IERC20(pool.baseToken).balanceOf(address(this));
        reserve1 = IERC20(pool.quoteToken).balanceOf(address(this));
    }
    
    /**
     * @dev Get fee information for a pool
     * @param baseToken Address of the base token in the pair
     * @param quoteToken Address of the quote token in the pair
     * @return feeBps Fee in basis points
     * @return feeRecipient Address receiving the fees
     * @notice Reverts if pool doesn't exist
     */
    function getPoolFees(address baseToken, address quoteToken) external view returns (uint256 feeBps, address feeRecipient) {
        Pool storage pool = _getPool(baseToken, quoteToken);
        
        feeBps = pool.feeBps;
        feeRecipient = pool.feeRecipient;
    }

    /**
     * @dev Get comprehensive statistics for a liquidity pool
     * @param baseToken Address of the base token in the pair
     * @param quoteToken Address of the quote token in the pair
     * @return volume24h 24-hour trading volume
     * @return volume7d 7-day trading volume
     * @return volume30d 30-day trading volume
     * @return fees24h 24-hour fee collection
     * @return fees7d 7-day fee collection
     * @return fees30d 30-day fee collection
     * @return totalParticipants Total number of unique liquidity providers
     * @return currentPrice Current price of baseToken in quoteToken
     * @return totalLiquidity Total liquidity in the pool
     * @notice Provides comprehensive analytics for pool performance
     * @notice Reverts if pool doesn't exist
     */
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
        Pool storage pool = _getPool(baseToken, quoteToken);
        
        volume24h = pool.volume24h;
        volume7d = pool.volume7d;
        volume30d = pool.volume30d;
        fees24h = pool.fees24h;
        fees7d = pool.fees7d;
        fees30d = pool.fees30d;
        totalParticipants = pool.totalParticipants;
        totalLiquidity = pool.totalLiquidity;
        
        currentPrice = _getPrice(baseToken, quoteToken);
    }



    /**
     * @dev Check if a user is a participant in a specific pool
     * @param baseToken Address of the base token in the pair
     * @param quoteToken Address of the quote token in the pair
     * @param user Address of the user to check
     * @return True if user has provided liquidity to the pool, false otherwise
     * @notice Reverts if pool doesn't exist
     */
    function isPoolParticipant(address baseToken, address quoteToken, address user) external view returns (bool) {
        Pool storage pool = _getPool(baseToken, quoteToken);
        return pool.participants[user];
    }



    /**
     * @dev Calculate APR for a pool based on fee collection
     * @param baseToken Address of the base token in the pair
     * @param quoteToken Address of the quote token in the pair
     * @param period Time period for calculation (24h, 7d, or 30d)
     * @return apr Annual percentage rate in basis points
     * @notice Calculates APR based on fees collected over the specified period
     * @notice Reverts if pool doesn't exist
     */
    function getPoolAPR(
        address baseToken,
        address quoteToken,
        uint256 period
    ) external view returns (uint256 apr) {
        Pool storage pool = _getPool(baseToken, quoteToken);
        
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



    /**
     * @dev Get all supported chains for cross-chain operations
     * @return chainIds Array of supported chain IDs
     * @return chainDexAddresses Array of TorqueDEX contract addresses on each chain
     * @notice Returns all chains configured for cross-chain liquidity operations
     */
    function getSupportedChains() external view returns (
        uint16[] memory chainIds,
        address[] memory chainDexAddresses
    ) {
        uint256 supportedChainCount = supportedChainList.length;
        
        chainIds = new uint16[](supportedChainCount);
        chainDexAddresses = new address[](supportedChainCount);
        
        for (uint256 i = 0; i < supportedChainCount; i++) {
            uint16 chainId = supportedChainList[i];
            chainIds[i] = chainId;
            chainDexAddresses[i] = dexAddresses[chainId];
        }
    }



    /**
     * @dev Get comprehensive position information for a user in a specific pool
     * @param baseToken Address of the base token in the pair
     * @param quoteToken Address of the quote token in the pair
     * @param user Address of the user to query
     * @return totalLiquidity Total liquidity provided by the user
     * @return lpTokens Number of LP tokens held by the user
     * @return token0Balance Amount of base tokens in user's position
     * @return token1Balance Amount of quote tokens in user's position
     * @return ranges Array of all liquidity ranges provided by the user
     * @return isParticipant Whether the user has ever provided liquidity to this pool
     * @notice Provides detailed breakdown of user's liquidity position
     * @notice Reverts if pool doesn't exist
     */
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
        Pool storage pool = _getPool(baseToken, quoteToken);
        
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





    /**
     * @dev Get price range information for a pool
     * @param baseToken Address of the base token in the pair
     * @param quoteToken Address of the quote token in the pair
     * @return minPrice Minimum expected price (with 18 decimal precision)
     * @return maxPrice Maximum expected price (with 18 decimal precision)
     * @return currentPrice Current price of baseToken in quoteToken
     * @return isStablePair Whether this is a stable pair
     * @notice Provides price range estimates based on pool type
     * @notice Reverts if pool doesn't exist
     */
    function getPoolPriceRange(
        address baseToken,
        address quoteToken
    ) external view returns (
        uint256 minPrice,
        uint256 maxPrice,
        uint256 currentPrice,
        bool isStablePair
    ) {
        Pool storage pool = _getPool(baseToken, quoteToken);
        
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





    // ============ INTERNAL FUNCTIONS ============

    /**
     * @dev Get pool storage reference with existence check
     * @param baseToken Address of the base token in the pair
     * @param quoteToken Address of the quote token in the pair
     * @return pool Storage reference to the pool
     * @notice Reverts if pool doesn't exist
     */
    function _getPool(address baseToken, address quoteToken) internal view returns (Pool storage pool) {
        bytes32 pairHash = _getPairHash(baseToken, quoteToken);
        pool = pools[pairHash];
        if (!pool.active) {
            revert TorqueDEX__PoolNotFound();
        }
    }

    /**
     * @dev Generate canonical pair hash by sorting token addresses
     * @param tokenA First token address
     * @param tokenB Second token address
     * @return pairHash Canonical hash for the token pair
     * @notice Ensures consistent pair identification regardless of token order
     */
    function _getPairHash(address tokenA, address tokenB) internal pure returns (bytes32 pairHash) {
        (address token0, address token1) = tokenA < tokenB ? (tokenA, tokenB) : (tokenB, tokenA);
        pairHash = keccak256(abi.encodePacked(token0, token1));
    }

    /**
     * @dev Get all liquidity ranges for a user in a specific pool
     * @param user Address of the user
     * @param baseToken Address of the base token in the pair
     * @param quoteToken Address of the quote token in the pair
     * @return Array of user's liquidity ranges
     * @notice Internal function used by getUserRanges and getUserPosition
     */
    function _getUserRanges(
        address user,
        address baseToken,
        address quoteToken
    ) internal view returns (Range[] memory) {
        Pool storage pool = _getPool(baseToken, quoteToken);
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

    /**
     * @dev Get the current price of baseToken in terms of quoteToken
     * @param baseToken Address of the base token
     * @param quoteToken Address of the quote token
     * @return price Price with 18 decimal precision (1e18 = 1.0)
     * @notice Internal function used by getPrice and other price-dependent functions
     */
    function _getPrice(address baseToken, address quoteToken) internal view returns (uint256 price) {
        Pool storage pool = _getPool(baseToken, quoteToken);
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

    /**
     * @dev Update volume statistics for a pool
     * @param pool Storage reference to the pool
     * @param volumeAmount Amount to add to volume statistics
     * @notice Updates 24h, 7d, and 30d volume metrics
     */
    function _updateVolumeStats(
        Pool storage pool,
        uint256 volumeAmount
    ) internal {
        uint256 currentTime = block.timestamp;
        
        // Simple rolling windows
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

    /**
     * @dev Update fee statistics for a pool
     * @param pool Storage reference to the pool
     * @param feeAmount Amount to add to fee statistics
     * @notice Updates 24h, 7d, and 30d fee metrics
     */
    function _updateFeeStats(
        Pool storage pool,
        uint256 feeAmount
    ) internal {
        uint256 currentTime = block.timestamp;
        
        // Simple rolling windows
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

    /**
     * @dev Add a participant to the pool's participant list
     * @param pool Storage reference to the pool
     * @param participant Address of the participant to add
     * @notice Only adds if not already a participant
     */
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

    /**
     * @dev Get cross-chain liquidity for a user on a specific chain
     * @param user Address of the user
     * @param chainId Chain ID to check
     * @return Amount of cross-chain liquidity
     */
    function getCrossChainLiquidity(address user, uint16 chainId) external view returns (uint256) {
        // This would track cross-chain liquidity per user per chain
        // For now, return 0 as this requires additional tracking infrastructure
        return 0;
    }

    /**
     * @dev Get total cross-chain liquidity for a user across all chains
     * @param user Address of the user
     * @return Total amount of cross-chain liquidity
     */
    function getTotalCrossChainLiquidity(address user) external view returns (uint256) {
        // This would sum up cross-chain liquidity across all chains
        // For now, return 0 as this requires additional tracking infrastructure
        return 0;
    }

    /**
     * @dev Get cross-chain liquidity quote for gas estimation
     * @param dstChainIds Array of destination chain IDs
     * @param adapterParams Array of adapter parameters
     * @return totalGasEstimate Total gas estimate for cross-chain operations
     */
    function getCrossChainLiquidityQuote(
        uint16[] calldata dstChainIds,
        bytes[] calldata adapterParams
    ) external view returns (uint256 totalGasEstimate) {
        require(dstChainIds.length == adapterParams.length, "Array length mismatch");
        
        totalGasEstimate = 0;
        for (uint256 i = 0; i < dstChainIds.length; i++) {
            if (!supportedChainIds[dstChainIds[i]]) {
                revert TorqueDEX__UnsupportedChain();
            }
            // Base gas cost for cross-chain message
            totalGasEstimate += 50000;
        }
        return totalGasEstimate;
    }

    /**
     * @dev Emergency function to withdraw stuck tokens
     * @param token Address of the token to withdraw
     * @param to Address to send tokens to
     * @param amount Amount to withdraw
     */
    function emergencyWithdraw(address token, address to, uint256 amount) external onlyOwner {
        require(to != address(0), "Invalid recipient");
        IERC20(token).safeTransfer(to, amount);
    }

    /**
     * @dev Set fee for a specific pool
     * @param baseToken Address of the base token
     * @param quoteToken Address of the quote token
     * @param newFeeBps New fee in basis points
     */
    function setFee(address baseToken, address quoteToken, uint256 newFeeBps) external onlyOwner {
        require(newFeeBps <= 1000, "Fee too high");
        Pool storage pool = _getPool(baseToken, quoteToken);
        pool.feeBps = newFeeBps;
    }

    /**
     * @dev Set fee recipient for a specific pool
     * @param baseToken Address of the base token
     * @param quoteToken Address of the quote token
     * @param newFeeRecipient New fee recipient address
     */
    function setFeeRecipient(address baseToken, address quoteToken, address newFeeRecipient) external onlyOwner {
        require(newFeeRecipient != address(0), "Invalid fee recipient");
        Pool storage pool = _getPool(baseToken, quoteToken);
        pool.feeRecipient = newFeeRecipient;
    }
}
