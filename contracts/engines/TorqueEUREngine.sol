// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import "./TorqueEngine.sol";
import { TorqueEUR } from "../currencies/TorqueEUR.sol";
import { AggregatorV3Interface } from "@chainlink/contracts/src/v0.8/shared/interfaces/AggregatorV3Interface.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";

contract TorqueEUREngine is TorqueEngine {
    IERC20 private immutable i_collateralToken;
    AggregatorV3Interface private immutable i_priceFeed;
    TorqueEUR private immutable i_torqueEUR;

    constructor(
        address collateralToken,
        address priceFeed,
        address torqueEUR,
        address lzEndpoint
    ) TorqueEngine(lzEndpoint) {
        i_collateralToken = IERC20(collateralToken);
        i_priceFeed = AggregatorV3Interface(priceFeed);
        i_torqueEUR = TorqueEUR(torqueEUR);
    }

    function getCollateralToken() public view override returns (IERC20) {
        return i_collateralToken;
    }

    function getPriceFeed() public view override returns (AggregatorV3Interface) {
        return i_priceFeed;
    }

    function getTorqueToken() public view override returns (IERC20) {
        return i_torqueEUR;
    }

    function getCollateralDecimals() public view override returns (uint8) {
        return 6; // USDC decimals
    }

    function depositCollateralAndMintTorqueEUR(
        uint256 amountCollateral,
        uint256 amountTorqueEURToMint,
        uint16 dstChainId,
        bytes calldata dstAddress,
        bytes calldata adapterParams
    ) external payable moreThanZero(amountCollateral) {
        // CHECKS
        require(amountCollateral > 0, "Amount must be greater than 0");
        require(amountTorqueEURToMint > 0, "Mint amount must be greater than 0");
        require(dstChainId > 0, "Invalid destination chain");

        // EFFECTS
        depositCollateral(amountCollateral);

        // INTERACTIONS
        _lzSend(
            dstChainId,
            abi.encode(amountTorqueEURToMint, msg.sender),
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
        (uint256 amountTorqueEURToMint, address user) = abi.decode(_payload, (uint256, address));
        _mintTorque(amountTorqueEURToMint, user);
    }

    function redeemCollateralForTorqueEUR(
        uint256 amountCollateral,
        uint256 amountTorqueEURToBurn,
        uint16 dstChainId,
        bytes calldata dstAddress,
        bytes calldata adapterParams
    ) external moreThanZero(amountCollateral) {
        // CHECKS
        require(amountCollateral > 0, "Amount must be greater than 0");
        require(amountTorqueEURToBurn > 0, "Burn amount must be greater than 0");
        require(dstChainId > 0, "Invalid destination chain");

        // EFFECTS
        _burnTorque(amountTorqueEURToBurn, msg.sender);
        _redeemCollateral(amountCollateral, msg.sender, msg.sender);

        // INTERACTIONS
        _lzSend(
            dstChainId,
            abi.encode(amountTorqueEURToBurn, msg.sender),
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
        uint256 tokenAmountFromDebtCovered = getTokenAmountFromEur(debtToCover);
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

    function getTokenAmountFromEur(uint256 eurAmountInWei) public view returns (uint256) {
        (, int256 price,,,) = i_priceFeed.staleCheckLatestRoundData();
        return ((eurAmountInWei * PRECISION) / (uint256(price) * ADDITIONAL_FEED_PRECISION));
    }

    // OFTCore required functions
    function _debit(uint256 _amountLD, uint256 _minAmountLD, uint32 _dstEid) internal override returns (uint256 _amountSentLD, uint256 _feeDebitLD) {
        _amountSentLD = _amountLD;
        _feeDebitLD = 0;
    }

    function _credit(address _to, uint256 _amountLD, uint32 _srcEid) internal override returns (uint256 _amountReceivedLD) {
        _amountReceivedLD = _amountLD;
    }

    function token() external view override returns (address) {
        return address(this);
    }

    function approvalRequired() external pure override returns (bool) {
        return false;
    }
} 