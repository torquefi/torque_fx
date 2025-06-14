// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import "./TorqueEngine.sol";
import { TorqueJPY } from "../currencies/TorqueJPY.sol";
import { AggregatorV3Interface } from "@chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract TorqueJPYEngine is TorqueEngine {
    IERC20 private immutable i_collateralToken;
    AggregatorV3Interface private immutable i_priceFeed;
    TorqueJPY private immutable i_torqueJPY;

    constructor(
        address collateralToken,
        address priceFeed,
        address torqueJPY,
        address lzEndpoint
    ) TorqueEngine(lzEndpoint) {
        i_collateralToken = IERC20(collateralToken);
        i_priceFeed = AggregatorV3Interface(priceFeed);
        i_torqueJPY = TorqueJPY(torqueJPY);
    }

    function getCollateralToken() public view override returns (IERC20) {
        return i_collateralToken;
    }

    function getPriceFeed() public view override returns (AggregatorV3Interface) {
        return i_priceFeed;
    }

    function getTorqueToken() public view override returns (IERC20) {
        return i_torqueJPY;
    }

    function getCollateralDecimals() public view override returns (uint8) {
        return 6; // USDC decimals
    }

    function depositCollateralAndMintTorqueJPY(
        uint256 amountCollateral,
        uint256 amountTorqueJPYToMint,
        uint16 dstChainId,
        bytes calldata dstAddress,
        bytes calldata adapterParams
    ) external payable moreThanZero(amountCollateral) {
        depositCollateral(amountCollateral);
        _lzSend(
            dstChainId,
            abi.encode(amountTorqueJPYToMint, msg.sender),
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
        (uint256 amountTorqueJPYToMint, address user) = abi.decode(_payload, (uint256, address));
        _mintTorque(amountTorqueJPYToMint, user);
    }

    function redeemCollateralForTorqueJPY(
        uint256 amountCollateral,
        uint256 amountTorqueJPYToBurn,
        uint16 dstChainId,
        bytes calldata dstAddress,
        bytes calldata adapterParams
    ) external moreThanZero(amountCollateral) {
        _burnTorque(amountTorqueJPYToBurn, msg.sender);
        _redeemCollateral(amountCollateral, msg.sender, msg.sender);
        _lzSend(
            dstChainId,
            abi.encode(amountTorqueJPYToBurn, msg.sender),
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
        uint256 tokenAmountFromDebtCovered = getTokenAmountFromJpy(debtToCover);
        uint256 bonusCollateral = (tokenAmountFromDebtCovered * LIQUIDATION_BONUS) / 100;
        _redeemCollateral(tokenAmountFromDebtCovered + bonusCollateral, user, msg.sender);
        _burnTorque(debtToCover, user);
        uint256 endingUserHealthFactor = _healthFactor(user);
        if (endingUserHealthFactor <= startingUserHealthFactor) {
            revert TorqueEngine__HealthFactorNotImproved();
        }
    }

    function getTokenAmountFromJpy(uint256 jpyAmountInWei) public view returns (uint256) {
        (, int256 price,,,) = i_priceFeed.staleCheckLatestRoundData();
        return ((jpyAmountInWei * PRECISION) / (uint256(price) * ADDITIONAL_FEED_PRECISION));
    }
} 