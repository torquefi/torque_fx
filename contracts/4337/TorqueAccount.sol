// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.28;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/Pausable.sol";
import "@account-abstraction/contracts/core/BaseAccount.sol";
import "@account-abstraction/contracts/interfaces/IEntryPoint.sol";
import "@account-abstraction/contracts/core/UserOperationLib.sol";
import "@layerzerolabs/lz-evm-oapp-v2/contracts/oapp/OApp.sol";

interface ITorqueDEX {
    function depositLiquidity(address token, uint256 amount) external;
    function withdrawLiquidity(address token, uint256 amount) external;
    function openPosition(
        address user,
        address baseToken,
        address quoteToken,
        uint256 baseAmount,
        uint256 leverage
    ) external returns (uint256 positionId);
    function closePosition(uint256 positionId) external;
    function getPosition(uint256 positionId) external view returns (
        address user,
        address baseToken,
        address quoteToken,
        uint256 baseAmount,
        uint256 leverage,
        uint256 entryPrice,
        uint256 currentPrice
    );
    function swap(address tokenIn, uint256 amountIn, uint256 accountId) external returns (uint256 amountOut);
    function getPrice(address baseToken, address quoteToken) external view returns (uint256 price);
}

contract TorqueAccount is BaseAccount, Ownable, ReentrancyGuard, Pausable, OApp {
    using SafeERC20 for IERC20;
    using ECDSA for bytes32;

    struct Account {
        uint256 leverage;
        bool exists;
        bool active;
        string username;
        address referrer;
        uint256 lastDepositTime;
        uint256 lastWithdrawTime;
        uint256[] openPositions;
        uint256 nonce;
    }

    struct Position {
        uint256 positionId;
        address baseToken;
        address quoteToken;
        uint256 baseAmount;
        uint256 leverage;
        uint256 entryPrice;
        uint256 currentPrice;
        bool isLong;
        uint256 lastUpdateTime;
    }

    struct WithdrawRequest {
        uint256 amount;
        uint256 timestamp;
        bool isETH;
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

    IEntryPoint private immutable _entryPoint;
    IERC20 public immutable usdc;
    ITorqueDEX public immutable torqueDEX;
    address public guardian;
    
    mapping(address => mapping(uint256 => Account)) public userAccounts;
    mapping(address => uint256) public accountCount;
    mapping(string => bool) public usernames;
    mapping(address => uint256) public referralCount;
    mapping(address => uint256) public referralVolume;
    mapping(address => mapping(uint256 => uint256)) public ethBalances;
    mapping(address => mapping(uint256 => uint256)) public usdcBalances;
    mapping(address => mapping(uint256 => WithdrawRequest)) public pendingWithdrawals;
    mapping(address => mapping(uint256 => Position[])) public userPositions;
    mapping(address => mapping(uint256 => uint256)) public totalExposure;
    mapping(address => mapping(uint256 => uint256)) public totalCollateral;
    mapping(bytes32 => bool) public processedMessages;

    uint256 public constant MAX_ACCOUNTS = 5;
    uint256 public constant MIN_LEVERAGE = 1;
    uint256 public constant MAX_LEVERAGE = 10000;
    uint256 public constant MAX_USERNAME_LENGTH = 32;
    uint256 public constant RECOVERY_DELAY = 7 days;
    uint256 public constant RECOVERY_WINDOW = 2 days;
    uint256 public constant SIG_VALIDATION_FAILED = 1;
    uint256 public constant SIG_VALIDATION_SUCCESS = 0;

    event AccountCreated(address indexed user, uint256 accountId, uint256 leverage, string username, address referrer);
    event AccountUpdated(address indexed user, uint256 accountId, uint256 leverage);
    event AccountDisabled(address indexed user, uint256 accountId);
    event UsernameChanged(address indexed user, uint256 accountId, string newUsername);
    event ReferralAdded(address indexed user, address indexed referrer);
    event Deposit(address indexed user, uint256 accountId, address token, uint256 amount);
    event Withdraw(address indexed user, uint256 accountId, address token, uint256 amount);
    event ETHDeposit(address indexed user, uint256 accountId, uint256 amount);
    event ETHWithdraw(address indexed user, uint256 accountId, uint256 amount);
    event GuardianSet(address indexed oldGuardian, address indexed newGuardian);
    event AccountRecovered(address indexed oldOwner, address indexed newOwner, uint256 accountId);
    event PositionOpened(
        address indexed user,
        uint256 indexed accountId,
        uint256 positionId,
        address baseToken,
        address quoteToken,
        uint256 baseAmount,
        uint256 leverage,
        bool isLong,
        uint256 entryPrice
    );
    event PositionClosed(
        address indexed user,
        uint256 indexed accountId,
        uint256 positionId,
        uint256 exitPrice,
        int256 pnl
    );

    modifier onlyGuardian() {
        require(msg.sender == guardian, "Not guardian");
        _;
    }

    constructor(
        IEntryPoint entryPoint_,
        address _usdc,
        address _guardian,
        address _torqueDEX,
        address _lzEndpoint
    ) OApp(_lzEndpoint, msg.sender) Ownable(msg.sender) {
        _entryPoint = entryPoint_;
        usdc = IERC20(_usdc);
        guardian = _guardian;
        torqueDEX = ITorqueDEX(_torqueDEX);
    }

    function setGuardian(address _guardian) external onlyOwner {
        address oldGuardian = guardian;
        guardian = _guardian;
        emit GuardianSet(oldGuardian, _guardian);
    }

    function pause() external onlyOwner {
        _pause();
    }

    function unpause() external onlyOwner {
        _unpause();
    }

    function withdrawETH(uint256 accountId, uint256 amount) external nonReentrant whenNotPaused {
        // CHECKS
        require(amount > 0, "Amount must be greater than 0");
        Account storage account = userAccounts[msg.sender][accountId];
        require(account.exists && account.active, "Invalid account");
        require(ethBalances[msg.sender][accountId] >= amount, "Insufficient ETH balance");

        // EFFECTS
        ethBalances[msg.sender][accountId] -= amount;

        // INTERACTIONS
        (bool success, ) = payable(msg.sender).call{value: amount}("");
        require(success, "ETH transfer failed");

        emit ETHWithdraw(msg.sender, accountId, amount);
    }

    function withdrawUSDC(uint256 accountId, uint256 amount) external nonReentrant whenNotPaused {
        // CHECKS
        require(amount > 0, "Amount must be greater than 0");
        Account storage account = userAccounts[msg.sender][accountId];
        require(account.exists && account.active, "Invalid account");
        require(usdcBalances[msg.sender][accountId] >= amount, "Insufficient USDC balance");

        // EFFECTS
        usdcBalances[msg.sender][accountId] -= amount;

        // INTERACTIONS
        usdc.safeTransfer(msg.sender, amount);
        
        emit Withdraw(msg.sender, accountId, address(usdc), amount);
    }

    function recoverAccount(address oldOwner, address newOwner, uint256 accountId) external onlyGuardian {
        // CHECKS
        require(userAccounts[oldOwner][accountId].exists, "Account does not exist");
        require(!userAccounts[newOwner][accountId].exists, "New owner has existing account");
        require(oldOwner != newOwner, "Same owner");

        // EFFECTS
        Account storage account = userAccounts[oldOwner][accountId];
        account.active = false;

        userAccounts[newOwner][accountId] = Account({
            leverage: account.leverage,
            exists: true,
            active: true,
            username: account.username,
            referrer: account.referrer,
            lastDepositTime: block.timestamp,
            lastWithdrawTime: block.timestamp,
            openPositions: account.openPositions,
            nonce: account.nonce
        });

        ethBalances[newOwner][accountId] = ethBalances[oldOwner][accountId];
        usdcBalances[newOwner][accountId] = usdcBalances[oldOwner][accountId];
        delete ethBalances[oldOwner][accountId];
        delete usdcBalances[oldOwner][accountId];

        // INTERACTIONS (none in this case)
        emit AccountRecovered(oldOwner, newOwner, accountId);
    }

    function entryPoint() public view virtual override returns (IEntryPoint) {
        return _entryPoint;
    }

    function _validateSignature(
        PackedUserOperation calldata userOp,
        bytes32 userOpHash
    ) internal virtual override returns (uint256 validationData) {
        bytes32 hash = keccak256(abi.encodePacked(userOpHash));
        address signer = hash.recover(userOp.signature);
        if (owner() != signer) return SIG_VALIDATION_FAILED;
        return 0;
    }

    function depositETH(uint256 accountId) external payable nonReentrant {
        // CHECKS
        require(msg.value > 0, "Amount must be greater than 0");
        Account storage account = userAccounts[msg.sender][accountId];
        require(account.exists && account.active, "Invalid account");

        // EFFECTS
        ethBalances[msg.sender][accountId] += msg.value;

        // INTERACTIONS (none in this case as ETH is sent with the transaction)
        emit ETHDeposit(msg.sender, accountId, msg.value);
    }

    function depositUSDC(uint256 accountId, uint256 amount) external nonReentrant {
        // CHECKS
        require(amount > 0, "Amount must be greater than 0");
        Account storage account = userAccounts[msg.sender][accountId];
        require(account.exists && account.active, "Invalid account");

        // EFFECTS
        usdcBalances[msg.sender][accountId] += amount;

        // INTERACTIONS
        usdc.safeTransferFrom(msg.sender, address(this), amount);
        usdc.approve(address(torqueDEX), amount);
        torqueDEX.depositLiquidity(address(usdc), amount);
        
        emit Deposit(msg.sender, accountId, address(usdc), amount);
    }

    function getETHBalance(address user, uint256 accountId) external view returns (uint256) {
        Account storage account = userAccounts[user][accountId];
        require(account.exists && account.active, "Invalid account");
        return ethBalances[user][accountId];
    }

    function getUSDCBalance(address user, uint256 accountId) external view returns (uint256) {
        Account storage account = userAccounts[user][accountId];
        require(account.exists && account.active, "Invalid account");
        return usdcBalances[user][accountId];
    }

    function createAccount(
        uint256 leverage,
        string memory username,
        address referrer
    ) external nonReentrant returns (uint256) {
        // CHECKS
        require(accountCount[msg.sender] < MAX_ACCOUNTS, "Max accounts reached");
        require(leverage >= MIN_LEVERAGE && leverage <= MAX_LEVERAGE, "Invalid leverage");
        require(bytes(username).length <= MAX_USERNAME_LENGTH, "Username too long");
        require(!usernames[username], "Username taken");
        require(referrer != msg.sender, "Self referral");

        // EFFECTS
        uint256 accountId = accountCount[msg.sender];
        userAccounts[msg.sender][accountId] = Account({
            leverage: leverage,
            exists: true,
            active: true,
            username: username,
            referrer: referrer,
            lastDepositTime: block.timestamp,
            lastWithdrawTime: block.timestamp,
            openPositions: new uint256[](0),
            nonce: 0
        });

        usernames[username] = true;
        accountCount[msg.sender]++;

        if (referrer != address(0)) {
            referralCount[referrer]++;
        }

        // INTERACTIONS (none in this case)
        emit AccountCreated(msg.sender, accountId, leverage, username, referrer);
        if (referrer != address(0)) {
            emit ReferralAdded(msg.sender, referrer);
        }

        return accountId;
    }

    function updateLeverage(uint256 accountId, uint256 newLeverage) external {
        require(newLeverage >= MIN_LEVERAGE && newLeverage <= MAX_LEVERAGE, "Invalid leverage");
        Account storage account = userAccounts[msg.sender][accountId];
        require(account.exists && account.active, "Invalid account");
        account.leverage = newLeverage;
        emit AccountUpdated(msg.sender, accountId, newLeverage);
    }

    function disableAccount(uint256 accountId) external {
        Account storage account = userAccounts[msg.sender][accountId];
        require(account.exists && account.active, "Invalid account");
        account.active = false;
        emit AccountDisabled(msg.sender, accountId);
    }

    function changeUsername(uint256 accountId, string memory newUsername) external {
        require(bytes(newUsername).length <= MAX_USERNAME_LENGTH, "Username too long");
        require(!usernames[newUsername], "Username taken");
        Account storage account = userAccounts[msg.sender][accountId];
        require(account.exists && account.active, "Invalid account");

        usernames[account.username] = false;
        usernames[newUsername] = true;
        account.username = newUsername;

        emit UsernameChanged(msg.sender, accountId, newUsername);
    }

    function getLeverage(address user, uint256 accountId) external view returns (uint256) {
        Account storage account = userAccounts[user][accountId];
        require(account.exists && account.active, "Invalid account");
        return account.leverage;
    }

    function isValidAccount(address user, uint256 accountId) public view returns (bool) {
        Account storage account = userAccounts[user][accountId];
        return account.exists && account.active;
    }

    function getReferralStats(address user) external view returns (uint256 count, uint256 volume) {
        return (referralCount[user], referralVolume[user]);
    }

    function openPosition(
        uint256 accountId,
        address baseToken,
        address quoteToken,
        uint256 baseAmount,
        bool isLong
    ) external nonReentrant {
        // CHECKS
        require(isValidAccount(msg.sender, accountId), "Invalid account");
        Account storage account = userAccounts[msg.sender][accountId];
        require(account.exists && account.active, "Invalid account");

        // Calculate required collateral
        uint256 collateral = calculateRequiredCollateral(baseAmount, account.leverage);
        require(usdcBalances[msg.sender][accountId] >= collateral, "Insufficient collateral");

        // EFFECTS
        // Deduct collateral
        usdcBalances[msg.sender][accountId] -= collateral;

        // Create position
        uint256 positionId = userPositions[msg.sender][accountId].length;
        uint256 entryPrice = calculateEntryPrice(baseAmount, collateral, isLong);

        userPositions[msg.sender][accountId].push(Position({
            positionId: positionId,
            baseToken: baseToken,
            quoteToken: quoteToken,
            baseAmount: baseAmount,
            leverage: account.leverage,
            entryPrice: entryPrice,
            currentPrice: entryPrice,
            isLong: isLong,
            lastUpdateTime: block.timestamp
        }));

        // Update exposure
        totalExposure[msg.sender][accountId] += baseAmount;
        totalCollateral[msg.sender][accountId] += collateral;

        // INTERACTIONS
        // Execute swap in DEX
        usdc.approve(address(torqueDEX), collateral);
        uint256 outputAmount = torqueDEX.swap(address(usdc), collateral, accountId);

        emit PositionOpened(
            msg.sender,
            accountId,
            positionId,
            baseToken,
            quoteToken,
            baseAmount,
            account.leverage,
            isLong,
            entryPrice
        );
    }

    function closePosition(
        uint256 accountId,
        uint256 positionId
    ) external nonReentrant {
        // CHECKS
        require(isValidAccount(msg.sender, accountId), "Invalid account");
        Position[] storage positions = userPositions[msg.sender][accountId];
        require(positionId < positions.length, "Invalid position");

        Position storage position = positions[positionId];
        require(position.baseAmount > 0, "Position already closed");

        // Calculate current price and PnL
        uint256 currentPrice = getCurrentPrice(position.baseToken, position.quoteToken);
        int256 pnl = calculatePnL(position, currentPrice);

        // EFFECTS
        // Update exposure
        totalExposure[msg.sender][accountId] -= position.baseAmount;
        totalCollateral[msg.sender][accountId] -= position.baseAmount / position.leverage;

        // Mark position as closed
        position.baseAmount = 0;

        // INTERACTIONS
        // Execute reverse swap in DEX
        uint256 returnAmount = torqueDEX.swap(
            position.isLong ? position.baseToken : position.quoteToken,
            position.baseAmount,
            accountId
        );

        // Return collateral plus/minus PnL
        uint256 finalAmount = position.isLong 
            ? returnAmount + uint256(pnl > 0 ? pnl : int256(0))
            : returnAmount - uint256(pnl < 0 ? -pnl : int256(0));

        usdcBalances[msg.sender][accountId] += finalAmount;

        emit PositionClosed(
            msg.sender,
            accountId,
            positionId,
            currentPrice,
            pnl
        );
    }

    function calculateRequiredCollateral(
        uint256 baseAmount,
        uint256 leverage
    ) public pure returns (uint256) {
        return baseAmount * 100 / leverage;
    }

    function calculateEntryPrice(
        uint256 baseAmount,
        uint256 quoteAmount,
        bool isLong
    ) public pure returns (uint256) {
        return isLong 
            ? (quoteAmount * 1e18) / baseAmount
            : (baseAmount * 1e18) / quoteAmount;
    }

    function calculatePnL(
        Position storage position,
        uint256 currentPrice
    ) internal view returns (int256) {
        if (position.isLong) {
            return int256((currentPrice - position.entryPrice) * position.baseAmount / 1e18);
        } else {
            return int256((position.entryPrice - currentPrice) * position.baseAmount / 1e18);
        }
    }

    function getCurrentPrice(
        address baseToken,
        address quoteToken
    ) public view returns (uint256) {
        // This would be implemented to get current price from DEX or oracle
        return torqueDEX.getPrice(baseToken, quoteToken);
    }

    function getPositions(
        uint256 accountId
    ) external view returns (Position[] memory) {
        return userPositions[msg.sender][accountId];
    }

    function getTotalExposure(
        uint256 accountId
    ) external view returns (uint256) {
        return totalExposure[msg.sender][accountId];
    }

    function getTotalCollateral(
        uint256 accountId
    ) external view returns (uint256) {
        return totalCollateral[msg.sender][accountId];
    }

    // Cross-chain message handling
    function _lzReceive(
        Origin calldata _origin,
        bytes32 _guid,
        bytes calldata _message,
        address _executor,
        bytes calldata _extraData
    ) internal override {
        bytes32 messageId = keccak256(abi.encodePacked(_origin.srcEid, _origin.sender, _guid));
        require(!processedMessages[messageId], "Message already processed");
        processedMessages[messageId] = true;

        // Process cross-chain message
        (address user, uint256 accountId, bytes memory data) = abi.decode(_message, (address, uint256, bytes));
        require(isValidAccount(user, accountId), "Invalid account");

        // Execute cross-chain operation
        (bool success, ) = address(this).call(data);
        require(success, "Cross-chain operation failed");
    }
}
