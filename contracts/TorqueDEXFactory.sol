// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@layerzerolabs/lz-evm-oapp-v2/contracts/oapp/OApp.sol";
import "./TorqueDEX.sol";

contract TorqueDEXFactory is OApp, Ownable {
    // Pool tracking
    mapping(bytes32 => address) public pairToPool; // pair hash => pool address
    mapping(address => bool) public isPool; // pool address => is valid pool
    address[] public allPools; // Array of all deployed pools
    
    // Factory parameters
    address public defaultFeeRecipient;
    uint256 public defaultFeeBps = 4; // 0.04%
    bool public defaultIsStablePair = false;
    
    // TUSD as quote asset
    address public tusdToken;
    bool public tusdSet = false;
    
    // Events
    event PoolCreated(
        address indexed poolAddress,
        address indexed baseToken,
        address indexed tusdToken,
        string pairName,
        string pairSymbol,
        string lpName,
        string lpSymbol
    );
    event DefaultFeeRecipientUpdated(address indexed oldRecipient, address indexed newRecipient);
    event DefaultFeeBpsUpdated(uint256 oldFeeBps, uint256 newFeeBps);
    event DefaultIsStablePairUpdated(bool oldIsStable, bool newIsStable);
    event TUSDTokenSet(address indexed oldTUSD, address indexed newTUSD);
    
    // Errors
    error TorqueDEXFactory__PairAlreadyExists();
    error TorqueDEXFactory__InvalidTokens();
    error TorqueDEXFactory__InvalidFeeRecipient();
    error TorqueDEXFactory__InvalidFeeBps();
    error TorqueDEXFactory__TUSDNotSet();
    error TorqueDEXFactory__BaseTokenCannotBeTUSD();
    error TorqueDEXFactory__TUSDAlreadySet();
    
    constructor(
        address _lzEndpoint,
        address _owner,
        address _defaultFeeRecipient
    ) OApp(_lzEndpoint, _owner) Ownable(_owner) {
        defaultFeeRecipient = _defaultFeeRecipient;
    }
    
    /**
     * @dev Set TUSD token address (can only be set once)
     */
    function setTUSDToken(address _tusdToken) external onlyOwner {
        if (tusdSet) {
            revert TorqueDEXFactory__TUSDAlreadySet();
        }
        if (_tusdToken == address(0)) {
            revert TorqueDEXFactory__InvalidTokens();
        }
        
        address oldTUSD = tusdToken;
        tusdToken = _tusdToken;
        tusdSet = true;
        
        emit TUSDTokenSet(oldTUSD, _tusdToken);
    }
    
    /**
     * @dev Create a new trading pool for a trading pair with TUSD as quote asset
     */
    function createPool(
        address baseToken,
        string memory pairName,
        string memory pairSymbol,
        address feeRecipient,
        bool isStablePair
    ) external onlyOwner returns (address poolAddress) {
        // Validations
        if (!tusdSet) {
            revert TorqueDEXFactory__TUSDNotSet();
        }
        if (baseToken == address(0) || baseToken == tusdToken) {
            revert TorqueDEXFactory__BaseTokenCannotBeTUSD();
        }
        if (feeRecipient == address(0)) {
            revert TorqueDEXFactory__InvalidFeeRecipient();
        }
        
        // Always use baseToken as token0 and TUSD as token1 (for consistent ordering)
        address token0 = baseToken;
        address token1 = tusdToken;
        
        // Check if pair already exists
        bytes32 pairHash = keccak256(abi.encodePacked(token0, token1));
        if (pairToPool[pairHash] != address(0)) {
            revert TorqueDEXFactory__PairAlreadyExists();
        }
        
        // Create unique LP token name and symbol
        string memory lpName = string(abi.encodePacked("Torque ", pairName, " LP"));
        string memory lpSymbol = string(abi.encodePacked("T", pairSymbol));
        
        // Deploy new pool
        TorqueDEX pool = new TorqueDEX(
            token0,
            token1,
            lpName,
            lpSymbol,
            feeRecipient,
            isStablePair,
            lzEndpoint,
            owner
        );
        
        poolAddress = address(pool);
        
        // Register the pool
        pairToPool[pairHash] = poolAddress;
        isPool[poolAddress] = true;
        allPools.push(poolAddress);
        
        emit PoolCreated(
            poolAddress,
            baseToken,
            tusdToken,
            pairName,
            pairSymbol,
            lpName,
            lpSymbol
        );
    }
    
    /**
     * @dev Create pool with default parameters
     */
    function createPoolWithDefaults(
        address baseToken,
        string memory pairName,
        string memory pairSymbol
    ) external onlyOwner returns (address poolAddress) {
        return createPool(
            baseToken,
            pairName,
            pairSymbol,
            defaultFeeRecipient,
            defaultIsStablePair
        );
    }
    
    /**
     * @dev Get pool address for a base token (TUSD is always the quote asset)
     */
    function getPool(address baseToken) external view returns (address) {
        if (!tusdSet) {
            revert TorqueDEXFactory__TUSDNotSet();
        }
        bytes32 pairHash = keccak256(abi.encodePacked(baseToken, tusdToken));
        return pairToPool[pairHash];
    }
    
    /**
     * @dev Get pool address for a specific token pair (for backward compatibility)
     */
    function getPoolPair(address token0, address token1) external view returns (address) {
        if (!tusdSet) {
            revert TorqueDEXFactory__TUSDNotSet();
        }
        
        // Ensure consistent ordering: baseToken should be token0, TUSD should be token1
        if (token0 == tusdToken && token1 != tusdToken) {
            // Swap them to maintain baseToken/TUSD format
            (token0, token1) = (token1, token0);
        }
        
        if (token1 != tusdToken) {
            revert TorqueDEXFactory__InvalidTokens();
        }
        
        bytes32 pairHash = keccak256(abi.encodePacked(token0, token1));
        return pairToPool[pairHash];
    }
    
    /**
     * @dev Get all pool addresses
     */
    function getAllPools() external view returns (address[] memory) {
        return allPools;
    }
    
    /**
     * @dev Get total number of pools
     */
    function getPoolCount() external view returns (uint256) {
        return allPools.length;
    }
    
    /**
     * @dev Check if a base token has a pool pair
     */
    function hasPool(address baseToken) external view returns (bool) {
        if (!tusdSet) {
            return false;
        }
        bytes32 pairHash = keccak256(abi.encodePacked(baseToken, tusdToken));
        return pairToPool[pairHash] != address(0);
    }
    
    /**
     * @dev Update default fee recipient
     */
    function setDefaultFeeRecipient(address _defaultFeeRecipient) external onlyOwner {
        if (_defaultFeeRecipient == address(0)) {
            revert TorqueDEXFactory__InvalidFeeRecipient();
        }
        address oldRecipient = defaultFeeRecipient;
        defaultFeeRecipient = _defaultFeeRecipient;
        emit DefaultFeeRecipientUpdated(oldRecipient, _defaultFeeRecipient);
    }
    
    /**
     * @dev Update default fee basis points
     */
    function setDefaultFeeBps(uint256 _defaultFeeBps) external onlyOwner {
        if (_defaultFeeBps > 1000) { // Max 10%
            revert TorqueDEXFactory__InvalidFeeBps();
        }
        uint256 oldFeeBps = defaultFeeBps;
        defaultFeeBps = _defaultFeeBps;
        emit DefaultFeeBpsUpdated(oldFeeBps, _defaultFeeBps);
    }
    
    /**
     * @dev Update default stable pair setting
     */
    function setDefaultIsStablePair(bool _defaultIsStablePair) external onlyOwner {
        bool oldIsStable = defaultIsStablePair;
        defaultIsStablePair = _defaultIsStablePair;
        emit DefaultIsStablePairUpdated(oldIsStable, _defaultIsStablePair);
    }
    
    /**
     * @dev Emergency function to recover stuck tokens
     */
    function emergencyWithdraw(
        address token,
        address to,
        uint256 amount
    ) external onlyOwner {
        IERC20(token).transfer(to, amount);
    }
} 