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

    constructor(address lzEndpoint) OFTCore(18, lzEndpoint, msg.sender) Ownable(msg.sender) {}

    function getCollateralToken() public view virtual returns (IERC20);
    function getPriceFeed() public view virtual returns (AggregatorV3Interface);
    function getTorqueToken() public view virtual returns (IERC20);
    function getCollateralDecimals() public view virtual returns (uint8);

    function depositCollateral(uint256 amountCollateral) public moreThanZero(amountCollateral) nonReentrant {
        // CHECKS
        require(amountCollateral > 0, "Amount must be greater than 0");

        // EFFECTS
        s_collateralDeposited[msg.sender] += amountCollateral;

        // INTERACTIONS
        require(getCollateralToken().transferFrom(msg.sender, address(this), amountCollateral), "Transfer failed");
        
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
