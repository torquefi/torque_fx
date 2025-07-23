// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.30;

import "./TorqueEngine.sol";
import { TorqueCNY } from "../currencies/TorqueCNY.sol";
import { AggregatorV3Interface } from "@chainlink/contracts/src/v0.8/shared/interfaces/AggregatorV3Interface.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";
import { Origin } from "@layerzerolabs/lz-evm-oapp-v2/contracts/oapp/interfaces/IOAppReceiver.sol";
import { MessagingFee } from "@layerzerolabs/lz-evm-protocol-v2/contracts/interfaces/ILayerZeroEndpointV2.sol";

contract TorqueCNYEngine is TorqueEngine {
    IERC20 private immutable i_collateralToken;
    AggregatorV3Interface private immutable i_priceFeed;
    TorqueCNY private immutable i_torqueCNY;

    constructor(
        address collateralToken,
        address priceFeed,
        address torqueCNY,
        address lzEndpoint
    ) TorqueEngine(lzEndpoint) {
        i_collateralToken = IERC20(collateralToken);
        i_priceFeed = AggregatorV3Interface(priceFeed);
        i_torqueCNY = TorqueCNY(torqueCNY);
    }

    function getCollateralToken() public view override returns (IERC20) {
        return i_collateralToken;
    }

    function getPriceFeed() public view override returns (AggregatorV3Interface) {
        return i_priceFeed;
    }

    function getTorqueToken() public view override returns (IERC20) {
        return i_torqueCNY;
    }

    function getCollateralDecimals() public view override returns (uint8) {
        return 6; // USDC decimals
    }

    function depositCollateralAndMintTorqueCNY(
        uint256 amountCollateral,
        uint256 amountTorqueCNYToMint,
        uint16 dstChainId,
        bytes calldata dstAddress,
        bytes calldata adapterParams
    ) external payable moreThanZero(amountCollateral) {
        // CHECKS
        require(amountCollateral > 0, "Amount must be greater than 0");
        require(amountTorqueCNYToMint > 0, "Mint amount must be greater than 0");
        require(dstChainId > 0, "Invalid destination chain");

        // EFFECTS
        depositCollateral(amountCollateral);

        // INTERACTIONS
        bytes memory message = abi.encode(amountTorqueCNYToMint, msg.sender);
        MessagingFee memory fee = _quote(dstChainId, message, adapterParams, false);
        _lzSend(
            dstChainId,
            message,
            adapterParams,
            fee,
            payable(msg.sender)
        );
    }

    function _lzReceive(
        Origin calldata _origin,
        bytes32 _guid,
        bytes calldata _message,
        address _executor,
        bytes calldata _extraData
    ) internal virtual override {
        // Call parent implementation first
        super._lzReceive(_origin, _guid, _message, _executor, _extraData);
        
        // Additional custom logic for minting TorqueCNY
        if (_message.length > 0) {
            (uint256 amountTorqueCNYToMint, address user) = abi.decode(_message, (uint256, address));
            _mintTorque(amountTorqueCNYToMint, user);
        }
    }

    function redeemCollateralForTorqueCNY(
        uint256 amountCollateral,
        uint256 amountTorqueCNYToBurn,
        uint16 dstChainId,
        bytes calldata dstAddress,
        bytes calldata adapterParams
    ) external moreThanZero(amountCollateral) {
        // CHECKS
        require(amountCollateral > 0, "Amount must be greater than 0");
        require(amountTorqueCNYToBurn > 0, "Burn amount must be greater than 0");
        require(dstChainId > 0, "Invalid destination chain");

        // EFFECTS
        _burnTorque(amountTorqueCNYToBurn, msg.sender);
        _redeemCollateral(amountCollateral, msg.sender, msg.sender);

        // INTERACTIONS
        bytes memory message = abi.encode(amountTorqueCNYToBurn, msg.sender);
        MessagingFee memory fee = _quote(dstChainId, message, adapterParams, false);
        _lzSend(
            dstChainId,
            message,
            adapterParams,
            fee,
            payable(msg.sender)
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
        uint256 tokenAmountFromDebtCovered = getTokenAmountFromUsd(debtToCover);
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

    function getTokenAmountFromUsd(uint256 usdAmountInWei) public view returns (uint256) {
        (, int256 price,,,) = i_priceFeed.latestRoundData();
        return ((usdAmountInWei * PRECISION) / (uint256(price) * ADDITIONAL_FEED_PRECISION));
    }

    // OFTCore required functions
    function _debit(
        address _from,
        uint256 _amountLD,
        uint256 _minAmountLD,
        uint32 _dstEid
    ) internal virtual override returns (uint256 amountSentLD, uint256 amountReceivedLD) {
        amountSentLD = _amountLD;
        amountReceivedLD = _amountLD;
    }

    function _credit(
        address _to,
        uint256 _amountLD,
        uint32 _srcEid
    ) internal virtual override returns (uint256 amountReceivedLD) {
        amountReceivedLD = _amountLD;
    }

    function token() external view override returns (address) {
        return address(this);
    }

    function approvalRequired() external pure override returns (bool) {
        return false;
    }
} 