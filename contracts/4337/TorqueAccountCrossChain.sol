// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.28;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@layerzerolabs/lz-evm-oapp-v2/contracts/oapp/OApp.sol";
import "@layerzerolabs/lz-evm-oapp-v2/contracts/oapp/interfaces/IOAppMsgInspector.sol";
import { MessagingFee } from "@layerzerolabs/lz-evm-protocol-v2/contracts/interfaces/ILayerZeroEndpointV2.sol";
import "./TorqueAccount.sol";

contract TorqueAccountCrossChain is OApp, ReentrancyGuard {
    TorqueAccount public immutable accountContract;
    
    struct CrossChainOperation {
        uint32 dstChainId;
        bytes dstAddress;
        uint256 accountId;
        uint256 amount;
        bool isETH;
        uint256 nonce;
        uint256 deadline;
    }

    struct GasOptimizedOperation {
        address user;
        uint256 accountId;
        uint256 amount;
        bool isETH;
        uint256 nonce;
        uint256 deadline;
        bytes signature;
    }

    mapping(uint32 => bool) public supportedChains;
    mapping(uint32 => address) public remoteContracts;
    mapping(bytes32 => bool) public processedMessages;
    mapping(address => uint256) public nonces;
    mapping(bytes32 => bool) public executedOperations;

    event CrossChainOperationInitiated(
        address indexed user,
        uint16 indexed dstChainId,
        uint256 accountId,
        uint256 amount,
        bool isETH,
        uint256 nonce
    );
    event CrossChainOperationCompleted(
        address indexed user,
        uint16 indexed srcChainId,
        uint256 accountId,
        uint256 amount,
        bool isETH
    );
    event ChainSupported(uint32 indexed chainId, bool supported);
    event RemoteContractSet(uint32 indexed chainId, address remoteContract);
    event GasOptimizedOperationExecuted(
        address indexed user,
        uint256 accountId,
        uint256 amount,
        bool isETH,
        uint256 nonce
    );

    constructor(
        address _accountContract,
        address _lzEndpoint
    ) OApp(_lzEndpoint, msg.sender) Ownable(msg.sender) {
        accountContract = TorqueAccount(_accountContract);
    }

    function setSupportedChain(uint32 chainId, bool supported) external onlyOwner {
        supportedChains[chainId] = supported;
        emit ChainSupported(chainId, supported);
    }

    function setRemoteContract(uint32 chainId, address remoteContract) external onlyOwner {
        require(supportedChains[chainId], "Chain not supported");
        remoteContracts[chainId] = remoteContract;
        emit RemoteContractSet(chainId, remoteContract);
    }

    function initiateCrossChainOperation(
        CrossChainOperation calldata operation,
        bytes calldata adapterParams
    ) external payable nonReentrant {
        require(supportedChains[operation.dstChainId], "Chain not supported");
        require(accountContract.isValidAccount(msg.sender, operation.accountId), "Invalid account");
        require(block.timestamp <= operation.deadline, "Operation expired");
        require(operation.nonce == nonces[msg.sender], "Invalid nonce");

        if (operation.isETH) {
            require(msg.value >= operation.amount, "Insufficient ETH");
            accountContract.depositETH{value: operation.amount}(operation.accountId);
        } else {
            accountContract.depositUSDC(operation.accountId, operation.amount);
        }

        bytes memory payload = abi.encode(
            msg.sender,
            operation.accountId,
            operation.amount,
            operation.isETH,
            operation.nonce
        );

        nonces[msg.sender]++;

        MessagingFee memory fee = _quote(uint16(operation.dstChainId), payload, adapterParams, false);
        _lzSend(
            uint16(operation.dstChainId),
            payload,
            adapterParams,
            fee,
            payable(msg.sender)
        );

        emit CrossChainOperationInitiated(
            msg.sender,
            uint16(operation.dstChainId),
            operation.accountId,
            operation.amount,
            operation.isETH,
            operation.nonce
        );
    }

    function executeGasOptimizedOperation(
        GasOptimizedOperation calldata operation
    ) external nonReentrant {
        require(block.timestamp <= operation.deadline, "Operation expired");
        require(operation.nonce == nonces[operation.user], "Invalid nonce");
        require(accountContract.isValidAccount(operation.user, operation.accountId), "Invalid account");

        bytes32 operationHash = keccak256(
            abi.encodePacked(
                operation.user,
                operation.accountId,
                operation.amount,
                operation.isETH,
                operation.nonce,
                operation.deadline
            )
        );

        require(!executedOperations[operationHash], "Operation already executed");
        require(
            _verifySignature(operationHash, operation.signature, operation.user),
            "Invalid signature"
        );

        executedOperations[operationHash] = true;
        nonces[operation.user]++;

        if (operation.isETH) {
            accountContract.depositETH{value: operation.amount}(operation.accountId);
        } else {
            accountContract.depositUSDC(operation.accountId, operation.amount);
        }

        emit GasOptimizedOperationExecuted(
            operation.user,
            operation.accountId,
            operation.amount,
            operation.isETH,
            operation.nonce
        );
    }

    function _lzReceive(
        Origin calldata _origin,
        bytes32 _guid,
        bytes calldata _message,
        address _executor,
        bytes calldata _extraData
    ) internal override {
        require(supportedChains[uint16(_origin.srcEid)], "Chain not supported");
        require(remoteContracts[uint16(_origin.srcEid)] == address(uint160(uint256(bytes32(_origin.sender)))), "Invalid remote contract");

        bytes32 messageId = keccak256(abi.encodePacked(_origin.srcEid, _origin.sender, _guid));
        require(!processedMessages[messageId], "Message already processed");
        processedMessages[messageId] = true;

        (
            address user,
            uint256 accountId,
            uint256 amount,
            bool isETH,
            uint256 nonce
        ) = abi.decode(_message, (address, uint256, uint256, bool, uint256));

        require(accountContract.isValidAccount(user, accountId), "Invalid account");

        if (isETH) {
            accountContract.withdrawETH(accountId, amount);
        } else {
            accountContract.withdrawUSDC(accountId, amount);
        }

        emit CrossChainOperationCompleted(
            user,
            uint16(_origin.srcEid),
            accountId,
            amount,
            isETH
        );
    }

    function _verifySignature(
        bytes32 hash,
        bytes memory signature,
        address signer
    ) internal pure returns (bool) {
        bytes32 messageHash = keccak256(
            abi.encodePacked("\x19Ethereum Signed Message:\n32", hash)
        );
        (bytes32 r, bytes32 s, uint8 v) = abi.decode(signature, (bytes32, bytes32, uint8));
        address recoveredSigner = ecrecover(messageHash, v, r, s);
        return recoveredSigner == signer;
    }

    function getNonce(address user) external view returns (uint256) {
        return nonces[user];
    }

    function estimateFee(
        uint32 dstChainId,
        bytes calldata payload,
        bytes calldata adapterParams
    ) external view returns (uint256 nativeFee, uint256 zroFee) {
        MessagingFee memory fee = _quote(uint16(dstChainId), payload, adapterParams, false);
        return (fee.nativeFee, fee.lzTokenFee);
    }
} 