// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import "./TorqueEngine.sol";
import { TorqueXAG } from "../currencies/TorqueXAG.sol";
import { AggregatorV3Interface } from "@chainlink/contracts/src/v0.8/shared/interfaces/AggregatorV3Interface.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract TorqueXAGEngine is TorqueEngine {
    IERC20 private immutable i_collateralToken;
    AggregatorV3Interface private immutable i_priceFeed;
    TorqueXAG private immutable i_torqueXAG;

    constructor(
        address collateralToken,
        address priceFeed,
        address torqueXAG,
        address lzEndpoint
    ) TorqueEngine(lzEndpoint) {
        i_collateralToken = IERC20(collateralToken);
        i_priceFeed = AggregatorV3Interface(priceFeed);
        i_torqueXAG = TorqueXAG(torqueXAG);
    }

    function getCollateralToken() public view override returns (IERC20) {
        return i_collateralToken;
    }

    function getPriceFeed() public view override returns (AggregatorV3Interface) {
        return i_priceFeed;
    }

    function getTorqueToken() public view override returns (IERC20) {
        return i_torqueXAG;
    }

    function getCollateralDecimals() public view override returns (uint8) {
        return 6; // USDC decimals
    }

    function depositCollateralAndMintTorqueXAG(
        uint256 amountCollateral,
        uint256 amountTorqueXAGToMint,
        uint16 dstChainId,
        bytes calldata dstAddress,
        bytes calldata adapterParams
    ) external payable moreThanZero(amountCollateral) {
        // CHECKS
        require(amountCollateral > 0, "Amount must be greater than 0");
        require(amountTorqueXAGToMint > 0, "Mint amount must be greater than 0");
        require(dstChainId > 0, "Invalid destination chain");

        // EFFECTS
        depositCollateral(amountCollateral);

        // INTERACTIONS
        _lzSend(
            dstChainId,
            abi.encode(amountTorqueXAGToMint, msg.sender),
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
        // CHECKS
        require(_payload.length > 0, "Invalid payload");

        // EFFECTS
        (uint256 amountTorqueXAGToMint, address user) = abi.decode(_payload, (uint256, address));
        _mintTorque(amountTorqueXAGToMint, user);
    }

    function redeemCollateralForTorqueXAG(
        uint256 amountCollateral,
        uint256 amountTorqueXAGToBurn,
        uint16 dstChainId,
        bytes calldata dstAddress,
        bytes calldata adapterParams
    ) external moreThanZero(amountCollateral) {
        // CHECKS
        require(amountCollateral > 0, "Amount must be greater than 0");
        require(amountTorqueXAGToBurn > 0, "Burn amount must be greater than 0");
        require(dstChainId > 0, "Invalid destination chain");

        // EFFECTS
        _burnTorque(amountTorqueXAGToBurn, msg.sender);
        _redeemCollateral(amountCollateral, msg.sender, msg.sender);

        // INTERACTIONS
        _lzSend(
            dstChainId,
            abi.encode(amountTorqueXAGToBurn, msg.sender),
            payable(msg.sender),
            address(0),
            adapterParams
        );
    }

    function liquidate(address user, uint256 debtToCover) external moreThanZero(debtToCover) nonReentrant {
        // CHECKS
        require(user != address(0), "Invalid user");
        require(debtToCover > 0, "Debt to cover must be greater than 0");
        uint256 startingUserHealthFactor = _healthFactor(user);
        if (startingUserHealthFactor >= MIN_HEALTH_FACTOR) {
            revert TorqueEngine__HealthFactorOk();
        }

        // Calculate amounts
        uint256 tokenAmountFromDebtCovered = getTokenAmountFromXag(debtToCover);
        uint256 bonusCollateral = (tokenAmountFromDebtCovered * LIQUIDATION_BONUS) / 100;

        // EFFECTS
        _redeemCollateral(tokenAmountFromDebtCovered + bonusCollateral, user, msg.sender);
        _burnTorque(debtToCover, user);

        // Verify health factor improvement
        uint256 endingUserHealthFactor = _healthFactor(user);
        if (endingUserHealthFactor <= startingUserHealthFactor) {
            revert TorqueEngine__HealthFactorNotImproved();
        }
    }

    function getTokenAmountFromXag(uint256 xagAmountInWei) public view returns (uint256) {
        (, int256 price,,,) = i_priceFeed.staleCheckLatestRoundData();
        return ((xagAmountInWei * PRECISION) / (uint256(price) * ADDITIONAL_FEED_PRECISION));
    }
} 