// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.28;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@chainlink/contracts/src/v0.8/shared/interfaces/AggregatorV3Interface.sol";
import "./4337/TorqueAccount.sol";

interface ITorqueAccount {
    function getLeverage(address user, uint256 accountId) external view returns (uint256);
    function userAccounts(address user, uint256 accountId) external view returns (
        uint256 leverage, bool exists, bool active, string memory username, address referrer
    );
    function isValidAccount(address user, uint256 accountId) external view returns (bool);
    function openPosition(
        uint256 accountId,
        uint256 positionId,
        address baseToken,
        address quoteToken,
        uint256 collateral,
        uint256 positionSize,
        uint256 entryPrice,
        bool isLong
    ) external;
    function closePosition(
        uint256 accountId,
        uint256 positionId,
        int256 pnl
    ) external;
}

// ITorqueDEX interface is already defined in TorqueAccount.sol

contract TorqueFX is Ownable, ReentrancyGuard {
    enum OrderType { MARKET, LIMIT, STOP_LOSS, TAKE_PROFIT }
    enum OrderStatus { PENDING, FILLED, CANCELLED, EXPIRED }

    struct Position {
        uint256 collateral;
        int256 entryPrice;
        bool isLong;
        uint256 accountId;
        uint256 lastLiquidationAmount;
        uint256 stopLossPrice;
        uint256 takeProfitPrice;
        uint256 positionSize;
        uint256 positionId;
        uint256 closePrice;
        int256 pnl;
        bool isOpen;
        address baseToken;
        address quoteToken;
    }

    struct Order {
        bytes32 pair;
        uint256 collateral;
        int256 price;
        bool isLong;
        uint256 accountId;
        OrderType orderType;
        OrderStatus status;
        uint256 expiry;
        uint256 leverage;
    }

    struct PoolPosition {
        uint256 longExposure;
        uint256 shortExposure;
        uint256 totalCollateral;
        uint256 lastHedgeTime;
        uint256 lastHedgePrice;
    }

    struct MarketData {
        uint256 longInterest;
        uint256 shortInterest;
        uint256 totalVolume;
        uint256 lastUpdate;
    }

    IERC20 public immutable usdc;
    ITorqueAccount public immutable accountContract;
    ITorqueDEX public immutable dexContract;
    address public feeRecipient;

    uint256 public openFeeBps = 5;
    uint256 public closeFeeBps = 5;
    uint256 public constant PRICE_FEED_TIMEOUT = 1 hours;
    uint256 public constant BASIS_POINTS = 10000;
    uint256 public constant MAX_PENDING_ORDERS = 10;
    uint256 public constant ORDER_EXPIRY = 24 hours;
    uint256 public partialLiquidationThreshold = 8500;
    uint256 public fullLiquidationThreshold = 9500;
    uint256 public maxPositionSize;
    uint256 public constant LIQUIDATION_INCENTIVE = 1000;
    bool public circuitBreaker;
    uint256 public lastPriceUpdate;
    uint256 public constant MAX_PRICE_IMPACT = 500;
    uint256 public constant MAX_SLIPPAGE = 100;

    mapping(address => mapping(bytes32 => Position)) public positions;
    mapping(bytes32 => address) public priceFeeds;
    mapping(bytes32 => address) public dexPools;
    mapping(address => uint256) public userTotalExposure;
    mapping(address => Order[]) public pendingOrders;
    mapping(address => uint256) public orderCount;
    mapping(address => bool) public addressCircuitBreaker;
    mapping(bytes32 => PoolPosition) public poolPositions;
    mapping(bytes32 => MarketData) public marketData;
    mapping(bytes32 => uint256) public poolLiquidity;
    mapping(bytes32 => uint256) public maxPoolExposure;
    mapping(bytes32 => uint256) public hedgeThreshold;

    event PositionOpened(address indexed user, bytes32 indexed pair, uint256 collateral, uint256 leverage, bool isLong, uint256 accountId, int256 entryPrice);
    event PositionClosed(address indexed user, bytes32 indexed pair, int256 pnl, uint256 collateralReturned, uint256 feeCharged);
    event PositionLiquidated(address indexed user, bytes32 indexed pair, int256 pnl, uint256 feeCharged, uint256 liquidationAmount, bool isFullLiquidation);
    event OrderPlaced(address indexed user, bytes32 indexed pair, uint256 orderId, OrderType orderType, int256 price, uint256 collateral, bool isLong);
    event OrderFilled(address indexed user, bytes32 indexed pair, uint256 orderId, int256 fillPrice);
    event OrderCancelled(address indexed user, bytes32 indexed pair, uint256 orderId);
    event PositionModified(address indexed user, bytes32 indexed pair, uint256 newCollateral, int256 newEntryPrice);
    event PriceFeedUpdated(bytes32 indexed pair, address feed);
    event LiquidationThresholdsUpdated(uint256 partialThreshold, uint256 full);
    event CircuitBreakerToggled(bool active);
    event MaxPositionSizeUpdated(uint256 size);
    event DEXPoolUpdated(bytes32 indexed pair, address pool);
    event AddressCircuitBreakerToggled(address indexed target, bool paused);
    event PoolPositionUpdated(bytes32 indexed pair, uint256 longExposure, uint256 shortExposure, uint256 totalCollateral);
    event MarketDataUpdated(bytes32 indexed pair, uint256 longInterest, uint256 shortInterest, uint256 totalVolume);
    event PoolLiquidityUpdated(bytes32 indexed pair, uint256 amount);
    event PositionHedged(bytes32 indexed pair, uint256 amount, bool isLong);

    modifier whenAddressNotPaused(address target) {
        require(!addressCircuitBreaker[target], "Address is paused");
        _;
    }

    constructor(
        address _accountContract,
        address _dexContract,
        address _usdc
    ) Ownable(msg.sender) {
        accountContract = ITorqueAccount(_accountContract);
        dexContract = ITorqueDEX(_dexContract);
        usdc = IERC20(_usdc);
        feeRecipient = msg.sender;
    }

    function setDEXPool(bytes32 pair, address pool) external onlyOwner {
        require(pool != address(0), "Invalid pool");
        dexPools[pair] = pool;
        emit DEXPoolUpdated(pair, pool);
    }

    function placeOrder(
        bytes32 pair,
        uint256 collateral,
        int256 price,
        bool isLong,
        uint256 accountId,
        OrderType orderType
    ) external nonReentrant {
        require(priceFeeds[pair] != address(0), "Pair not allowed");
        require(orderCount[msg.sender] < MAX_PENDING_ORDERS, "Too many pending orders");
        
        (uint256 leverage, bool exists, bool active,,) = accountContract.userAccounts(msg.sender, accountId);
        require(exists && active, "Invalid account");
        require(leverage >= 100 && leverage <= 10000, "Invalid leverage");

        _checkPositionSize(collateral, leverage);
        _checkCircuitBreaker();

        uint256 orderId = pendingOrders[msg.sender].length;
        pendingOrders[msg.sender].push(Order({
            pair: pair,
            collateral: collateral,
            price: price,
            isLong: isLong,
            accountId: accountId,
            orderType: orderType,
            status: OrderStatus.PENDING,
            expiry: block.timestamp + ORDER_EXPIRY,
            leverage: leverage
        }));

        orderCount[msg.sender]++;
        emit OrderPlaced(msg.sender, pair, orderId, orderType, price, collateral, isLong);
    }

    function cancelOrder(uint256 orderId) external nonReentrant {
        require(orderId < pendingOrders[msg.sender].length, "Invalid order");
        Order storage order = pendingOrders[msg.sender][orderId];
        require(order.status == OrderStatus.PENDING, "Order not pending");
        
        order.status = OrderStatus.CANCELLED;
        orderCount[msg.sender]--;
        emit OrderCancelled(msg.sender, order.pair, orderId);
    }

    function modifyPosition(
        bytes32 pair,
        uint256 newCollateral,
        uint256 stopLossPrice,
        uint256 takeProfitPrice
    ) external nonReentrant {
        // CHECKS
        Position storage pos = positions[msg.sender][pair];
        require(pos.collateral > 0, "No position");

        // EFFECTS
        if (newCollateral > pos.collateral) {
            uint256 additionalCollateral = newCollateral - pos.collateral;
            pos.collateral = newCollateral;
            pos.stopLossPrice = stopLossPrice;
            pos.takeProfitPrice = takeProfitPrice;

            // INTERACTIONS
            require(usdc.transferFrom(msg.sender, address(this), additionalCollateral), "Transfer failed");
        } else if (newCollateral < pos.collateral) {
            uint256 reduction = pos.collateral - newCollateral;
            pos.collateral = newCollateral;
            pos.stopLossPrice = stopLossPrice;
            pos.takeProfitPrice = takeProfitPrice;

            // INTERACTIONS
            require(usdc.transfer(msg.sender, reduction), "Transfer failed");
        } else {
            pos.stopLossPrice = stopLossPrice;
            pos.takeProfitPrice = takeProfitPrice;
        }

        emit PositionModified(msg.sender, pair, newCollateral, pos.entryPrice);
    }

    function _checkPriceImpact(int256 currentPrice, int256 executionPrice, bool isLong) internal pure {
        uint256 impact = isLong 
            ? uint256((executionPrice - currentPrice) * 10000 / currentPrice)
            : uint256((currentPrice - executionPrice) * 10000 / currentPrice);
        require(impact <= MAX_PRICE_IMPACT, "Price impact too high");
    }

    function _checkSlippage(int256 expectedPrice, int256 actualPrice, bool isLong) internal pure {
        uint256 slippage = isLong
            ? uint256((actualPrice - expectedPrice) * 10000 / expectedPrice)
            : uint256((expectedPrice - actualPrice) * 10000 / expectedPrice);
        require(slippage <= MAX_SLIPPAGE, "Slippage too high");
    }

    function openPosition(
        uint256 accountId,
        address baseToken,
        address quoteToken,
        uint256 collateral,
        uint256 leverage,
        bool isLong
    ) external returns (uint256 positionId) {
        // CHECKS
        require(accountContract.isValidAccount(msg.sender, accountId), "Invalid account");
        require(collateral > 0, "Invalid collateral");
        require(leverage >= 1 && leverage <= 10000, "Invalid leverage");

        // Calculate position size
        uint256 positionSize = collateral * leverage;
        
        // Get current price from DEX
        uint256 price = dexContract.getPrice(baseToken, quoteToken);
        require(price > 0, "Invalid price");

        // Calculate required tokens for position
        uint256 requiredTokens = isLong ? 
            (positionSize * 1e18) / price : 
            (positionSize * price) / 1e18;

        // EFFECTS
        positionId = _createPosition(
            accountId,
            baseToken,
            quoteToken,
            collateral,
            positionSize,
            price,
            isLong
        );

        // Update account position
        accountContract.openPosition(
            accountId,
            positionId,
            baseToken,
            quoteToken,
            collateral,
            positionSize,
            price,
            isLong
        );
        
        // Update user exposure
        userTotalExposure[msg.sender]++;

        // INTERACTIONS
        usdc.transferFrom(msg.sender, address(this), collateral);

        // Execute swap through DEX
        uint256 tokensReceived = dexContract.swap(
            isLong ? quoteToken : baseToken,
            requiredTokens,
            accountId
        );

        bytes32 pair = keccak256(abi.encodePacked(baseToken, quoteToken));
        emit PositionOpened(
            msg.sender,
            pair,
            collateral,
            leverage,
            isLong,
            accountId,
            int256(price)
        );
    }

    function _createPosition(
        uint256 accountId,
        address baseToken,
        address quoteToken,
        uint256 collateral,
        uint256 positionSize,
        uint256 price,
        bool isLong
    ) internal returns (uint256 positionId) {
        bytes32 pair = keccak256(abi.encodePacked(baseToken, quoteToken));
        positionId = userTotalExposure[msg.sender]; // Use a counter instead of array length
        positions[msg.sender][pair] = Position({
            collateral: collateral,
            entryPrice: int256(price),
            isLong: isLong,
            accountId: accountId,
            lastLiquidationAmount: 0,
            stopLossPrice: 0,
            takeProfitPrice: 0,
            positionSize: positionSize,
            positionId: positionId,
            closePrice: 0,
            pnl: 0,
            isOpen: true,
            baseToken: baseToken,
            quoteToken: quoteToken
        });
        return positionId;
    }

    function _checkAndHedgePool(bytes32 pair) internal {
        // CHECKS
        PoolPosition storage pool = poolPositions[pair];
        uint256 netExposure;
        bool isLong;

        if (pool.longExposure > pool.shortExposure) {
            netExposure = pool.longExposure - pool.shortExposure;
            isLong = true;
        } else {
            netExposure = pool.shortExposure - pool.longExposure;
            isLong = false;
        }

        if (netExposure > hedgeThreshold[pair]) {
            // Calculate hedge amount
            uint256 hedgeAmount = netExposure - hedgeThreshold[pair];
            
            // EFFECTS
            pool.lastHedgeTime = block.timestamp;
            pool.lastHedgePrice = uint256(getLatestPrice(pair));

            // INTERACTIONS
            if (isLong) {
                // Hedge by going short in real market
                ITorqueDEX(dexPools[pair]).swap(address(usdc), hedgeAmount, 0);
            } else {
                // Hedge by going long in real market
                ITorqueDEX(dexPools[pair]).swap(address(usdc), hedgeAmount, 0);
            }

            emit PositionHedged(pair, hedgeAmount, isLong);
        }
    }

    function setHedgeThreshold(bytes32 pair, uint256 threshold) external onlyOwner {
        hedgeThreshold[pair] = threshold;
    }

    function setMaxPoolExposure(bytes32 pair, uint256 maxExposure) external onlyOwner {
        maxPoolExposure[pair] = maxExposure;
    }

    function addPoolLiquidity(bytes32 pair, uint256 amount) external onlyOwner {
        // CHECKS
        require(amount > 0, "Invalid amount");

        // EFFECTS
        poolLiquidity[pair] += amount;

        // INTERACTIONS
        require(usdc.transferFrom(msg.sender, address(this), amount), "Transfer failed");
        
        emit PoolLiquidityUpdated(pair, poolLiquidity[pair]);
    }

    function removePoolLiquidity(bytes32 pair, uint256 amount) external onlyOwner {
        // CHECKS
        require(amount <= poolLiquidity[pair], "Insufficient liquidity");
        require(amount > 0, "Invalid amount");

        // EFFECTS
        poolLiquidity[pair] -= amount;

        // INTERACTIONS
        require(usdc.transfer(msg.sender, amount), "Transfer failed");
        
        emit PoolLiquidityUpdated(pair, poolLiquidity[pair]);
    }

    function closePosition(
        uint256 accountId,
        bytes32 pair
    ) external returns (uint256 pnl) {
        // CHECKS
        require(accountContract.isValidAccount(msg.sender, accountId), "Invalid account");
        
        Position storage position = positions[msg.sender][pair];
        require(position.accountId == accountId, "Position not found");
        require(position.isOpen, "Position closed");

        // Get current price from DEX
        uint256 currentPrice = dexContract.getPrice(
            position.baseToken,
            position.quoteToken
        );
        require(currentPrice > 0, "Invalid price");

        // Calculate PnL
        pnl = uint256(_calculatePnL(
            position,
            int256(currentPrice)
        ));

        // Calculate tokens to swap
        uint256 tokensToSwap = position.isLong ?
            (position.positionSize * 1e18) / uint256(position.entryPrice) :
            (position.positionSize * uint256(position.entryPrice)) / 1e18;

        // EFFECTS
        position.isOpen = false;
        position.closePrice = currentPrice;
        position.pnl = int256(pnl);

        // Update account position
        accountContract.closePosition(
            accountId,
            position.positionId,
            int256(pnl)
        );

        // INTERACTIONS
        // Execute reverse swap through DEX
        uint256 tokensReceived = dexContract.swap(
            position.isLong ? position.baseToken : position.quoteToken,
            tokensToSwap,
            accountId
        );

        // Transfer funds back to account
        if (pnl > 0) {
            usdc.transfer(msg.sender, pnl);
        }

        emit PositionClosed(
            msg.sender,
            pair,
            int256(pnl),
            pnl,
            0
        );
    }

    function liquidate(
        address user,
        bytes32 pair
    ) external nonReentrant whenAddressNotPaused(user) {
        // CHECKS
        Position storage pos = positions[user][pair];
        require(pos.collateral > 0, "No position");

        int256 currentPrice = getLatestPrice(pair);
        uint256 leverage = accountContract.getLeverage(user, pos.accountId);
        uint256 notionalValue = pos.collateral * leverage / 100;
        
        int256 pnl = pos.isLong 
            ? int256((currentPrice - pos.entryPrice) * int256(pos.collateral) / pos.entryPrice)
            : int256((pos.entryPrice - currentPrice) * int256(pos.collateral) / pos.entryPrice);

        uint256 healthFactor = _calculateHealthFactor(pos.collateral, notionalValue, pnl);
        require(healthFactor >= fullLiquidationThreshold, "Position not liquidatable");

        // EFFECTS
        uint256 fee = (notionalValue * closeFeeBps) / 10000;
        uint256 liquidationAmount = pos.collateral;
        bool isFullLiquidation = healthFactor >= fullLiquidationThreshold;

        if (!isFullLiquidation) {
            liquidationAmount = pos.collateral * (healthFactor - partialLiquidationThreshold) / (fullLiquidationThreshold - partialLiquidationThreshold);
            pos.lastLiquidationAmount = liquidationAmount;
            pos.collateral -= liquidationAmount;
        } else {
            delete positions[user][pair];
        }

        uint256 liquidatorReward = (liquidationAmount * LIQUIDATION_INCENTIVE) / 10000;
        uint256 remainingAmount = liquidationAmount - liquidatorReward - fee;

        userTotalExposure[user] -= notionalValue;

        // INTERACTIONS
        if (remainingAmount > 0) {
            require(usdc.transfer(user, remainingAmount), "Transfer failed");
        }
        if (liquidatorReward > 0) {
            require(usdc.transfer(msg.sender, liquidatorReward), "Transfer failed");
        }
        if (fee > 0) {
            require(usdc.transfer(feeRecipient, fee), "Fee transfer failed");
        }

        emit PositionLiquidated(user, pair, pnl, fee, liquidationAmount, isFullLiquidation);
    }

    function _calculateHealthFactor(
        uint256 collateral,
        uint256 notionalValue,
        int256 pnl
    ) internal pure returns (uint256) {
        if (pnl >= 0) return 10000;
        uint256 loss = uint256(-pnl);
        if (loss >= collateral) return 0;
        return ((collateral - loss) * 10000) / collateral;
    }

    function _checkPositionSize(uint256 collateral, uint256 leverage) internal view {
        uint256 notionalValue = collateral * leverage / 100;
        require(notionalValue <= maxPositionSize, "Position too large");
    }

    function _checkCircuitBreaker() internal view {
        require(!circuitBreaker, "Circuit breaker active");
    }

    function getLatestPrice(bytes32 pair) public view returns (int256) {
        require(priceFeeds[pair] != address(0), "Price feed not set");
        AggregatorV3Interface priceFeed = AggregatorV3Interface(priceFeeds[pair]);
        (, int256 price,, uint256 updatedAt,) = priceFeed.latestRoundData();
        require(block.timestamp - updatedAt <= PRICE_FEED_TIMEOUT, "Price feed stale");
        return price;
    }

    function setPriceFeed(bytes32 pair, address feed) external onlyOwner {
        require(feed != address(0), "Invalid feed");
        priceFeeds[pair] = feed;
        emit PriceFeedUpdated(pair, feed);
    }

    function setLiquidationThresholds(uint256 partialThreshold, uint256 full) external onlyOwner {
        require(partialThreshold < full, "Invalid thresholds");
        require(full <= 10000, "Threshold too high");
        partialLiquidationThreshold = partialThreshold;
        fullLiquidationThreshold = full;
        emit LiquidationThresholdsUpdated(partialThreshold, full);
    }

    function toggleCircuitBreaker() external onlyOwner {
        circuitBreaker = !circuitBreaker;
        emit CircuitBreakerToggled(circuitBreaker);
    }

    function setMaxPositionSize(uint256 size) external onlyOwner {
        maxPositionSize = size;
        emit MaxPositionSizeUpdated(size);
    }

    function setFeeRecipient(address recipient) external onlyOwner {
        require(recipient != address(0), "Invalid recipient");
        feeRecipient = recipient;
    }

    function setFees(uint256 open, uint256 close) external onlyOwner {
        require(open <= 100 && close <= 100, "Fees too high");
        openFeeBps = open;
        closeFeeBps = close;
    }

    function toggleAddressCircuitBreaker(address target) external onlyOwner {
        addressCircuitBreaker[target] = !addressCircuitBreaker[target];
        emit AddressCircuitBreakerToggled(target, addressCircuitBreaker[target]);
    }

    function _calculatePnL(Position storage position, int256 currentPrice) internal view returns (int256 pnl) {
        if (position.isLong) {
            pnl = int256((currentPrice - position.entryPrice) * int256(position.collateral) / position.entryPrice);
        } else {
            pnl = int256((position.entryPrice - currentPrice) * int256(position.collateral) / position.entryPrice);
        }
        return pnl;
    }
}
