// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "./TorqueAccount.sol";

contract TorqueAccountGasOptimizer is Ownable, ReentrancyGuard {
    TorqueAccount public immutable accountContract;
    
    struct BatchOperation {
        uint256 accountId;
        uint256 amount;
        bool isETH;
        bool isDeposit;
    }

    struct GasOptimizedOperation {
        address user;
        uint256 accountId;
        uint256 amount;
        bool isETH;
        bool isDeposit;
        uint256 nonce;
        uint256 deadline;
        bytes signature;
    }

    mapping(address => uint256) public nonces;
    mapping(bytes32 => bool) public executedOperations;

    event BatchOperationExecuted(
        address indexed user,
        uint256[] accountIds,
        uint256[] amounts,
        bool[] isETH,
        bool[] isDeposit
    );
    event GasOptimizedOperationExecuted(
        address indexed user,
        uint256 accountId,
        uint256 amount,
        bool isETH,
        bool isDeposit,
        uint256 nonce
    );

    constructor(address _accountContract) Ownable(msg.sender) {
        accountContract = TorqueAccount(_accountContract);
    }

    function executeBatchOperations(
        BatchOperation[] calldata operations
    ) external payable nonReentrant {
        uint256 totalETH = 0;
        uint256 totalUSDC = 0;

        for (uint256 i = 0; i < operations.length; i++) {
            require(accountContract.isValidAccount(msg.sender, operations[i].accountId), "Invalid account");
            
            if (operations[i].isDeposit) {
                if (operations[i].isETH) {
                    totalETH += operations[i].amount;
                } else {
                    totalUSDC += operations[i].amount;
                }
            }
        }

        require(msg.value >= totalETH, "Insufficient ETH");

        uint256[] memory accountIds = new uint256[](operations.length);
        uint256[] memory amounts = new uint256[](operations.length);
        bool[] memory isETH = new bool[](operations.length);
        bool[] memory isDeposit = new bool[](operations.length);

        for (uint256 i = 0; i < operations.length; i++) {
            accountIds[i] = operations[i].accountId;
            amounts[i] = operations[i].amount;
            isETH[i] = operations[i].isETH;
            isDeposit[i] = operations[i].isDeposit;

            if (operations[i].isDeposit) {
                if (operations[i].isETH) {
                    accountContract.depositETH{value: operations[i].amount}(operations[i].accountId);
                } else {
                    accountContract.depositUSDC(operations[i].accountId, operations[i].amount);
                }
            } else {
                if (operations[i].isETH) {
                    accountContract.withdrawETH(operations[i].accountId, operations[i].amount);
                } else {
                    accountContract.withdrawUSDC(operations[i].accountId, operations[i].amount);
                }
            }
        }

        emit BatchOperationExecuted(msg.sender, accountIds, amounts, isETH, isDeposit);
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
                operation.isDeposit,
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

        if (operation.isDeposit) {
            if (operation.isETH) {
                accountContract.depositETH{value: operation.amount}(operation.accountId);
            } else {
                accountContract.depositUSDC(operation.accountId, operation.amount);
            }
        } else {
            if (operation.isETH) {
                accountContract.withdrawETH(operation.accountId, operation.amount);
            } else {
                accountContract.withdrawUSDC(operation.accountId, operation.amount);
            }
        }

        emit GasOptimizedOperationExecuted(
            operation.user,
            operation.accountId,
            operation.amount,
            operation.isETH,
            operation.isDeposit,
            operation.nonce
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
} 