// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;
import 'hardhat/console.sol';
import '@openzeppelin/contracts/access/Ownable.sol';
import '@openzeppelin/contracts/security/Pausable.sol';
import '@openzeppelin/contracts/security/ReentrancyGuard.sol';
import '@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol';



/// Feedback: calcualte rewards based on day, not seconds.
/// Feedback: do not store user rewards on contract

/**
 * @dev Staking Vault Contract
 */
contract StakingVault is Ownable, Pausable, ReentrancyGuard {
    using SafeERC20 for IERC20;
    uint256 public constant MIN_LOCK_DAYS = 30 days;
    uint256 public constant MAX_LOCK_DAYS = 4 * 365 days;
    uint256 public totalRewards;
    uint256 public totalLockedAmount;

    address public distributor;  /// Feedbacks: no need to use distributor in V2
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
        // reward
        uint256 reward;     ///  Feedbacks: Do not store this reward on contract, because we can calcualte user rewards with user locked amount and emission rate at any time.
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

    modifier isLocked(uint256 lockId) { /// Feedback: No need this, this check is being used in only one function
        require(
            lockInfoList[msg.sender][lockId].amount > 0,
            'StakingVault: You must be create lock.'
        );
        _;
    }

    modifier isLockId(address user, uint256 lockId) { /// Feedback: No need this, this check is being used in only one function
        require(lockId > 0 && lockId <= lockIdList[user], 'StakingVault: lockId error.');
        _;
    }

    modifier isApproved(address user, uint256 amount) {   /// Feedback: No need this
        require(
            stakingToken.allowance(user, address(this)) >= amount,
            'StakingVault: You must be approve.'
        );
        _;
    }

    modifier onlyRewardDistributor() {   /// Feedback: No need this
        require(msg.sender == distributor, 'RewardDistributor can only call this function.');
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
     *@dev User can increaselock with below params.
     * @param lockId lockId for increase lock.
     * @param amount amount for increase lock.
     * @param period period for increase lock.
     */
    function increaseLock(
        uint256 lockId,
        uint256 amount,
        uint256 period
    )
        external
        nonReentrant
        whenNotPaused
        isLockId(msg.sender, lockId)
        (lockId)(lockId) /// Feedback: what's this?
        isApproved(msg.sender, amount)  /// Feedback: No need this
    {
        LockInfo storage lockInfo = lockInfoList[msg.sender][lockId];
        require(period + lockInfo.period <= MAX_LOCK_DAYS, 'StakingVault: increase period error.');
        require(
            block.timestamp <= lockInfo.createdTime + lockInfo.period,
            "StakingVault: Lock's deadline has expired., lockId"
        );
        _updateReward(msg.sender, lockId);
        lockInfo.period += period;
        lockInfo.amount += amount;
        totalLockedAmount += amount;
        stakingToken.safeTransferFrom(msg.sender, address(this), amount);
    }

    /**
     * @dev unlock locked tokens with rewards.
     * @param amount amount for unlock.
     * @param lockId user's lock Id.
     * @param withRewards true: get reward, false: can't get reward.
     */
    function unLock(
        uint256 amount,
        uint256 lockId,
        bool withRewards   /// Feedback: No logic for this
    ) external nonReentrant whenNotPaused {
        require(lockId <= lockIdList[msg.sender], 'StakingVault: lockId not exist.');
        LockInfo storage lockInfo;
        uint256 rewards;
        _updateReward(msg.sender, lockId);
        if (lockId == 0) {
            for (uint256 i = 1; i <= lockIdList[msg.sender]; i++) {
                lockInfo = lockInfoList[msg.sender][i];
                if (block.timestamp - lockInfo.createdTime >= lockInfo.period) {
                    rewards = lockInfo.reward;
                    if (amount >= lockInfo.amount) {
                        amount -= lockInfo.amount;
                    } else {
                        lockInfo.amount -= amount;
                        amount = 0;
                    }
                }
                if (amount == 0) break;
            }
            require(amount == 0, 'StakingVault: all unlock amount error.');
        } else {
            lockInfo = lockInfoList[msg.sender][lockId];
            require(
                block.timestamp - lockInfo.createdTime >= lockInfo.period,
                'StakingVault: You can unlock after lock period.'
            );
            require(amount <= lockInfo.amount, 'StakingVault: unlock amount error.');
            rewards = lockInfo.reward;
            lockInfo.reward = 0;
            lockInfo.amount -= amount;
        }
        totalRewards -= rewards;
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
        public
        view
        whenNotPaused
        returns (uint256 rewards)
    {
        require(lockId < lockIdList[user], 'StakingVault: lockId not exist.');
        if (lockId == 0) {
            for (uint256 i = 1; i < lockIdList[user]; i++) {
                rewards += _earned(user, i) + lockInfoList[user][i].reward;
            }
        } else {
            rewards = _earned(user, lockId) + lockInfoList[user][lockId].reward;
        }
    }

    /**
     * @dev claim user's rewards
     * @param user user's address for claim
     * @param lockId user's lock id
     */
    function claimRewards(address user, uint256 lockId) external nonReentrant whenNotPaused {
        require(user == msg.sender, 'StakingVault: Not permission.');
        LockInfo storage lockInfo;
        uint256 rewards;
        uint256 addReward;
        // claim all user's rewards.
        if (lockId == 0) {
            for (uint256 i = 1; i <= lockIdList[user]; i++) {
                addReward = _earned(user, i);
                lockInfo = lockInfoList[user][i];
                rewards = rewards + lockInfo.reward + addReward;
                lockInfo.reward = 0;
                totalRewards += addReward;
                lockInfo.updatedTime = block.timestamp;
            }
            if (rewards > 0) {
                stakingToken.safeTransfer(user, rewards);
            }
        } else {
            _updateReward(msg.sender, lockId);
            rewards = lockInfo.reward;
            if (rewards > 0) {
                lockInfo.reward = 0;
                stakingToken.safeTransfer(user, rewards);
            }
        }
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
    ) external whenNotPaused isLocked(lockId) {
        require(user == msg.sender, 'StakingVault: Not permission.');
        LockInfo storage lockInfo = lockInfoList[user];
        require(
            block.timestamp <= lockInfo.createdTime + lockInfo.period,
            "StakingVault: Lock's deadline has expired."
        );
        _updateReward(msg.sender, lockId);
        require(rewards <= lockInfo.reward, 'StakingVault: Not Enough compound rewards.');
        lockInfo.amount += rewards;
        totalLockedAmount += rewards;
        totalRewards -= rewards;
        lockInfo.reward -= rewards;
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
     * @dev owner can set rewardDistributor using this func.
     * @param _distributor distributor address for set
     */
    function setRewardDistributor(address _distributor) external onlyOwner { /// Feedback: No need this function
        distributor = _distributor;
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
     * @dev RewardDistributor function
     */
    function addRewards(uint256 reward)
        external
        onlyRewardDistributor
        isApproved(msg.sender, reward)
    {
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
    ) internal nonReentrant whenNotPaused isApproved(user, amount) returns (uint256 lockId) {
        require(amount > 0, 'StakingVault: a.mount zero.');
        require(lockInfoList[msg.sender].amount == 0, 'StakingVault: You have already locked it.');
        require(MIN_LOCK_DAYS <= period && period <= MAX_LOCK_DAYS, 'StakingVault: period error.');
        LockInfo storage lockInfo = lockInfoList[user];
        lockInfo.amount = amount;
        lockInfo.period = period;
        lockInfo.createdTime = block.timestamp;
        lockInfo.updatedTime = block.timestamp;
        totalLockedAmount += amount;
        stakingToken.safeTransferFrom(user, address(this), amount);
        lockId = ++lockIdList[user];
    }

    /**
     * @dev you can get user's rewards via this function.
     * @param user user's address
     * @param lockId user's lock id
     * @return rewards
     */
    function _earned(address user, uint256 lockId) internal view returns (uint256 rewards) {
        require(lockId <= lockIdList[user], 'StakingVault: lockId not exist.');
        uint256 period;
        uint256 reward;
        if (lockId == 0) {
            for (uint256 i = 1; i <= lockIdList[user]; i++) {
                period = block.timestamp - lockInfoList[user][i].updatedTime;
                reward = (period * lockInfoList[user][i].amount) * _getRewardPerTokenForOneSecond();
                reward /= 1e18;
                rewards += reward;
            }
        } else {
            LockInfo storage lockInfo = lockInfoList[user][lockId];
            period = block.timestamp - lockInfo.updatedTime;
            reward = (period * lockInfo.amount) * _getRewardPerTokenForOneSecond();
            reward /= 1e18;
            rewards = reward;
        }
    }

    /**
     * @dev users can update user's rewards via this function.
     * @param user user's address
     */
    function _updateReward(address user, uint256 lockId) internal {
        require(lockId <= lockIdList[user], 'StakingVault: lockId not exist.');
        LockInfo storage lockInfo;
        uint256 addReward;
        addReward = _earned(user, lockId);
        lockInfo = lockInfoList[user][lockId];
        if (addReward > 0) {
            lockInfo.reward += addReward;
            totalRewards += addReward;
            lockInfo.updatedTime = block.timestamp;
        }
    }

    /**
     * @dev users can get formula's rewards_per_token_for_one_second via this function.
     */
    function _getRewardPerTokenForOneSecond() internal view returns (uint256 secondReward) {
        secondReward =
            ((totalRewards * 1e18) / (totalLockedAmount == 0 ? 1 : totalLockedAmount)) /
            MAX_LOCK_DAYS;
    }
}
