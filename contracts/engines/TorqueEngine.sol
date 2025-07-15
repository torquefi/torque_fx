// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.30;

import "@openzeppelin/contracts/access/Ownable.sol";
import { ReentrancyGuard } from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import { OracleLib, AggregatorV3Interface } from "../libraries/OracleLib.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { OFTCore } from "@layerzerolabs/lz-evm-oapp-v2/contracts/oft/OFTCore.sol";

abstract contract TorqueEngine is Ownable, ReentrancyGuard, OFTCore {
    using OracleLib for AggregatorV3Interface;

    // Errors
    error TorqueEngine__NeedsMoreThanZero();
    error TorqueEngine__BreaksHealthFactor(uint256 healthFactorValue);
    error TorqueEngine__MintFailed();
    error TorqueEngine__HealthFactorOk();
    error TorqueEngine__HealthFactorNotImproved();
    error TorqueEngine__InsufficientRepayment();
    error TorqueEngine__NoDebtToRepay();
    error TorqueEngine__InvalidInterestRate();

    // Constants
    uint256 internal constant LIQUIDATION_THRESHOLD = 98; // 98% collateral threshold
    uint256 internal constant LIQUIDATION_BONUS = 20; // 20% bonus for liquidators
    uint256 internal constant LIQUIDATION_PRECISION = 100;
    uint256 internal constant MIN_HEALTH_FACTOR = 1e18;
    uint256 internal constant PRECISION = 1e18;
    uint256 internal constant ADDITIONAL_FEED_PRECISION = 1e10;
    uint256 internal constant FEED_PRECISION = 1e8;
    uint256 internal constant SECONDS_PER_YEAR = 365 days;

    // State Variables
    mapping(address => uint256) private s_collateralDeposited;
    mapping(address => uint256) private s_torqueMinted;
    address public treasuryAddress;
    
    // Multi-collateral support
    mapping(address => bool) public supportedCollateral;
    mapping(address => address) public collateralPriceFeeds;
    mapping(address => uint8) public collateralDecimals;
    address[] public supportedCollateralList;

    // APR and fee configuration
    uint256 public baseAPR = 500; // 5% base APR in basis points
    uint256 public maxAPR = 2000; // 20% max APR in basis points
    uint256 public minAPR = 100;  // 1% min APR in basis points
    uint256 public tvlScalingFactor = 1000; // TVL scaling factor in basis points
    uint256 public totalValueLocked; // Total value locked in the engine
    uint256 public mintFee = 50; // 0.5% mint fee in basis points
    uint256 public burnFee = 25;  // 0.25% burn fee in basis points
    uint256 public lastAPRUpdate;
    uint256 public constant APR_UPDATE_INTERVAL = 1 days;

    // Interest tracking
    mapping(address => uint256) private s_interestAccrued;
    mapping(address => uint256) private s_lastInterestUpdate;
    mapping(address => uint256) private s_totalInterestPaid;
    uint256 public totalInterestAccrued;
    uint256 public totalInterestPaid;

    // Events
    event CollateralDeposited(address indexed user, uint256 amount);
    event CollateralRedeemed(address indexed from, address indexed to, uint256 amount);
    event TorqueMinted(address indexed user, uint256 amount);
    event TorqueBurned(address indexed user, uint256 amount);
    event CollateralTokenAdded(address indexed token, uint8 decimals, address priceFeed);
    event CollateralTokenRemoved(address indexed token);
    event APRUpdated(uint256 oldAPR, uint256 newAPR, uint256 tvl);
    event FeeUpdated(string feeType, uint256 oldFee, uint256 newFee);
    event TVLUpdated(uint256 oldTVL, uint256 newTVL);
    event InterestAccrued(address indexed user, uint256 interest, uint256 timestamp);
    event InterestRepaid(address indexed user, uint256 amount, uint256 timestamp);
    event DebtRepaid(address indexed user, uint256 principal, uint256 interest, uint256 timestamp);

    // Modifiers
    modifier moreThanZero(uint256 amount) {
        if (amount == 0) {
            revert TorqueEngine__NeedsMoreThanZero();
        }
        _;
    }

    constructor(address lzEndpoint) OFTCore(18, lzEndpoint, msg.sender) Ownable(msg.sender) {}

    function getCollateralToken() public view virtual returns (IERC20);
    function getPriceFeed() public view virtual returns (AggregatorV3Interface);
    function getTorqueToken() public view virtual returns (IERC20);
    function getCollateralDecimals() public view virtual returns (uint8);
    
    /**
     * @dev Add a new collateral token
     */
    function addCollateralToken(
        address token,
        uint8 decimals,
        address priceFeed
    ) external onlyOwner {
        require(token != address(0), "Invalid token");
        require(!supportedCollateral[token], "Token already supported");
        
        supportedCollateral[token] = true;
        collateralDecimals[token] = decimals;
        collateralPriceFeeds[token] = priceFeed;
        supportedCollateralList.push(token);
        
        emit CollateralTokenAdded(token, decimals, priceFeed);
    }
    
    /**
     * @dev Remove a collateral token
     */
    function removeCollateralToken(address token) external onlyOwner {
        require(supportedCollateral[token], "Token not supported");
        
        supportedCollateral[token] = false;
        
        // Remove from list
        for (uint256 i = 0; i < supportedCollateralList.length; i++) {
            if (supportedCollateralList[i] == token) {
                supportedCollateralList[i] = supportedCollateralList[supportedCollateralList.length - 1];
                supportedCollateralList.pop();
                break;
            }
        }
        
        emit CollateralTokenRemoved(token);
    }
    
    /**
     * @dev Get supported collateral tokens
     */
    function getSupportedCollateral() external view returns (address[] memory) {
        return supportedCollateralList;
    }
    
    /**
     * @dev Check if a token is supported as collateral
     */
    function isCollateralSupported(address token) external view returns (bool) {
        return supportedCollateral[token];
    }
    
    /**
     * @dev Get collateral value in USD for a specific token
     */
    function getCollateralValue(address token, uint256 amount) public view returns (uint256) {
        if (collateralPriceFeeds[token] == address(0)) {
            // No price feed, assume 1:1 with USD (for USDC, USDT)
            return amount;
        }
        
        // Get price from Chainlink feed
        AggregatorV3Interface priceFeed = AggregatorV3Interface(collateralPriceFeeds[token]);
        (, int256 price,,,) = priceFeed.latestRoundData();
        require(price > 0, "Invalid price feed");
        
        // Convert to USD value (assuming price feed is in USD with 8 decimals)
        uint8 tokenDecimals = collateralDecimals[token];
        return (amount * uint256(price)) / (10 ** (8 + tokenDecimals - 6));
    }

    function depositCollateral(uint256 amountCollateral) public moreThanZero(amountCollateral) nonReentrant {
        // CHECKS
        require(amountCollateral > 0, "Amount must be greater than 0");

        // EFFECTS
        s_collateralDeposited[msg.sender] += amountCollateral;

        // INTERACTIONS
        require(getCollateralToken().transferFrom(msg.sender, address(this), amountCollateral), "Transfer failed");
        
        // Update TVL
        _updateTVL();
        
        emit CollateralDeposited(msg.sender, amountCollateral);
    }
    
    function depositCollateral(address collateralToken, uint256 amountCollateral) public moreThanZero(amountCollateral) nonReentrant {
        // CHECKS
        require(amountCollateral > 0, "Amount must be greater than 0");
        require(supportedCollateral[collateralToken], "Collateral token not supported");

        // EFFECTS
        s_collateralDeposited[msg.sender] += amountCollateral;

        // INTERACTIONS
        require(IERC20(collateralToken).transferFrom(msg.sender, address(this), amountCollateral), "Transfer failed");
        
        // Update TVL
        _updateTVL();
        
        emit CollateralDeposited(msg.sender, amountCollateral);
    }

    function _mintTorque(uint256 amountToMint, address to) internal moreThanZero(amountToMint) {
        // CHECKS
        require(amountToMint > 0, "Amount must be greater than 0");
        require(to != address(0), "Invalid recipient");

        // Update interest before minting
        _updateInterest(to);

        // EFFECTS
        s_torqueMinted[to] += amountToMint;
        s_lastInterestUpdate[to] = block.timestamp;

        // INTERACTIONS
        require(getTorqueToken().transfer(to, amountToMint), "Mint failed");
        
        emit TorqueMinted(to, amountToMint);
    }

    function _burnTorque(uint256 amountToBurn, address from) internal {
        // CHECKS
        require(amountToBurn > 0, "Amount must be greater than 0");
        require(from != address(0), "Invalid sender");
        require(s_torqueMinted[from] >= amountToBurn, "Insufficient balance");

        // Update interest before burning
        _updateInterest(from);

        // EFFECTS
        s_torqueMinted[from] -= amountToBurn;

        // INTERACTIONS
        require(getTorqueToken().transferFrom(from, address(this), amountToBurn), "Transfer failed");
        
        emit TorqueBurned(from, amountToBurn);
    }

    /**
     * @dev Repay debt (principal + interest) in Torque currency
     */
    function repayDebt(uint256 amountToRepay) external moreThanZero(amountToRepay) nonReentrant {
        // Update interest first
        _updateInterest(msg.sender);
        
        uint256 totalDebt = s_torqueMinted[msg.sender] + s_interestAccrued[msg.sender];
        require(totalDebt > 0, "No debt to repay");
        require(amountToRepay <= totalDebt, "Repayment exceeds debt");
        
        // Calculate how much goes to principal vs interest
        uint256 interestToRepay = s_interestAccrued[msg.sender];
        uint256 principalToRepay = 0;
        
        if (amountToRepay <= interestToRepay) {
            // Only repaying interest
            s_interestAccrued[msg.sender] -= amountToRepay;
            s_totalInterestPaid[msg.sender] += amountToRepay;
            totalInterestPaid += amountToRepay;
        } else {
            // Repaying interest first, then principal
            s_interestAccrued[msg.sender] = 0;
            s_totalInterestPaid[msg.sender] += interestToRepay;
            totalInterestPaid += interestToRepay;
            
            principalToRepay = amountToRepay - interestToRepay;
            s_torqueMinted[msg.sender] -= principalToRepay;
        }
        
        // Transfer Torque currency from user
        require(getTorqueToken().transferFrom(msg.sender, address(this), amountToRepay), "Transfer failed");
        
        emit DebtRepaid(msg.sender, principalToRepay, interestToRepay, block.timestamp);
    }

    /**
     * @dev Repay only interest in Torque currency
     */
    function repayInterest(uint256 amountToRepay) external moreThanZero(amountToRepay) nonReentrant {
        // Update interest first
        _updateInterest(msg.sender);
        
        require(s_interestAccrued[msg.sender] > 0, "No interest to repay");
        require(amountToRepay <= s_interestAccrued[msg.sender], "Repayment exceeds interest");
        
        s_interestAccrued[msg.sender] -= amountToRepay;
        s_totalInterestPaid[msg.sender] += amountToRepay;
        totalInterestPaid += amountToRepay;
        
        // Transfer Torque currency from user
        require(getTorqueToken().transferFrom(msg.sender, address(this), amountToRepay), "Transfer failed");
        
        emit InterestRepaid(msg.sender, amountToRepay, block.timestamp);
    }

    /**
     * @dev Update interest for a user
     */
    function _updateInterest(address user) internal {
        if (s_torqueMinted[user] == 0) {
            s_lastInterestUpdate[user] = block.timestamp;
            return;
        }
        
        uint256 timeElapsed = block.timestamp - s_lastInterestUpdate[user];
        if (timeElapsed == 0) return;
        
        uint256 currentAPR = _calculateAPR(0);
        uint256 interest = (s_torqueMinted[user] * currentAPR * timeElapsed) / (SECONDS_PER_YEAR * 10000);
        
        if (interest > 0) {
            s_interestAccrued[user] += interest;
            totalInterestAccrued += interest;
            emit InterestAccrued(user, interest, block.timestamp);
        }
        
        s_lastInterestUpdate[user] = block.timestamp;
    }

    /**
     * @dev Get total debt (principal + accrued interest) for a user
     */
    function getTotalDebt(address user) external view returns (uint256) {
        uint256 principal = s_torqueMinted[user];
        uint256 interest = _calculateAccruedInterest(user);
        return principal + interest;
    }

    /**
     * @dev Calculate accrued interest for a user (view function)
     */
    function _calculateAccruedInterest(address user) internal view returns (uint256) {
        if (s_torqueMinted[user] == 0) return 0;
        
        uint256 timeElapsed = block.timestamp - s_lastInterestUpdate[user];
        if (timeElapsed == 0) return s_interestAccrued[user];
        
        uint256 currentAPR = _calculateAPR(0);
        uint256 newInterest = (s_torqueMinted[user] * currentAPR * timeElapsed) / (SECONDS_PER_YEAR * 10000);
        
        return s_interestAccrued[user] + newInterest;
    }

    /**
     * @dev Get user's interest information
     */
    function getUserInterestInfo(address user) external view returns (
        uint256 principal,
        uint256 accruedInterest,
        uint256 totalInterestPaid,
        uint256 lastUpdate,
        uint256 currentAPR
    ) {
        principal = s_torqueMinted[user];
        accruedInterest = _calculateAccruedInterest(user);
        totalInterestPaid = s_totalInterestPaid[user];
        lastUpdate = s_lastInterestUpdate[user];
        currentAPR = _calculateAPR(0);
    }

    function _redeemCollateral(uint256 amountCollateral, address from, address to) internal {
        // CHECKS
        require(amountCollateral > 0, "Amount must be greater than 0");
        require(from != address(0), "Invalid sender");
        require(to != address(0), "Invalid recipient");
        require(s_collateralDeposited[from] >= amountCollateral, "Insufficient collateral");

        // EFFECTS
        s_collateralDeposited[from] -= amountCollateral;

        // INTERACTIONS
        require(getCollateralToken().transfer(to, amountCollateral), "Transfer failed");
        
        emit CollateralRedeemed(from, to, amountCollateral);
    }

    function getCollateralBalanceOfUser(address user) external view returns (uint256) {
        return s_collateralDeposited[user];
    }

    function getTorqueMintedOfUser(address user) external view returns (uint256) {
        return s_torqueMinted[user];
    }

    function getAccountCollateralValue(address user) public view returns (uint256) {
        uint256 amountCollateral = s_collateralDeposited[user];
        return _getUsdValue(amountCollateral);
    }

    function _getUsdValue(uint256 amountCollateral) internal view returns (uint256) {
        (, int256 price,,,) = getPriceFeed().staleCheckLatestRoundData();
        return ((amountCollateral * uint256(price) * ADDITIONAL_FEED_PRECISION) / PRECISION);
    }

    function _healthFactor(address user) internal view returns (uint256) {
        (uint256 totalTorqueMinted, uint256 collateralValueInUsd) = _getAccountInformation(user);
        return _calculateHealthFactor(totalTorqueMinted, collateralValueInUsd);
    }

    function _calculateHealthFactor(uint256 totalTorqueMinted, uint256 collateralValueInUsd) internal pure returns (uint256) {
        if (totalTorqueMinted == 0) return type(uint256).max;
        uint256 collateralAdjustedForThreshold = (collateralValueInUsd * LIQUIDATION_THRESHOLD) / 100;
        return (collateralAdjustedForThreshold * PRECISION) / totalTorqueMinted;
    }

    function _getAccountInformation(address user) internal view returns (uint256, uint256) {
        uint256 totalTorqueMinted = s_torqueMinted[user];
        uint256 collateralValueInUsd = getAccountCollateralValue(user);
        return (totalTorqueMinted, collateralValueInUsd);
    }

    function setTreasuryAddress(address _treasuryAddress) external onlyOwner {
        require(_treasuryAddress != address(0), "Invalid treasury address");
        treasuryAddress = _treasuryAddress;
    }

    function deployReserves(uint256 amount) external onlyOwner nonReentrant {
        // CHECKS
        require(amount > 0, "Amount must be greater than zero");
        require(getCollateralToken().balanceOf(address(this)) >= amount, "Insufficient balance");
        require(treasuryAddress != address(0), "Treasury not set");

        // EFFECTS (none in this case)

        // INTERACTIONS
        require(getCollateralToken().transfer(treasuryAddress, amount), "Transfer failed");
    }

    function mintTorque(uint256 amountToMint, address to) external onlyOwner {
        _mintTorque(amountToMint, to);
    }

    /**
     * @dev Get comprehensive engine statistics for frontend
     */
    function getEngineStats() external view returns (
        uint256 totalCollateralDeposited,
        uint256 totalTorqueMinted,
        uint256 marketCap,
        uint256 volume24h,
        uint256 volume7d,
        uint256 volume30d,
        uint256 liquidityUsd,
        uint256 liquidityPercent,
        uint256 apr7d,
        uint256 apr30d,
        uint256 mintFee,
        uint256 collateralizationRatio,
        uint256 lastUpdate
    ) {
        totalCollateralDeposited = _getTotalCollateralDeposited();
        totalTorqueMinted = _getTotalTorqueMinted();
        marketCap = _calculateMarketCap();
        volume24h = _getVolume24h();
        volume7d = _getVolume7d();
        volume30d = _getVolume30d();
        liquidityUsd = _getLiquidityUsd();
        liquidityPercent = _getLiquidityPercent();
        apr7d = _calculateAPR(7 days);
        apr30d = _calculateAPR(30 days);
        mintFee = _getMintFee();
        collateralizationRatio = _getCollateralizationRatio();
        lastUpdate = block.timestamp;
    }

    /**
     * @dev Get user's comprehensive position data
     */
    function getUserPosition(address user) external view returns (
        uint256 collateralDeposited,
        uint256 torqueMinted,
        uint256 collateralValueUsd,
        uint256 healthFactor,
        uint256 collateralizationRatio,
        uint256 availableCollateral,
        uint256 maxMintable,
        uint256 interestEarned,
        uint256 totalDebt,
        uint256 lastUpdate
    ) {
        collateralDeposited = s_collateralDeposited[user];
        torqueMinted = s_torqueMinted[user];
        collateralValueUsd = getAccountCollateralValue(user);
        healthFactor = _healthFactor(user);
        collateralizationRatio = _getUserCollateralizationRatio(user);
        availableCollateral = _getAvailableCollateral(user);
        maxMintable = _getMaxMintable(user);
        interestEarned = _getInterestEarned(user);
        totalDebt = s_torqueMinted[user] + _calculateAccruedInterest(user);
        lastUpdate = block.timestamp;
    }

    /**
     * @dev Get currency information for frontend
     */
    function getCurrencyInfo() external view returns (
        string memory symbol,
        string memory name,
        uint256 rate,
        uint256 totalSupply,
        uint256 circulatingSupply,
        uint256 marketCap,
        uint256 volume24h,
        uint256 mintFee,
        uint256 burnFee,
        uint256 collateralizationRatio,
        bool isActive
    ) {
        symbol = _getCurrencySymbol();
        name = _getCurrencyName();
        rate = _getCurrentRate();
        totalSupply = _getTotalSupply();
        circulatingSupply = _getCirculatingSupply();
        marketCap = _calculateMarketCap();
        volume24h = _getVolume24h();
        mintFee = _getMintFee();
        burnFee = _getBurnFee();
        collateralizationRatio = _getCollateralizationRatio();
        isActive = _isCurrencyActive();
    }

    /**
     * @dev Get supported collateral information
     */
    function getCollateralInfo() external view returns (
        address[] memory tokens,
        uint256[] memory balances,
        uint256[] memory values,
        uint256 totalValue
    ) {
        tokens = supportedCollateralList;
        balances = new uint256[](tokens.length);
        values = new uint256[](tokens.length);
        
        totalValue = 0;
        for (uint256 i = 0; i < tokens.length; i++) {
            balances[i] = IERC20(tokens[i]).balanceOf(address(this));
            values[i] = getCollateralValue(tokens[i], balances[i]);
            totalValue += values[i];
        }
    }

    // Internal helper functions for statistics
    function _getTotalCollateralDeposited() internal view returns (uint256) {
        // This would need to track total deposits across all users
        // For now, return the contract's collateral balance
        return getCollateralToken().balanceOf(address(this));
    }

    function _getTotalTorqueMinted() internal view returns (uint256) {
        // This would need to track total mints across all users
        // For now, return the contract's torque balance
        return getTorqueToken().balanceOf(address(this));
    }

    function _calculateMarketCap() internal view returns (uint256) {
        uint256 totalSupply = getTorqueToken().totalSupply();
        uint256 price = _getCurrentRate();
        return (totalSupply * price) / PRECISION;
    }

    function _getVolume24h() internal view returns (uint256) {
        // This would need volume tracking
        // For now, return 0
        return 0;
    }

    function _getVolume7d() internal view returns (uint256) {
        // This would need volume tracking
        return 0;
    }

    function _getVolume30d() internal view returns (uint256) {
        // This would need volume tracking
        return 0;
    }

    function _getLiquidityUsd() internal view returns (uint256) {
        // This would need liquidity tracking
        return _getTotalCollateralDeposited();
    }

    function _getLiquidityPercent() internal view returns (uint256) {
        // This would need total market liquidity calculation
        return 100; // Placeholder
    }

    /**
     * @dev Calculate current APR based on TVL and configuration
     */
    function _calculateAPR(uint256 period) internal view returns (uint256) {
        uint256 currentAPR = baseAPR;
        
        // Adjust APR based on TVL (higher TVL = lower APR)
        if (totalValueLocked > 0) {
            uint256 tvlAdjustment = (totalValueLocked * tvlScalingFactor) / PRECISION;
            if (tvlAdjustment > currentAPR) {
                currentAPR = minAPR;
            } else {
                currentAPR = currentAPR > tvlAdjustment ? currentAPR - tvlAdjustment : minAPR;
            }
        }
        
        // Ensure APR is within bounds
        if (currentAPR > maxAPR) currentAPR = maxAPR;
        if (currentAPR < minAPR) currentAPR = minAPR;
        
        return currentAPR;
    }

    /**
     * @dev Update APR based on current TVL
     */
    function updateAPR() external {
        require(block.timestamp >= lastAPRUpdate + APR_UPDATE_INTERVAL, "Too soon to update");
        
        uint256 oldAPR = _calculateAPR(0);
        uint256 newAPR = _calculateAPR(0);
        
        lastAPRUpdate = block.timestamp;
        
        emit APRUpdated(oldAPR, newAPR, totalValueLocked);
    }

    /**
     * @dev Set base APR (admin only)
     */
    function setBaseAPR(uint256 newBaseAPR) external onlyOwner {
        require(newBaseAPR >= minAPR && newBaseAPR <= maxAPR, "APR out of bounds");
        uint256 oldAPR = baseAPR;
        baseAPR = newBaseAPR;
        emit APRUpdated(oldAPR, newBaseAPR, totalValueLocked);
    }

    /**
     * @dev Set APR bounds (admin only)
     */
    function setAPRBounds(uint256 newMinAPR, uint256 newMaxAPR) external onlyOwner {
        require(newMinAPR < newMaxAPR, "Invalid bounds");
        require(newMinAPR >= 0 && newMaxAPR <= 5000, "APR out of reasonable bounds"); // Max 50%
        minAPR = newMinAPR;
        maxAPR = newMaxAPR;
    }

    /**
     * @dev Set TVL scaling factor (admin only)
     */
    function setTVLScalingFactor(uint256 newScalingFactor) external onlyOwner {
        tvlScalingFactor = newScalingFactor;
    }

    /**
     * @dev Set mint fee (admin only)
     */
    function setMintFee(uint256 newMintFee) external onlyOwner {
        require(newMintFee <= 1000, "Fee too high"); // Max 10%
        uint256 oldFee = mintFee;
        mintFee = newMintFee;
        emit FeeUpdated("mint", oldFee, newMintFee);
    }

    /**
     * @dev Set burn fee (admin only)
     */
    function setBurnFee(uint256 newBurnFee) external onlyOwner {
        require(newBurnFee <= 1000, "Fee too high"); // Max 10%
        uint256 oldFee = burnFee;
        burnFee = newBurnFee;
        emit FeeUpdated("burn", oldFee, newBurnFee);
    }

    /**
     * @dev Update TVL when collateral is deposited or withdrawn
     */
    function _updateTVL() internal {
        uint256 oldTVL = totalValueLocked;
        totalValueLocked = _getTotalCollateralDeposited();
        emit TVLUpdated(oldTVL, totalValueLocked);
    }

    function _getMintFee() internal view returns (uint256) {
        return mintFee;
    }

    function _getBurnFee() internal view returns (uint256) {
        return burnFee;
    }

    function _getCollateralizationRatio() internal view returns (uint256) {
        uint256 totalCollateral = _getTotalCollateralDeposited();
        uint256 totalMinted = _getTotalTorqueMinted();
        if (totalMinted == 0) return type(uint256).max;
        return (totalCollateral * PRECISION) / totalMinted;
    }

    function _getUserCollateralizationRatio(address user) internal view returns (uint256) {
        uint256 collateral = s_collateralDeposited[user];
        uint256 minted = s_torqueMinted[user];
        if (minted == 0) return type(uint256).max;
        return (collateral * PRECISION) / minted;
    }

    function _getAvailableCollateral(address user) internal view returns (uint256) {
        // This would calculate available collateral for minting
        return s_collateralDeposited[user];
    }

    function _getMaxMintable(address user) internal view returns (uint256) {
        uint256 collateralValue = getAccountCollateralValue(user);
        // Assuming 150% collateralization requirement
        return (collateralValue * 100) / 150;
    }

    function _getInterestEarned(address user) internal view returns (uint256) {
        return _calculateAccruedInterest(user);
    }

    function _getCurrencySymbol() internal view virtual returns (string memory) {
        return "TORQUE";
    }

    function _getCurrencyName() internal view virtual returns (string memory) {
        return "Torque Token";
    }

    function _getCurrentRate() internal view returns (uint256) {
        // This would get the current exchange rate
        return PRECISION; // 1:1 for now
    }

    function _getTotalSupply() internal view returns (uint256) {
        return getTorqueToken().totalSupply();
    }

    function _getCirculatingSupply() internal view returns (uint256) {
        return getTorqueToken().totalSupply();
    }

    function _isCurrencyActive() internal view returns (bool) {
        return true;
    }
}
