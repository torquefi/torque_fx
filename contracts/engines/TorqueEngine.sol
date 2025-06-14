// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import "@openzeppelin/contracts/access/Ownable.sol";
import { ReentrancyGuard } from "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import { OracleLib, AggregatorV3Interface } from "../libraries/OracleLib.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { OFTCore } from "@layerzerolabs/oft-evm/contracts/OFTCore.sol";

abstract contract TorqueEngine is Ownable, ReentrancyGuard, OFTCore {
    using OracleLib for AggregatorV3Interface;

    // Errors
    error TorqueEngine__NeedsMoreThanZero();
    error TorqueEngine__BreaksHealthFactor(uint256 healthFactorValue);
    error TorqueEngine__MintFailed();
    error TorqueEngine__HealthFactorOk();
    error TorqueEngine__HealthFactorNotImproved();

    // Constants
    uint256 private constant LIQUIDATION_THRESHOLD = 98; // 98% collateral threshold
    uint256 private constant LIQUIDATION_BONUS = 20; // 20% bonus for liquidators
    uint256 private constant LIQUIDATION_PRECISION = 100;
    uint256 private constant MIN_HEALTH_FACTOR = 1e18;
    uint256 private constant PRECISION = 1e18;
    uint256 private constant ADDITIONAL_FEED_PRECISION = 1e10;
    uint256 private constant FEED_PRECISION = 1e8;

    // State Variables
    mapping(address => uint256) private s_collateralDeposited;
    mapping(address => uint256) private s_torqueMinted;
    address public treasuryAddress;

    // Events
    event CollateralDeposited(address indexed user, uint256 amount);
    event CollateralRedeemed(address indexed from, address indexed to, uint256 amount);
    event TorqueMinted(address indexed user, uint256 amount);
    event TorqueBurned(address indexed user, uint256 amount);

    // Modifiers
    modifier moreThanZero(uint256 amount) {
        if (amount == 0) {
            revert TorqueEngine__NeedsMoreThanZero();
        }
        _;
    }

    constructor(address lzEndpoint) OFTCore(lzEndpoint) Ownable() {}

    // Abstract functions to be implemented by currency-specific engines
    function getCollateralToken() public view virtual returns (IERC20);
    function getPriceFeed() public view virtual returns (AggregatorV3Interface);
    function getTorqueToken() public view virtual returns (IERC20);
    function getCollateralDecimals() public view virtual returns (uint8);

    // Core functions
    function depositCollateral(uint256 amountCollateral) public moreThanZero(amountCollateral) nonReentrant {
        s_collateralDeposited[msg.sender] += amountCollateral;
        require(getCollateralToken().transferFrom(msg.sender, address(this), amountCollateral), "Transfer failed");
        emit CollateralDeposited(msg.sender, amountCollateral);
    }

    function _mintTorque(uint256 amountToMint, address to) internal moreThanZero(amountToMint) {
        s_torqueMinted[to] += amountToMint;
        require(getTorqueToken().transfer(to, amountToMint), "Mint failed");
        emit TorqueMinted(to, amountToMint);
    }

    function _burnTorque(uint256 amountToBurn, address from) internal {
        require(s_torqueMinted[from] >= amountToBurn, "Insufficient balance");
        s_torqueMinted[from] -= amountToBurn;
        require(getTorqueToken().transferFrom(from, address(this), amountToBurn), "Transfer failed");
        emit TorqueBurned(from, amountToBurn);
    }

    function _redeemCollateral(uint256 amountCollateral, address from, address to) internal {
        require(s_collateralDeposited[from] >= amountCollateral, "Insufficient collateral");
        s_collateralDeposited[from] -= amountCollateral;
        require(getCollateralToken().transfer(to, amountCollateral), "Transfer failed");
        emit CollateralRedeemed(from, to, amountCollateral);
    }

    // View functions
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

    // Admin functions
    function setTreasuryAddress(address _treasuryAddress) external onlyOwner {
        require(_treasuryAddress != address(0), "Invalid treasury address");
        treasuryAddress = _treasuryAddress;
    }

    function deployReserves(uint256 amount) external onlyOwner nonReentrant {
        require(amount > 0, "Amount must be greater than zero");
        require(getCollateralToken().balanceOf(address(this)) >= amount, "Insufficient balance");
        require(getCollateralToken().transfer(treasuryAddress, amount), "Transfer failed");
    }
} 