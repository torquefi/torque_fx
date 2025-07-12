// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.28;

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

    // Constants
    uint256 internal constant LIQUIDATION_THRESHOLD = 98; // 98% collateral threshold
    uint256 internal constant LIQUIDATION_BONUS = 20; // 20% bonus for liquidators
    uint256 internal constant LIQUIDATION_PRECISION = 100;
    uint256 internal constant MIN_HEALTH_FACTOR = 1e18;
    uint256 internal constant PRECISION = 1e18;
    uint256 internal constant ADDITIONAL_FEED_PRECISION = 1e10;
    uint256 internal constant FEED_PRECISION = 1e8;

    // State Variables
    mapping(address => uint256) private s_collateralDeposited;
    mapping(address => uint256) private s_torqueMinted;
    address public treasuryAddress;
    
    // Multi-collateral support
    mapping(address => bool) public supportedCollateral;
    mapping(address => address) public collateralPriceFeeds;
    mapping(address => uint8) public collateralDecimals;
    address[] public supportedCollateralList;

    // Events
    event CollateralDeposited(address indexed user, uint256 amount);
    event CollateralRedeemed(address indexed from, address indexed to, uint256 amount);
    event TorqueMinted(address indexed user, uint256 amount);
    event TorqueBurned(address indexed user, uint256 amount);
    event CollateralTokenAdded(address indexed token, uint8 decimals, address priceFeed);
    event CollateralTokenRemoved(address indexed token);

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
        
        emit CollateralDeposited(msg.sender, amountCollateral);
    }

    function _mintTorque(uint256 amountToMint, address to) internal moreThanZero(amountToMint) {
        // CHECKS
        require(amountToMint > 0, "Amount must be greater than 0");
        require(to != address(0), "Invalid recipient");

        // EFFECTS
        s_torqueMinted[to] += amountToMint;

        // INTERACTIONS
        require(getTorqueToken().transfer(to, amountToMint), "Mint failed");
        
        emit TorqueMinted(to, amountToMint);
    }

    function _burnTorque(uint256 amountToBurn, address from) internal {
        // CHECKS
        require(amountToBurn > 0, "Amount must be greater than 0");
        require(from != address(0), "Invalid sender");
        require(s_torqueMinted[from] >= amountToBurn, "Insufficient balance");

        // EFFECTS
        s_torqueMinted[from] -= amountToBurn;

        // INTERACTIONS
        require(getTorqueToken().transferFrom(from, address(this), amountToBurn), "Transfer failed");
        
        emit TorqueBurned(from, amountToBurn);
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
}
