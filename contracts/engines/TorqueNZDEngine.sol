// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import "./TorqueEngine.sol";
import { TorqueNZD } from "../currencies/TorqueNZD.sol";
import { AggregatorV3Interface } from "@chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract TorqueNZDEngine is TorqueEngine {
    IERC20 private immutable i_collateralToken;
    AggregatorV3Interface private immutable i_priceFeed;
    TorqueNZD private immutable i_torqueNZD;

    constructor(
        address collateralToken,
        address priceFeed,
        address torqueNZD,
        address lzEndpoint
    ) TorqueEngine(lzEndpoint) {
        i_collateralToken = IERC20(collateralToken);
        i_priceFeed = AggregatorV3Interface(priceFeed);
        i_torqueNZD = TorqueNZD(torqueNZD);
    }

    function getCollateralToken() public view override returns (IERC20) {
        return i_collateralToken;
    }

    function getPriceFeed() public view override returns (AggregatorV3Interface) {
        return i_priceFeed;
    }

    function getTorqueToken() public view override returns (IERC20) {
        return i_torqueNZD;
    }

    function getCollateralDecimals() public view override returns (uint8) {
        return 6; // USDC decimals
    }

    function depositCollateralAndMintTorqueNZD(
        uint256 amountCollateral,
        uint256 amountTorqueNZDToMint,
        uint16 dstChainId,
        bytes calldata dstAddress,
        bytes calldata adapterParams
    ) external payable moreThanZero(amountCollateral) {
        depositCollateral(amountCollateral);
        _lzSend(
            dstChainId,
            abi.encode(amountTorqueNZDToMint, msg.sender),
            payable(msg.sender),
            address(0),
            adapterParams
        );
    }

    function _nonblockingLzReceive(
        uint16,
        bytes memory,
        uint64,
        bytes memory _payload
    ) internal override {
        (uint256 amountTorqueNZDToMint, address user) = abi.decode(_payload, (uint256, address));
        _mintTorque(amountTorqueNZDToMint, user);
    }

    function redeemCollateralForTorqueNZD(
        uint256 amountCollateral,
        uint256 amountTorqueNZDToBurn,
        uint16 dstChainId,
        bytes calldata dstAddress,
        bytes calldata adapterParams
    ) external moreThanZero(amountCollateral) {
        _burnTorque(amountTorqueNZDToBurn, msg.sender);
        _redeemCollateral(amountCollateral, msg.sender, msg.sender);
        _lzSend(
            dstChainId,
            abi.encode(amountTorqueNZDToBurn, msg.sender),
            payable(msg.sender),
            address(0),
            adapterParams
        );
    }

    function liquidate(address user, uint256 debtToCover) external moreThanZero(debtToCover) nonReentrant {
        uint256 startingUserHealthFactor = _healthFactor(user);
        if (startingUserHealthFactor >= MIN_HEALTH_FACTOR) {
            revert TorqueEngine__HealthFactorOk();
        }
        uint256 tokenAmountFromDebtCovered = getTokenAmountFromNzd(debtToCover);
        uint256 bonusCollateral = (tokenAmountFromDebtCovered * LIQUIDATION_BONUS) / 100;
        _redeemCollateral(tokenAmountFromDebtCovered + bonusCollateral, user, msg.sender);
        _burnTorque(debtToCover, user);
        uint256 endingUserHealthFactor = _healthFactor(user);
        if (endingUserHealthFactor <= startingUserHealthFactor) {
            revert TorqueEngine__HealthFactorNotImproved();
        }
    }

    function getTokenAmountFromNzd(uint256 nzdAmountInWei) public view returns (uint256) {
        (, int256 price,,,) = i_priceFeed.staleCheckLatestRoundData();
        return ((nzdAmountInWei * PRECISION) / (uint256(price) * ADDITIONAL_FEED_PRECISION));
    }
} 