// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;
import 'hardhat/console.sol';
import '@openzeppelin/contracts/access/Ownable.sol';
import '@openzeppelin/contracts/security/Pausable.sol';
import '@openzeppelin/contracts/security/ReentrancyGuard.sol';
import '@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol';

/**
 * @dev Staking Vault Contract
 */
contract StakingVault is Ownable, Pausable, ReentrancyGuard {
    using SafeERC20 for IERC20;

    struct LockInfo {
        // locked amount
        uint256 amount;
        // lock period
        uint256 period;
        // lock created time.
        uint256 createdDay;
        // update time by increaselock
        uint256 updatedDay;
    }

    uint256 public constant MIN_LOCK_DAYS = 30;
    uint256 public constant MAX_LOCK_DAYS = 1160;
    uint256 public constant DAY_TIME = 1 days;

    uint256 private totalRewards;
    uint256 private totalLockedAmount;
    IERC20 private stakingToken;

    // mapping (User address => (LockId => LockInfo))
    mapping(address => mapping(uint256 => LockInfo)) private lockInfoList;
    // mapping (User address => LockMaxId)
    mapping(address => uint256) private lockIdList;

    event Locked(address indexed user, uint256 amount, uint256 period, uint256 lockId);
    event LockIncreased(address indexed user, uint256 amount, uint256 period, uint256 lockId);
    event UnLocked(address indexed user, uint256 amount, bool withRewards, uint256 lockId);
    event RewardsClaimed(address indexed user, uint256 rewards, uint256 lockId);
    event Compounded(address indexed user, uint256 rewards, uint256 lockId);
    event RewardsAdded(address indexed user, uint256 rewards);

    /**
     * @param _stakingToken staking ERC20 Token address.
     */
    constructor(address _stakingToken) {
        require(_stakingToken != address(0), 'StakingVault: address must not be zero address.');
        stakingToken = IERC20(_stakingToken);
    }

    modifier isExistLockIdWithZero(uint256 lockId, address user) {
        require(lockId <= lockIdList[user], 'StakingVault: lockId not exist.');
        _;
    }

    /// user side functions
    /**
     * @dev create lock with amount and period.
     * Note: maximum period is 4 years, minimum period is one month.
     * @param amount amount for lock.
     * @param period period for lock.
     */
    function lock(uint256 amount, uint256 period) external returns (uint256 lockId) {
        lockId = _lock(msg.sender, amount, period);
    }

    /**
     * @dev User can increaselock with below params.
     * @param lockId lockId for increase lock.
     * @param amount amount for increase lock.
     * @param period period for increase lock.
     */
    function increaseLock(
        uint256 amount,
        uint256 period,
        uint256 lockId
    ) external nonReentrant whenNotPaused {
        LockInfo storage lockInfo = lockInfoList[msg.sender][lockId];
        require(lockId <= lockIdList[msg.sender] && lockId != 0, 'StakingVault: lockId not exist.');
        require(period + lockInfo.period <= MAX_LOCK_DAYS, 'StakingVault: increase period error.');
        require(
            _getDay(block.timestamp) <= lockInfo.createdDay + lockInfo.period,
            "StakingVault: Lock's deadline has expired."
        );
        lockInfo.period += period;
        lockInfo.amount += amount;
        totalLockedAmount += amount;
        stakingToken.safeTransferFrom(msg.sender, address(this), amount);

        emit LockIncreased(msg.sender, amount, period, lockId);
    }

    /**
     * @dev unlock locked tokens with rewards.
     * @param amount amount for unlock.
     * @param lockId user's lock Id.
     * @param withRewards true: unlock with rewards, false: only unlock.
     */
    function unLock(
        uint256 amount,
        uint256 lockId,
        bool withRewards
    ) external nonReentrant whenNotPaused isExistLockIdWithZero(lockId, msg.sender) {
        LockInfo storage lockInfo;
        uint256 rewards = 0;
        uint256 srcAmount = amount;
        uint256 period;
        uint256 currentDay = _getDay(block.timestamp);
        // claim or unclaim(only update) process
        if (lockId == 0) {
            for (uint256 i = 1; i <= lockIdList[msg.sender]; i++) {
                lockInfo = lockInfoList[msg.sender][i];
                // unlock
                if (currentDay - lockInfo.createdDay >= lockInfo.period && amount != 0) {
                    if (amount >= lockInfo.amount) {
                        amount -= lockInfo.amount;
                    } else {
                        lockInfo.amount -= amount;
                        amount = 0;
                    }
                }
                // claim reward
                if (withRewards) {
                    period = currentDay - lockInfo.updatedDay;
                    rewards += _getUserRewardPerLock(period, lockInfo.amount);
                    lockInfo.updatedDay = currentDay;
                } else if (amount == 0) break;
            }
            require(amount == 0, 'StakingVault: all unlock amount error.');
        } else {
            lockInfo = lockInfoList[msg.sender][lockId];
            require(
                currentDay - lockInfo.createdDay >= lockInfo.period,
                'StakingVault: You can unlock after lock period.'
            );
            require(srcAmount <= lockInfo.amount, 'StakingVault: unlock amount error.');
            period = currentDay - lockInfo.updatedDay;
            rewards = _getUserRewardPerLock(period, lockInfo.amount);
            lockInfo.updatedDay = currentDay;
            lockInfo.amount -= srcAmount;
        }
        totalLockedAmount -= srcAmount;
        stakingToken.safeTransfer(msg.sender, srcAmount + rewards);

        emit UnLocked(msg.sender, amount, withRewards, lockId);
    }

    /**
     * @dev you can get user's claimable rewards.
     * @param user user's address
     * @param lockId user's lock id
     * @return rewards
     */
    function getClaimableRewards(address user, uint256 lockId)
        external
        view
        whenNotPaused
        isExistLockIdWithZero(lockId, user)
        returns (uint256 rewards)
    {
        uint256 currentDay = _getDay(block.timestamp);
        LockInfo storage lockInfo;
        if (lockId == 0) {
            for (uint256 i = 1; i <= lockIdList[user]; i++) {
                lockInfo = lockInfoList[user][i];
                rewards += _getUserRewardPerLock(currentDay - lockInfo.updatedDay, lockInfo.amount);
            }
        } else {
            lockInfo = lockInfoList[user][lockId];
            rewards = _getUserRewardPerLock(currentDay - lockInfo.updatedDay, lockInfo.amount);
        }
    }

    /**
     * @dev claim user's rewards
     * @param lockId user's lock id
     */
    function claimRewards(uint256 lockId)
        external
        nonReentrant
        whenNotPaused
        isExistLockIdWithZero(lockId, msg.sender)
    {
        address user = msg.sender;
        uint256 rewards;
        uint256 currentDay = _getDay(block.timestamp);
        LockInfo storage lockInfo;
        if (lockId == 0) {
            for (uint256 i = 1; i <= lockIdList[user]; i++) {
                lockInfo = lockInfoList[user][i];
                rewards += _getUserRewardPerLock(currentDay - lockInfo.updatedDay, lockInfo.amount);
                lockInfo.updatedDay = currentDay;
            }
        } else {
            lockInfo = lockInfoList[user][lockId];
            rewards = _getUserRewardPerLock(currentDay - lockInfo.updatedDay, lockInfo.amount);
            lockInfo.updatedDay = currentDay;
        }
        stakingToken.safeTransfer(user, rewards);

        emit RewardsClaimed(user, rewards, lockId);
    }

    /**
     * @dev lock user's rewards token into vault again.
     * @param rewards reward for increaselock
     * @param lockId user's lock id
     */
    function compound(uint256 rewards, uint256 lockId) external whenNotPaused {
        address user = msg.sender;
        require(lockId <= lockIdList[user] && lockId != 0, 'StakingVault: lockId not exist.');
        LockInfo storage lockInfo = lockInfoList[user][lockId];
        uint256 currentDay = _getDay(block.timestamp);
        require(
            currentDay <= lockInfo.createdDay + lockInfo.period,
            "StakingVault: Lock's deadline has expired."
        );
        require(
            rewards <= _getUserRewardPerLock(currentDay - lockInfo.updatedDay, lockInfo.amount),
            'StakingVault: Not Enough compound rewards.'
        );
        uint256 perTokenOneDay = (totalRewards * 1e18) / totalLockedAmount / MAX_LOCK_DAYS;
        uint256 selectRewardPeriod = ((rewards * 1e18) / perTokenOneDay / lockInfo.amount);
        lockInfo.updatedDay = lockInfo.updatedDay + selectRewardPeriod;
        lockInfo.amount += rewards;
        totalLockedAmount += rewards;
        totalRewards -= rewards;

        emit Compounded(user, rewards, lockId);
    }

    /// Admin Functions
    /**
     * @dev create lock for other user
     * @param user user's address for lock
     * @param amount amount for lock
     * @param period period for lock
     */
    function lockFor(
        address user,
        uint256 amount,
        uint256 period
    ) external onlyOwner returns (uint256 lockId) {
        lockId = _lock(user, amount, period);
    }

    /**
     * @dev pause function
     */
    function setPause(bool pause) external onlyOwner {
        if (pause == true) {
            _pause();
        } else {
            _unpause();
        }
    }

    /**
     * @dev addRewards function
     */
    function addRewards(uint256 rewards) external {
        stakingToken.safeTransferFrom(msg.sender, address(this), rewards);
        totalRewards += rewards;

        emit RewardsAdded(msg.sender, rewards);
    }

    /**
     * @dev internal lock function with amount and period for create lock.
     * @param user user's address
     * @param amount amount for lock.
     * @param period period for lock.
     */
    function _lock(
        address user,
        uint256 amount,
        uint256 period
    ) internal nonReentrant whenNotPaused returns (uint256 lockId) {
        require(amount > 0, 'StakingVault: amount zero.');
        require(MIN_LOCK_DAYS <= period && period <= MAX_LOCK_DAYS, 'StakingVault: period error.');
        uint256 crrentDay = _getDay(block.timestamp);
        lockId = ++lockIdList[user];
        LockInfo storage lockInfo = lockInfoList[user][lockId];
        lockInfo.amount = amount;
        lockInfo.period = period;
        lockInfo.createdDay = crrentDay;
        lockInfo.updatedDay = crrentDay;
        totalLockedAmount += amount;
        stakingToken.safeTransferFrom(user, address(this), amount);

        emit Locked(user, amount, period, lockId);
    }

    /**
     * @dev users can get formula's rewards_per_token_for_one_day via this function.
     */
    function _getUserRewardPerLock(uint256 period, uint256 amount)
        internal
        view
        returns (uint256 reward)
    {
        reward =
            ((totalRewards * 1e18) / (totalLockedAmount == 0 ? 1 : totalLockedAmount)) /
            MAX_LOCK_DAYS;
        reward = reward * period * amount;
        reward /= 1e18;
    }

    function _getDay(uint256 secondTime) internal pure returns (uint256 day) {
        day = secondTime / DAY_TIME;
    }
}
