// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/access/Ownable.sol";

/**
 * @title MockLayerZeroEndpoint
 * @dev Simple mock implementation of LayerZero endpoint for testing purposes
 */
contract MockLayerZeroEndpoint is Ownable {
    constructor() Ownable(msg.sender) {}

    // Mock events
    event Send(
        uint16 indexed _dstChainId,
        bytes indexed _destination,
        bytes _payload,
        address indexed _refundAddress,
        address _zroPaymentAddress,
        bytes _adapterParams
    );

    event Receive(
        uint16 indexed _srcChainId,
        bytes indexed _source,
        address indexed _destination,
        bytes _payload
    );

    // Mock send function - just emit event and return
    function send(
        uint16 _dstChainId,
        bytes calldata _destination,
        bytes calldata _payload,
        address payable _refundAddress,
        address _zroPaymentAddress,
        bytes calldata _adapterParams
    ) external payable {
        emit Send(_dstChainId, _destination, _payload, _refundAddress, _zroPaymentAddress, _adapterParams);
    }

    // Mock receive function - just emit event
    function receivePayload(
        uint16 _srcChainId,
        bytes calldata _source,
        address _destination,
        bytes calldata _payload
    ) external {
        emit Receive(_srcChainId, _source, _destination, _payload);
    }

    // Mock fee estimation - return fixed fees
    function estimateFees(
        uint16,
        address,
        bytes calldata,
        bool,
        bytes calldata
    ) external pure returns (uint256 nativeFee, uint256 zroFee) {
        return (0.001 ether, 0);
    }

    // Mock nonce functions - return 1
    function getInboundNonce(uint16, bytes calldata) external pure returns (uint64) {
        return 1;
    }

    function getOutboundNonce(uint16, address) external pure returns (uint64) {
        return 1;
    }

    // Mock version functions - return 1
    function getSendVersion(address) external pure returns (uint64) {
        return 1;
    }

    function getReceiveVersion(address) external pure returns (uint64) {
        return 1;
    }

    // Mock library address functions - return zero address
    function getSendLibraryAddress(address) external pure returns (address) {
        return address(0);
    }

    function getReceiveLibraryAddress(address) external pure returns (address) {
        return address(0);
    }

    // Mock config functions - do nothing
    function getConfig(uint16, uint16, address, uint256) external pure returns (bytes memory) {
        return "";
    }

    function setConfig(uint16, uint16, uint256, bytes calldata) external {}

    // Mock version setting functions - do nothing
    function setSendVersion(uint16) external {}
    function setReceiveVersion(uint16) external {}
    function setSendVersion(uint16, address, uint64) external {}
    function setReceiveVersion(uint16, address, uint64) external {}

    // Mock library setting functions - do nothing
    function setSendLibraryAddress(uint16, address, address) external {}
    function setReceiveLibraryAddress(uint16, address, address) external {}
    function setDefaultSendLibrary(uint16, address) external {}
    function setDefaultReceiveLibrary(uint16, address) external {}

    // Mock utility functions
    function isSendingPayload() external pure returns (bool) {
        return false;
    }

    function isReceivingPayload() external pure returns (bool) {
        return false;
    }

    function forceResumeReceive(uint16, bytes calldata) external {}
    function retryPayload(uint16, bytes calldata, bytes calldata) external {}
    function hasStoredPayload(uint16, bytes calldata) external pure returns (bool) {
        return false;
    }
    function getStoredPayload(uint16, bytes calldata) external pure returns (bytes memory) {
        return "";
    }
    function isTrustedRemote(uint16, bytes calldata) external pure returns (bool) {
        return true;
    }
} 