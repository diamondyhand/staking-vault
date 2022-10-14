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
    uint256 public constant MIN_LOCK_DAYS = 30;
    uint256 public constant MAX_LOCK_DAYS = 1160;
    uint256 public constant DAY_TIME = 24 * 3600;
    uint256 public totalRewards;
    uint256 public totalLockedAmount;
    IERC20 public stakingToken;
    struct LockInfo {
        // locked amount
        uint256 amount;
        // lock period
        uint256 period;
        // lock created time.
        uint256 createdTime;
        // update time by increaselock
        uint256 updatedTime;
    }

    // mapping (User address => (LockId => LockInfo))
    mapping(address => mapping(uint256 => LockInfo)) public lockInfoList;

    // mapping (User address => LockMaxId)
    mapping(address => uint256) public lockIdList;

    /**
     * @param _stakingToken staking ERC20 Token address.
     */
    constructor(address _stakingToken) {
        require(_stakingToken != address(0), 'StakingVault: address must not be zero address.');
        stakingToken = IERC20(_stakingToken);
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
     *@dev User can increaselock with below params.
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
        require(lockInfo.amount > 0, 'StakingVault: You must be create lock.');
        require(period + lockInfo.period <= MAX_LOCK_DAYS, 'StakingVault: increase period error.');
        require(
            _getDay(block.timestamp) <= lockInfo.createdTime + lockInfo.period,
            "StakingVault: Lock's deadline has expired."
        );
        lockInfo.period += period;
        lockInfo.amount += amount;
        totalLockedAmount += amount;
        stakingToken.safeTransferFrom(msg.sender, address(this), amount);
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
    ) external nonReentrant whenNotPaused {
        LockInfo storage lockInfo;
        require(lockId <= lockIdList[msg.sender], 'StakingVault: lockId not exist.');
        uint256 rewards = 0;
        uint256 period;
        uint256 nowDay = _getDay(block.timestamp);
        // claim or unclaim(only update) process
        if (lockId == 0) {
            for (uint256 i = 1; i <= lockIdList[msg.sender]; i++) {
                lockInfo = lockInfoList[msg.sender][i];
                if (withRewards) {
                    period = nowDay - lockInfo.updatedTime;
                    rewards += _getUserRewardPerLock(period, lockInfo.amount);
                    lockInfo.updatedTime = nowDay;
                }
                if (nowDay - lockInfo.createdTime >= lockInfo.period) {
                    if (amount >= lockInfo.amount) {
                        amount -= lockInfo.amount;
                    } else {
                        lockInfo.amount -= amount;
                        amount = 0;
                    }
                }
            }
            require(amount == 0, 'StakingVault: all unlock amount error.');
        } else {
            lockInfo = lockInfoList[msg.sender][lockId];
            require(
                nowDay - lockInfo.createdTime >= lockInfo.period,
                'StakingVault: You can unlock after lock period.'
            );
            require(amount <= lockInfo.amount, 'StakingVault: unlock amount error.');
            period = nowDay - lockInfo.updatedTime;
            rewards = _getUserRewardPerLock(period, lockInfo.amount);
            lockInfo.updatedTime = nowDay;
            lockInfo.amount -= amount;
        }
        totalLockedAmount -= amount;
        stakingToken.safeTransfer(msg.sender, amount + rewards);
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
        returns (uint256 rewards)
    {
        require(lockId <= lockIdList[user], 'StakingVault: lockId not exist.');
        uint256 period;
        uint256 newReward;
        uint256 nowDay = _getDay(block.timestamp);
        LockInfo storage lockInfo;
        if (lockId == 0) {
            for (uint256 i = 1; i <= lockIdList[user]; i++) {
                lockInfo = lockInfoList[user][i];
                period = nowDay - lockInfo.updatedTime;
                newReward = _getUserRewardPerLock(period, lockInfo.amount);
                rewards += newReward;
            }
        } else {
            lockInfo = lockInfoList[user][lockId];
            period = nowDay - lockInfo.updatedTime;
            rewards = _getUserRewardPerLock(period, lockInfo.amount);
        }
    }

    /**
     * @dev claim user's rewards
     * @param user user's address for claim
     * @param lockId user's lock id
     */
    function claimRewards(address user, uint256 lockId) external nonReentrant whenNotPaused {
        require(user == msg.sender, 'StakingVault: Not permission.');
        require(lockId <= lockIdList[user], 'StakingVault: lockId not exist.');
        uint256 period;
        uint256 newReward;
        uint256 rewards;
        uint256 nowDay = _getDay(block.timestamp);
        LockInfo storage lockInfo;
        if (lockId == 0) {
            for (uint256 i = 1; i <= lockIdList[user]; i++) {
                lockInfo = lockInfoList[user][i];
                period = nowDay - lockInfo.updatedTime;
                newReward = _getUserRewardPerLock(period, lockInfo.amount);
                rewards += newReward;
                lockInfo.updatedTime = nowDay;
            }
        } else {
            lockInfo = lockInfoList[user][lockId];
            period = nowDay - lockInfo.updatedTime;
            rewards = _getUserRewardPerLock(period, lockInfo.amount);
            lockInfo.updatedTime = nowDay;
        }
        stakingToken.safeTransfer(user, rewards);
    }

    /**
     * @dev lock user's rewards token into vault again.
     * @param user user's address for increaselock
     * @param rewards reward for increaselock
     * @param lockId user's lock id
     */
    function compound(
        address user,
        uint256 rewards,
        uint256 lockId
    ) external whenNotPaused {
        require(user == msg.sender, 'StakingVault: Not permission.');
        require(lockId <= lockIdList[msg.sender] && lockId != 0, 'StakingVault: lockId not exist.');
        LockInfo storage lockInfo = lockInfoList[user][lockId];
        uint256 nowDay = _getDay(block.timestamp);

        require(
            nowDay <= lockInfo.createdTime + lockInfo.period,
            "StakingVault: Lock's deadline has expired."
        );
        uint256 period = nowDay - lockInfo.updatedTime;
        require(
            rewards <= _getUserRewardPerLock(period, lockInfo.amount),
            'StakingVault: Not Enough compound rewards.'
        );
        uint256 perTokenOneDay = (totalRewards * 1e18) / totalLockedAmount / MAX_LOCK_DAYS;
        uint256 selectRewardPeriod = ((rewards * 1e18) / perTokenOneDay / lockInfo.amount);
        lockInfo.updatedTime = lockInfo.updatedTime + selectRewardPeriod;
        lockInfo.amount += rewards;
        totalLockedAmount += rewards;
        totalRewards -= rewards;
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
    function addRewards(uint256 reward) external {
        stakingToken.safeTransferFrom(msg.sender, address(this), reward);
        totalRewards += reward;
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
        uint256 nowDay = _getDay(block.timestamp);
        lockId = ++lockIdList[user];
        LockInfo storage lockInfo = lockInfoList[user][lockId];
        lockInfo.amount = amount;
        lockInfo.period = period;
        lockInfo.createdTime = nowDay;
        lockInfo.updatedTime = nowDay;
        totalLockedAmount += amount;
        stakingToken.safeTransferFrom(user, address(this), amount);
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

    function _getDay(uint256 time) internal pure returns (uint256 day) {
        day = time / DAY_TIME;
    }
}
