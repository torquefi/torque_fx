// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import "@openzeppelin/contracts/utils/cryptography/SignatureChecker.sol";
import "@openzeppelin/contracts/utils/Address.sol";

interface IAccount {
    function validateUserOp(
        UserOperation calldata userOp,
        bytes32 userOpHash,
        uint256 missingAccountFunds
    ) external returns (uint256 validationData);
}

struct UserOperation {
    address sender;
    uint256 nonce;
    bytes initCode;
    bytes callData;
    uint256 callGasLimit;
    uint256 verificationGasLimit;
    uint256 preVerificationGas;
    uint256 maxFeePerGas;
    uint256 maxPriorityFeePerGas;
    bytes paymasterAndData;
    bytes signature;
}

struct MemoryUserOp {
    address sender;
    uint256 nonce;
    uint256 callGasLimit;
    uint256 verificationGasLimit;
    uint256 preVerificationGas;
    uint256 maxFeePerGas;
    uint256 maxPriorityFeePerGas;
    bytes paymasterAndData;
    bytes callData;
    bytes signature;
}

contract EntryPoint is ReentrancyGuard {
    using ECDSA for bytes32;
    using Address for address;

    uint256 public constant SIG_VALIDATION_FAILED = 1;
    uint256 public constant SIG_VALIDATION_SUCCESS = 0;

    mapping(address => uint256) public nonces;
    mapping(address => uint256) public balances;

    event UserOperationEvent(
        bytes32 indexed userOpHash,
        address indexed sender,
        address indexed paymaster,
        uint256 nonce,
        bool success,
        uint256 actualGasCost,
        uint256 actualGasUsed
    );

    event AccountDeployed(
        address indexed account,
        address indexed owner,
        address indexed factory
    );

    function handleOps(UserOperation[] calldata ops, address payable beneficiary) external nonReentrant {
        for (uint256 i = 0; i < ops.length; i++) {
            UserOperation calldata op = ops[i];
            bytes32 userOpHash = getUserOpHash(op);
            uint256 validationData = _validateUserOp(op, userOpHash);
            
            if (validationData == SIG_VALIDATION_FAILED) {
                emit UserOperationEvent(
                    userOpHash,
                    op.sender,
                    address(0),
                    op.nonce,
                    false,
                    0,
                    0
                );
                continue;
            }

            bool success = _executeUserOp(op);
            uint256 gasUsed = gasleft();
            
            emit UserOperationEvent(
                userOpHash,
                op.sender,
                address(0),
                op.nonce,
                success,
                gasUsed * op.maxFeePerGas,
                gasUsed
            );
        }
    }

    function getUserOpHash(UserOperation calldata userOp) public view returns (bytes32) {
        return keccak256(abi.encode(
            userOp.sender,
            userOp.nonce,
            keccak256(userOp.initCode),
            keccak256(userOp.callData),
            userOp.callGasLimit,
            userOp.verificationGasLimit,
            userOp.preVerificationGas,
            userOp.maxFeePerGas,
            userOp.maxPriorityFeePerGas,
            keccak256(userOp.paymasterAndData)
        ));
    }

    function _validateUserOp(UserOperation calldata userOp, bytes32 userOpHash) internal returns (uint256) {
        if (userOp.initCode.length != 0) {
            _createAccount(userOp);
        }

        IAccount account = IAccount(userOp.sender);
        return account.validateUserOp(userOp, userOpHash, 0);
    }

    function _createAccount(UserOperation calldata userOp) internal {
        address factory = address(bytes20(userOp.initCode[:20]));
        bytes memory initData = userOp.initCode[20:];
        
        address account = factory.functionCall(initData);
        emit AccountDeployed(account, userOp.sender, factory);
    }

    function _executeUserOp(UserOperation calldata userOp) internal returns (bool) {
        address target = address(bytes20(userOp.callData[:20]));
        bytes memory callData = userOp.callData[20:];
        
        (bool success, ) = target.call{gas: userOp.callGasLimit}(callData);
        return success;
    }

    function depositTo(address account) external payable {
        balances[account] += msg.value;
    }

    function withdrawTo(address payable withdrawAddress, uint256 withdrawAmount) external {
        require(balances[msg.sender] >= withdrawAmount, "Insufficient balance");
        balances[msg.sender] -= withdrawAmount;
        withdrawAddress.transfer(withdrawAmount);
    }

    function getNonce(address account) external view returns (uint256) {
        return nonces[account];
    }

    function getBalance(address account) external view returns (uint256) {
        return balances[account];
    }
} 