// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "./TorqueAccount.sol";
import "./TorqueAccountFactory.sol";

contract TorqueAccountBundler is Ownable, ReentrancyGuard {
    TorqueAccount public immutable accountContract;
    TorqueAccountFactory public immutable factory;
    IEntryPoint public immutable entryPoint;

    struct BundledOperation {
        uint256 accountId;
        uint256 value;
        bytes data;
        bool isETH;
    }

    event OperationsBundled(
        address indexed user,
        uint256 indexed accountId,
        uint256 totalOperations,
        uint256 totalValue
    );

    constructor(
        address _accountContract,
        address _factory,
        address _entryPoint
    ) {
        accountContract = TorqueAccount(_accountContract);
        factory = TorqueAccountFactory(_factory);
        entryPoint = IEntryPoint(_entryPoint);
    }

    function bundleOperations(
        BundledOperation[] calldata operations
    ) external nonReentrant {
        uint256 totalValue;
        
        for (uint256 i = 0; i < operations.length; i++) {
            BundledOperation calldata op = operations[i];
            require(accountContract.isValidAccount(msg.sender, op.accountId), "Invalid account");
            
            if (op.isETH) {
                totalValue += op.value;
            }
            
            (bool success, ) = address(accountContract).call{value: op.value}(op.data);
            require(success, "Operation failed");
        }

        emit OperationsBundled(
            msg.sender,
            operations[0].accountId,
            operations.length,
            totalValue
        );
    }

    function bundleDeposits(
        uint256 accountId,
        uint256[] calldata amounts,
        bool[] calldata isETH
    ) external nonReentrant {
        require(amounts.length == isETH.length, "Length mismatch");
        require(accountContract.isValidAccount(msg.sender, accountId), "Invalid account");

        uint256 totalValue;
        for (uint256 i = 0; i < amounts.length; i++) {
            if (isETH[i]) {
                totalValue += amounts[i];
            }
        }

        require(msg.value >= totalValue, "Insufficient ETH");

        for (uint256 i = 0; i < amounts.length; i++) {
            if (isETH[i]) {
                accountContract.depositETH{value: amounts[i]}(accountId);
            } else {
                accountContract.depositUSDC(accountId, amounts[i]);
            }
        }

        emit OperationsBundled(
            msg.sender,
            accountId,
            amounts.length,
            totalValue
        );
    }

    function bundleWithdrawals(
        uint256 accountId,
        uint256[] calldata amounts,
        bool[] calldata isETH
    ) external nonReentrant {
        require(amounts.length == isETH.length, "Length mismatch");
        require(accountContract.isValidAccount(msg.sender, accountId), "Invalid account");

        for (uint256 i = 0; i < amounts.length; i++) {
            if (isETH[i]) {
                accountContract.requestWithdrawETH(accountId, amounts[i]);
            } else {
                accountContract.requestWithdrawUSDC(accountId, amounts[i]);
            }
        }

        emit OperationsBundled(
            msg.sender,
            accountId,
            amounts.length,
            0
        );
    }

    receive() external payable {}
} 