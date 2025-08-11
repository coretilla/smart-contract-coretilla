// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "openzeppelin-contracts/token/ERC20/IERC20.sol";
import "openzeppelin-contracts/access/Ownable.sol";
import "openzeppelin-contracts/token/ERC20/utils/SafeERC20.sol";
import "openzeppelin-contracts/utils/ReentrancyGuard.sol";
import "openzeppelin-contracts/utils/Pausable.sol";

/**
 * @title StakeVault
 * @dev A staking vault contract with 10% APY, cooldown mechanism, and real-time rewards
 * Features:
 * - 10% APY rewards in MBTC tokens
 * - 7-day cooldown period before unstaking
 * - 24-hour unstake window after cooldown
 * - Partial withdrawals supported
 * - Real-time reward calculation per second
 * - Claim rewards anytime without unstaking
 */
contract StakingVault is ReentrancyGuard, Ownable, Pausable {
    using SafeERC20 for IERC20;

    // State variables
    IERC20 public immutable stakingToken; // MBTC token for staking
    IERC20 public immutable rewardToken;  // MBTC token for rewards (same token)
    
    // Constants
    uint256 public constant APY = 10; // 10% APY
    uint256 public constant COOLDOWN_PERIOD = 7 days;
    uint256 public constant UNSTAKE_WINDOW = 1 days;
    uint256 public constant SECONDS_PER_YEAR = 365 * 24 * 60 * 60;
    uint256 public constant PRECISION = 1e18;
    
    // Structs
    struct UserInfo {
        uint256 stakedAmount;           // Total amount staked by user
        uint256 rewardDebt;             // Reward debt for accurate reward calculation
        uint256 lastStakeTime;          // Last time user staked
        uint256 cooldownStart;          // When cooldown period started
        bool inCooldown;                // Whether user is in cooldown period
        uint256 pendingRewards;         // Accumulated pending rewards
        uint256 lastRewardUpdate;       // Last time rewards were updated
    }
    
    // State mappings
    mapping(address => UserInfo) public userInfo;
    
    // Global state
    uint256 public totalStaked;
    uint256 public rewardRate; // Rewards per second per token staked
    uint256 public lastUpdateTime;
    uint256 public accRewardPerShare; // Accumulated rewards per share
    
    // Events
    event Staked(address indexed user, uint256 amount);
    event Unstaked(address indexed user, uint256 amount);
    event RewardsClaimed(address indexed user, uint256 amount);
    event CooldownStarted(address indexed user, uint256 startTime);
    event RewardRateUpdated(uint256 newRate);
    
    // Custom errors
    error InsufficientBalance();
    error NotInCooldown();
    error CooldownNotFinished();
    error UnstakeWindowExpired();
    error NoRewardsToClaim();
    error InvalidAmount();
    error InsufficientStake();
    
    constructor(
        address _stakingToken,
        address _rewardToken,
        address _owner
    ) Ownable(_owner) {
        stakingToken = IERC20(_stakingToken);
        rewardToken = IERC20(_rewardToken);
        
        // Calculate reward rate: (APY * PRECISION) / SECONDS_PER_YEAR / 100
        rewardRate = (APY * PRECISION) / SECONDS_PER_YEAR / 100;
        lastUpdateTime = block.timestamp;
        
        _transferOwnership(_owner);
    }
    
    // Modifiers
    modifier updateReward(address account) {
        accRewardPerShare = getAccRewardPerShare();
        lastUpdateTime = block.timestamp;
        
        if (account != address(0)) {
            UserInfo storage user = userInfo[account];
            user.pendingRewards = getPendingRewards(account);
            user.rewardDebt = (user.stakedAmount * accRewardPerShare) / PRECISION;
            user.lastRewardUpdate = block.timestamp;
        }
        _;
    }
    
    /**
     * @dev Stake MBTC tokens
     * @param amount Amount of tokens to stake
     */
    function stake(uint256 amount) external nonReentrant whenNotPaused updateReward(msg.sender) {
        if (amount == 0) revert InvalidAmount();
        
        UserInfo storage user = userInfo[msg.sender];
        
        // Transfer tokens from user
        stakingToken.safeTransferFrom(msg.sender, address(this), amount);
        
        // Update user info
        user.stakedAmount += amount;
        user.lastStakeTime = block.timestamp;
        user.rewardDebt = (user.stakedAmount * accRewardPerShare) / PRECISION;
        
        // Reset cooldown if user stakes new tokens
        if (user.inCooldown) {
            user.inCooldown = false;
            user.cooldownStart = 0;
        }
        
        // Update global state
        totalStaked += amount;
        
        emit Staked(msg.sender, amount);
    }
    
    /**
     * @dev Start cooldown period to prepare for unstaking
     */
    function startCooldown() external nonReentrant updateReward(msg.sender) {
        UserInfo storage user = userInfo[msg.sender];
        
        if (user.stakedAmount == 0) revert InsufficientStake();
        
        user.inCooldown = true;
        user.cooldownStart = block.timestamp;
        
        emit CooldownStarted(msg.sender, block.timestamp);
    }
    
    /**
     * @dev Unstake tokens (full or partial)
     * @param amount Amount to unstake (0 = unstake all)
     */
    function unstake(uint256 amount) external nonReentrant whenNotPaused updateReward(msg.sender) {
        UserInfo storage user = userInfo[msg.sender];
        
        if (!user.inCooldown) revert NotInCooldown();
        if (block.timestamp < user.cooldownStart + COOLDOWN_PERIOD) revert CooldownNotFinished();
        if (block.timestamp > user.cooldownStart + COOLDOWN_PERIOD + UNSTAKE_WINDOW) revert UnstakeWindowExpired();
        
        // If amount is 0, unstake everything
        if (amount == 0) {
            amount = user.stakedAmount;
        }
        
        if (amount > user.stakedAmount) revert InsufficientStake();
        if (amount == 0) revert InvalidAmount();
        
        // Update user info
        user.stakedAmount -= amount;
        user.rewardDebt = (user.stakedAmount * accRewardPerShare) / PRECISION;
        
        // If fully unstaked, reset cooldown
        if (user.stakedAmount == 0) {
            user.inCooldown = false;
            user.cooldownStart = 0;
        } else {
            // Partial unstake - reset cooldown for remaining stake
            user.inCooldown = false;
            user.cooldownStart = 0;
        }
        
        // Update global state
        totalStaked -= amount;
        
        // Transfer tokens back to user
        stakingToken.safeTransfer(msg.sender, amount);
        
        emit Unstaked(msg.sender, amount);
    }
    
    /**
     * @dev Claim accumulated rewards
     */
    function claimRewards() external nonReentrant updateReward(msg.sender) {
        uint256 rewards = userInfo[msg.sender].pendingRewards;
        
        if (rewards == 0) revert NoRewardsToClaim();
        
        // Reset pending rewards
        userInfo[msg.sender].pendingRewards = 0;
        
        // Transfer reward tokens to user
        rewardToken.safeTransfer(msg.sender, rewards);
        
        emit RewardsClaimed(msg.sender, rewards);
    }
    
    // View functions
    
    /**
     * @dev Get pending rewards for a user
     * @param account User address
     * @return Pending reward amount
     */
    function getPendingRewards(address account) public view returns (uint256) {
        UserInfo memory user = userInfo[account];
        
        if (user.stakedAmount == 0) {
            return user.pendingRewards;
        }
        
        uint256 currentAccRewardPerShare = getAccRewardPerShare();
        uint256 newRewards = (user.stakedAmount * currentAccRewardPerShare) / PRECISION - user.rewardDebt;
        
        return user.pendingRewards + newRewards;
    }
    
    /**
     * @dev Get accumulated reward per share
     * @return Current accumulated reward per share
     */
    function getAccRewardPerShare() public view returns (uint256) {
        if (totalStaked == 0) {
            return accRewardPerShare;
        }
        
        uint256 timeElapsed = block.timestamp - lastUpdateTime;
        uint256 reward = timeElapsed * rewardRate;
        
        return accRewardPerShare + (reward * PRECISION) / totalStaked;
    }
    
    /**
     * @dev Get user staking info
     * @param account User address
     * @return stakedAmount Amount staked by user
     * @return pendingRewards Pending rewards
     * @return canUnstake Whether user can unstake now
     * @return cooldownEnd When cooldown period ends
     * @return unstakeWindowEnd When unstake window ends
     */
    function getUserInfo(address account) external view returns (
        uint256 stakedAmount,
        uint256 pendingRewards,
        bool canUnstake,
        uint256 cooldownEnd,
        uint256 unstakeWindowEnd
    ) {
        UserInfo memory user = userInfo[account];
        
        stakedAmount = user.stakedAmount;
        pendingRewards = getPendingRewards(account);
        
        if (user.inCooldown) {
            cooldownEnd = user.cooldownStart + COOLDOWN_PERIOD;
            unstakeWindowEnd = cooldownEnd + UNSTAKE_WINDOW;
            canUnstake = block.timestamp >= cooldownEnd && block.timestamp <= unstakeWindowEnd;
        } else {
            cooldownEnd = 0;
            unstakeWindowEnd = 0;
            canUnstake = false;
        }
    }
    
    /**
     * @dev Get current APR (for display purposes)
     * @return Current APR in basis points (1000 = 10%)
     */
    function getCurrentAPR() external pure returns (uint256) {
        return APY * 100; // Return in basis points
    }
    
    /**
     * @dev Calculate estimated yearly rewards for a given stake amount
     * @param stakeAmount Amount to calculate rewards for
     * @return Estimated yearly rewards
     */
    function calculateYearlyRewards(uint256 stakeAmount) external pure returns (uint256) {
        return (stakeAmount * APY) / 100;
    }
    
    // Admin functions
    
    /**
     * @dev Emergency withdraw for contract owner
     * @param token Token address to withdraw
     * @param amount Amount to withdraw
     */
    function emergencyWithdraw(address token, uint256 amount) external onlyOwner {
        IERC20(token).safeTransfer(owner(), amount);
    }
    
    /**
     * @dev Pause the contract
     */
    function pause() external onlyOwner {
        _pause();
    }
    
    /**
     * @dev Unpause the contract
     */
    function unpause() external onlyOwner {
        _unpause();
    }
    
    /**
     * @dev Update reward rate (for future upgrades)
     * @param newAPY New APY percentage
     */
    function updateRewardRate(uint256 newAPY) external onlyOwner updateReward(address(0)) {
        rewardRate = (newAPY * PRECISION) / SECONDS_PER_YEAR / 100;
        emit RewardRateUpdated(rewardRate);
    }
    
    /**
     * @dev Get contract stats
     * @return totalStaked_ Total amount staked in contract
     * @return rewardRate_ Current reward rate per second
     * @return currentAPY_ Total number of users (approximation)
     */
    function getContractStats() external view returns (
        uint256 totalStaked_,
        uint256 rewardRate_,
        uint256 currentAPY_
    ) {
        totalStaked_ = totalStaked;
        rewardRate_ = rewardRate;
        currentAPY_ = APY;
    }
}
