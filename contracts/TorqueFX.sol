// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";

interface ITorqueAccount {
    function getLeverage(address user, uint256 accountId) external view returns (uint256);
    function userAccounts(address user, uint256 accountId) external view returns (
        uint256 leverage, bool exists, bool isDemo, bool active, string memory username, address referrer
    );
}

interface ITorqueDEX {
    function swap(address inputToken, uint256 inputAmount, uint256 accountId) external returns (uint256 outputAmount);
    function token0() external view returns (address);
    function token1() external view returns (address);
}

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

    IERC20 public immutable usdc;
    ITorqueAccount public torqueAccount;
    ITorqueDEX public torqueDEX;
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
    uint256 public constant POSITION_COOLDOWN = 5 minutes;
    uint256 public constant MAX_DAILY_VOLUME = 1000000e6;
    uint256 public constant MAX_PRICE_IMPACT = 500;
    uint256 public constant MAX_SLIPPAGE = 100;

    mapping(address => mapping(bytes32 => Position)) public positions;
    mapping(bytes32 => address) public priceFeeds;
    mapping(bytes32 => address) public dexPools;
    mapping(address => uint256) public userTotalExposure;
    mapping(address => Order[]) public pendingOrders;
    mapping(address => uint256) public orderCount;
    mapping(address => uint256) public lastTradeTimestamp;
    mapping(address => uint256) public dailyVolume;
    uint256 public lastVolumeReset;
    mapping(address => bool) public addressCircuitBreaker;

    event PositionOpened(address indexed user, bytes32 indexed pair, uint256 collateral, uint256 leverage, bool isLong, uint256 accountId, int256 entryPrice);
    event PositionClosed(address indexed user, bytes32 indexed pair, int256 pnl, uint256 collateralReturned, uint256 feeCharged);
    event PositionLiquidated(address indexed user, bytes32 indexed pair, int256 pnl, uint256 feeCharged, uint256 liquidationAmount, bool isFullLiquidation);
    event OrderPlaced(address indexed user, bytes32 indexed pair, uint256 orderId, OrderType orderType, int256 price, uint256 collateral, bool isLong);
    event OrderFilled(address indexed user, bytes32 indexed pair, uint256 orderId, int256 fillPrice);
    event OrderCancelled(address indexed user, bytes32 indexed pair, uint256 orderId);
    event PositionModified(address indexed user, bytes32 indexed pair, uint256 newCollateral, int256 newEntryPrice);
    event PriceFeedUpdated(bytes32 indexed pair, address feed);
    event LiquidationThresholdsUpdated(uint256 partial, uint256 full);
    event CircuitBreakerToggled(bool active);
    event MaxPositionSizeUpdated(uint256 size);
    event DEXPoolUpdated(bytes32 indexed pair, address pool);
    event AddressCircuitBreakerToggled(address indexed target, bool paused);

    modifier whenAddressNotPaused(address target) {
        require(!addressCircuitBreaker[target], "Address is paused");
        _;
    }

    constructor(
        address _usdc, 
        address _torqueAccount,
        address _torqueDEX
    ) {
        usdc = IERC20(_usdc);
        torqueAccount = ITorqueAccount(_torqueAccount);
        torqueDEX = ITorqueDEX(_torqueDEX);
        feeRecipient = msg.sender;
        lastVolumeReset = block.timestamp;
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
        
        (uint256 leverage, bool exists, bool isDemo, bool active,,) = torqueAccount.userAccounts(msg.sender, accountId);
        require(exists && active && !isDemo, "Invalid account");
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
        Position storage pos = positions[msg.sender][pair];
        require(pos.collateral > 0, "No position");

        if (newCollateral > pos.collateral) {
            uint256 additionalCollateral = newCollateral - pos.collateral;
            require(usdc.transferFrom(msg.sender, address(this), additionalCollateral), "Transfer failed");
            pos.collateral = newCollateral;
        } else if (newCollateral < pos.collateral) {
            uint256 reduction = pos.collateral - newCollateral;
            pos.collateral = newCollateral;
            require(usdc.transfer(msg.sender, reduction), "Transfer failed");
        }

        pos.stopLossPrice = stopLossPrice;
        pos.takeProfitPrice = takeProfitPrice;

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
        bytes32 pair,
        uint256 collateral,
        bool isLong,
        uint256 accountId,
        int256 expectedPrice
    ) external nonReentrant whenAddressNotPaused(msg.sender) {
        require(priceFeeds[pair] != address(0), "Pair not allowed");
        require(dexPools[pair] != address(0), "DEX pool not set");
        require(positions[msg.sender][pair].collateral == 0, "Position exists");

        (uint256 leverage, bool exists, bool isDemo, bool active,,) = torqueAccount.userAccounts(msg.sender, accountId);
        require(exists && active && !isDemo, "Invalid account");
        require(leverage >= 100 && leverage <= 10000, "Invalid leverage");

        _checkPositionSize(collateral, leverage);
        _checkCircuitBreaker();
        _checkTradingLimits(msg.sender, collateral * leverage / 100);

        int256 price = getLatestPrice(pair);
        _checkSlippage(expectedPrice, price, isLong);
        _checkPriceImpact(price, price, isLong);

        uint256 notionalValue = collateral * leverage / 100;
        uint256 fee = (notionalValue * openFeeBps) / 10000;
        uint256 totalCost = collateral + fee;

        require(usdc.transferFrom(msg.sender, address(this), totalCost), "Transfer failed");
        require(usdc.transfer(feeRecipient, fee), "Fee transfer failed");

        if (isLong) {
            ITorqueDEX(dexPools[pair]).swap(address(usdc), collateral, accountId);
        }

        positions[msg.sender][pair] = Position({
            collateral: collateral,
            entryPrice: price,
            isLong: isLong,
            accountId: accountId,
            lastLiquidationAmount: 0,
            stopLossPrice: 0,
            takeProfitPrice: 0
        });

        userTotalExposure[msg.sender] += notionalValue;

        emit PositionOpened(msg.sender, pair, collateral, leverage, isLong, accountId, price);
    }

    function closePosition(
        bytes32 pair,
        int256 expectedPrice
    ) external nonReentrant whenAddressNotPaused(msg.sender) {
        Position storage pos = positions[msg.sender][pair];
        require(pos.collateral > 0, "No position");

        int256 currentPrice = getLatestPrice(pair);
        _checkSlippage(expectedPrice, currentPrice, pos.isLong);

        uint256 notionalValue = pos.collateral * torqueAccount.getLeverage(msg.sender, pos.accountId) / 100;
        uint256 fee = (notionalValue * closeFeeBps) / 10000;
        
        int256 pnl = pos.isLong 
            ? int256((currentPrice - pos.entryPrice) * int256(pos.collateral) / pos.entryPrice)
            : int256((pos.entryPrice - currentPrice) * int256(pos.collateral) / pos.entryPrice);

        uint256 collateralReturned;
        if (pnl > 0) {
            collateralReturned = pos.collateral + uint256(pnl) - fee;
        } else {
            collateralReturned = pos.collateral > uint256(-pnl) + fee 
                ? pos.collateral - uint256(-pnl) - fee 
                : 0;
        }

        if (pos.isLong) {
            ITorqueDEX(dexPools[pair]).swap(address(usdc), collateralReturned, pos.accountId);
        }

        userTotalExposure[msg.sender] -= notionalValue;
        delete positions[msg.sender][pair];

        if (collateralReturned > 0) {
            require(usdc.transfer(msg.sender, collateralReturned), "Transfer failed");
        }
        if (fee > 0) {
            require(usdc.transfer(feeRecipient, fee), "Fee transfer failed");
        }

        emit PositionClosed(msg.sender, pair, pnl, collateralReturned, fee);
    }

    function liquidate(
        address user,
        bytes32 pair
    ) external nonReentrant whenAddressNotPaused(user) {
        Position storage pos = positions[user][pair];
        require(pos.collateral > 0, "No position");

        int256 currentPrice = getLatestPrice(pair);
        uint256 leverage = torqueAccount.getLeverage(user, pos.accountId);
        uint256 notionalValue = pos.collateral * leverage / 100;
        
        int256 pnl = pos.isLong 
            ? int256((currentPrice - pos.entryPrice) * int256(pos.collateral) / pos.entryPrice)
            : int256((pos.entryPrice - currentPrice) * int256(pos.collateral) / pos.entryPrice);

        uint256 healthFactor = _calculateHealthFactor(pos.collateral, notionalValue, pnl);
        require(healthFactor >= fullLiquidationThreshold, "Position not liquidatable");

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

    function _checkTradingLimits(address user, uint256 notionalValue) internal {
        if (block.timestamp - lastVolumeReset >= 1 days) {
            dailyVolume[user] = 0;
            lastVolumeReset = block.timestamp;
        }
        require(dailyVolume[user] + notionalValue <= MAX_DAILY_VOLUME, "Daily volume limit exceeded");
        dailyVolume[user] += notionalValue;
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

    function setLiquidationThresholds(uint256 partial, uint256 full) external onlyOwner {
        require(partial < full, "Invalid thresholds");
        require(full <= 10000, "Threshold too high");
        partialLiquidationThreshold = partial;
        fullLiquidationThreshold = full;
        emit LiquidationThresholdsUpdated(partial, full);
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
}
