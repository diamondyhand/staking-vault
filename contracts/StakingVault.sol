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
    uint256 public constant MINIMUM_LOCK_PERIOD = 30 days;
    uint256 public constant MAXIMUM_LOCK_PERIOD = 4 * 365 days;
    uint256 public totalRewards;
    uint256 public totalLockedAmount;

    address public distributor;
    IERC20 public stakingToken;
    struct LockInfo {
        // locked amount
        uint256 amount;
        // lock period
        uint256 period;
        // lock created time.
        uint256 startTime;
        // update time by increaselock
        uint256 updateTime;
        // reward
        uint256 reward;
    }

    // user's address => user's LockInfo
    mapping(address => LockInfo) public lockInfoList;

    /**
     * @param _stakingToken staking ERC20 Token address.
     */
    constructor(address _stakingToken) {
        require(_stakingToken != address(0), 'StakingVault: address must not be zero address.');
        stakingToken = IERC20(_stakingToken);
    }

    modifier isLocked() {
        require(lockInfoList[msg.sender].amount > 0, 'StakingVault: You must be create lock.');
        _;
    }

    modifier isApproved(address user, uint256 amount) {
        require(
            stakingToken.allowance(user, address(this)) >= amount,
            'StakingVault: You must be approve.'
        );
        _;
    }

    modifier onlyRewardDistributor() {
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
    function lock(uint256 amount, uint256 period) external {
        _lock(msg.sender, amount, period);
    }

    /**
     * @dev increase lock with amount and period.
     * @param amount amount for increase lock.
     * @param period period for increase lock.
     */
    function increaseLock(uint256 amount, uint256 period)
        external
        nonReentrant
        whenNotPaused
        isLocked
        isApproved(msg.sender, amount)
    {
        LockInfo storage lockInfo = lockInfoList[msg.sender];
        require(
            period + lockInfo.period <= MAXIMUM_LOCK_PERIOD,
            'StakingVault: increase period error.'
        );
        require(
            block.timestamp <= lockInfo.startTime + lockInfo.period,
            "StakingVault: Lock's deadline has expired."
        );
        _updateReward(msg.sender);
        lockInfo.period += period;
        lockInfo.amount += amount;
        totalLockedAmount += amount;
        stakingToken.safeTransferFrom(msg.sender, address(this), amount);
    }

    /**
     * @dev unlock locked tokens with rewards.
     * @param amount amount for unlock.
     */
    function unLock(uint256 amount) external nonReentrant whenNotPaused isLocked {
        LockInfo storage lockInfo = lockInfoList[msg.sender];
        // require("zero");
        require(
            block.timestamp - lockInfo.startTime >= lockInfo.period,
            'StakingVault: You can unlock after lock period.'
        );
        require(amount <= lockInfo.amount, 'StakingVault: unlock amount error.');
        _updateReward(msg.sender);
        uint256 reward = lockInfo.reward;
        totalRewards -= reward;
        totalLockedAmount -= amount;
        lockInfo.reward = 0;
        lockInfo.amount -= amount;
        if (lockInfo.amount == 0) {
            lockInfo.startTime = 0;
            lockInfo.updateTime = 0;
            lockInfo.period = 0;
        }
        stakingToken.safeTransfer(msg.sender, amount + reward);
    }

    /**
     * @dev you can get user's claimable rewards.
     * @param user user's address
     * @return reward
     */
    function getClaimableRewards(address user) public view whenNotPaused returns (uint256 reward) {
        reward = _earned(user) + lockInfoList[user].reward;
    }

    /**
     * @dev claim user's rewards
     * @param user user's address for claim
     */
    function claimRewards(address user) external nonReentrant whenNotPaused {
        require(user == msg.sender, 'StakingVault: Not permission.');
        _updateReward(msg.sender);
        LockInfo storage lockInfo = lockInfoList[user];
        uint256 reward = lockInfo.reward;
        if (reward > 0) {
            lockInfo.reward = 0;
            stakingToken.safeTransfer(user, reward);
        }
    }

    /**
     * @dev lock user's rewards token into vault again.
     * @param user user's address for increaselock
     * @param rewards reward for increaselock
     */
    function compound(address user, uint256 rewards) external whenNotPaused isLocked {
        require(user == msg.sender, 'StakingVault: Not permission.');
        LockInfo storage lockInfo = lockInfoList[user];
        require(
            block.timestamp <= lockInfo.startTime + lockInfo.period,
            "StakingVault: Lock's deadline has expired."
        );
        _updateReward(msg.sender);
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
    ) external onlyOwner {
        _lock(user, amount, period);
    }

    /**
     * @dev owner can set rewardDistributor using this func.
     * @param _distributor distributor address for set
     */
    function setRewardDistributor(address _distributor) external onlyOwner {
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
    function notifyRewardAmount(uint256 reward)
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
    ) internal nonReentrant whenNotPaused isApproved(user, amount) {
        require(amount > 0, 'StakingVault: a.mount zero.');
        require(lockInfoList[msg.sender].amount == 0, 'StakingVault: You have already locked it.');
        require(
            MINIMUM_LOCK_PERIOD <= period && period <= MAXIMUM_LOCK_PERIOD,
            'StakingVault: period error.'
        );
        LockInfo storage lockInfo = lockInfoList[user];
        lockInfo.amount = amount;
        lockInfo.period = period;
        lockInfo.startTime = block.timestamp;
        lockInfo.updateTime = block.timestamp;
        totalLockedAmount += amount;
        stakingToken.safeTransferFrom(user, address(this), amount);
    }

    /**
     * @dev you can get user's rewards via this function.
     * @param user user's address
     * @return reward
     */
    function _earned(address user) internal view returns (uint256 reward) {
        LockInfo storage lockInfo = lockInfoList[user];
        uint256 period = block.timestamp - lockInfo.updateTime;
        reward = (period * lockInfo.amount) * _getRewardPerTokenForOneSecond();
        reward /= 1e18;
    }

    /**
     * @dev users can update user's rewards via this function.
     * @param user user's address
     */
    function _updateReward(address user) internal {
        LockInfo storage lockInfo = lockInfoList[user];
        uint256 addReward = _earned(user);
        if (addReward > 0) {
            lockInfo.reward += addReward;
            totalRewards += addReward;
            lockInfo.updateTime = block.timestamp;
        }
    }

    /**
     * @dev users can get formula's rewards_per_token_for_one_second via this function.
     */
    function _getRewardPerTokenForOneSecond() internal view returns (uint256 secondReward) {
        secondReward =
            ((totalRewards * 1e18) / (totalLockedAmount == 0 ? 1 : totalLockedAmount)) /
            MAXIMUM_LOCK_PERIOD;
    }
}
