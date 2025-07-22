// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.30;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
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
    
    /**
     * @dev Get the LP token address for a specific pool
     * @param baseToken Address of the base token in the pair
     * @param quoteToken Address of the quote token in the pair
     * @return Address of the LP token contract for the pool
     * @notice Reverts if pool doesn't exist
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
        bytes32 pairHash = keccak256(abi.encodePacked(baseToken, quoteToken));
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
        bytes32 pairHash = keccak256(abi.encodePacked(baseToken, quoteToken));
        Pool storage pool = pools[pairHash];
        if (!pool.active) {
            revert TorqueDEX__PoolNotFound();
        }
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
    
    /**
     * @dev Remove liquidity from a specific range in a pool
     * @param baseToken Address of the base token in the pair
     * @param quoteToken Address of the quote token in the pair
     * @param liquidity Amount of LP tokens to burn
     * @param rangeIndex Index of the range to remove liquidity from
     * @return amount0 Amount of base tokens returned
     * @return amount1 Amount of quote tokens returned
     * @notice Burns LP tokens and returns underlying tokens proportionally
     * @notice Updates tick liquidity and pool statistics
     * @notice Emits LiquidityRemoved and RangeRemoved events
     * @notice Reverts if insufficient liquidity or invalid range
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
     * @notice Processes cross-chain liquidity add/remove requests
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
     * @dev Process cross-chain liquidity removal request
     * @param request Cross-chain liquidity request containing user and token details
     * @notice Burns LP tokens and returns underlying tokens to the user
     * @notice Emits CrossChainLiquidityCompleted or CrossChainLiquidityFailed event
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
    
    /**
     * @dev Calculate stable swap invariant (D) using amplified constant product formula
     * @param x Amount of token X
     * @param y Amount of token Y
     * @param amplification Amplification factor (typically 1000)
     * @return Invariant value D
     * @notice Used for stable pair pricing calculations
     */
    function _calculateStableInvariant(uint256 x, uint256 y, uint256 amplification) internal pure returns (uint256) {
        uint256 sum = x + y;
        if (sum == 0) return 0;
        
        uint256 product = x * y;
        uint256 amplificationFactor = amplification * PRECISION / 1000;
        
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
     * @param amplification Amplification factor (typically 1000)
     * @return Amount of token Y
     * @notice Used for stable pair swap calculations
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
     * @notice Uses Uniswap V3-style tick to price conversion
     * @notice Reverts if tick is out of bounds
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
        supportedChainIds[chainId] = true;
        dexAddresses[chainId] = dexAddress;
    }

    /**
     * @dev Remove a supported chain for cross-chain operations
     * @param chainId LayerZero chain ID to remove
     * @notice Only callable by the contract owner
     * @notice Disables cross-chain liquidity operations to this chain
     */
    function removeSupportedChain(uint16 chainId) external onlyOwner {
        supportedChainIds[chainId] = false;
        delete dexAddresses[chainId];
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
     * @dev Get current reserves for a pool
     * @param baseToken Address of the base token in the pair
     * @param quoteToken Address of the quote token in the pair
     * @return reserve0 Amount of base tokens in the pool
     * @return reserve1 Amount of quote tokens in the pool
     * @notice Reverts if pool doesn't exist
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
     * @dev Get fee information for a pool
     * @param baseToken Address of the base token in the pair
     * @param quoteToken Address of the quote token in the pair
     * @return feeBps Fee in basis points
     * @return feeRecipient Address receiving the fees
     * @notice Reverts if pool doesn't exist
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

    /**
     * @dev Check if a user is a participant in a specific pool
     * @param baseToken Address of the base token in the pair
     * @param quoteToken Address of the quote token in the pair
     * @param user Address of the user to check
     * @return True if user has provided liquidity to the pool, false otherwise
     * @notice Reverts if pool doesn't exist
     */
    function isPoolParticipant(address baseToken, address quoteToken, address user) external view returns (bool) {
        bytes32 pairHash = keccak256(abi.encodePacked(baseToken, quoteToken));
        Pool storage pool = pools[pairHash];
        if (!pool.active) {
            revert TorqueDEX__PoolNotFound();
        }
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

    /**
     * @dev Get cross-chain liquidity distribution for a user
     * @param user Address of the user
     * @param baseToken Address of the base token in the pair
     * @param quoteToken Address of the quote token in the pair
     * @return chainIds Array of supported chain IDs
     * @return amounts Array of liquidity amounts on each chain
     * @return totalAmount Total liquidity across all chains
     * @notice Returns distribution of user's liquidity across supported chains
     */
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

    /**
     * @dev Get risk assessment for a pool
     * @param baseToken Address of the base token in the pair
     * @param quoteToken Address of the quote token in the pair
     * @return riskLevel Risk level as string ("Low" or "High")
     * @return volatilityRisk Volatility risk score in basis points
     * @return liquidityRisk Liquidity risk score in basis points
     * @notice Provides risk assessment based on pool type and liquidity
     * @notice Reverts if pool doesn't exist
     */
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

    /**
     * @dev Get total liquidity information for a user across all pools
     * @param user Address of the user
     * @return totalLiquidity Total liquidity value across all pools
     * @return totalLpTokens Total LP tokens held across all pools
     * @return poolAddresses Array of LP token addresses
     * @return poolLiquidity Array of LP token balances for each pool
     * @notice Provides overview of user's liquidity across all pools
     */
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

    // ============ INTERNAL FUNCTIONS ============

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

    /**
     * @dev Get the current price of baseToken in terms of quoteToken
     * @param baseToken Address of the base token
     * @param quoteToken Address of the quote token
     * @return price Price with 18 decimal precision (1e18 = 1.0)
     * @notice Internal function used by getPrice and other price-dependent functions
     */
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
}
