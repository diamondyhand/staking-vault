//SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.0;
import 'hardhat/console.sol';
import './interfaces/IERC20.sol';
import '@openzeppelin/contracts/access/Ownable.sol';

// import '@openzeppelin/contracts/security/Pausable.sol';

/**
 * @dev Staking Vault Contract
 */
contract StakingVault is Ownable {
    uint256 public constant MINIMUM_LOCK_PERIOD = 30 days;
    uint256 public constant MAXIMUM_LOCK_PERIOD = 4 * 365 days;
    uint256 public totalRewards;
    uint256 public totalLockedAmount;

    bool public paused;
    address public distributor;
    IERC20 public stakingToken;

    struct lockInfo {
        // locked amount
        uint256 amount;
        // lock period
        uint256 period;
        // lock created time.
        uint256 startTime;
        // update time by increaselock
        uint256 updateTime;
        // Σ user_locked_amount * locked_period_in_seconds created when increaseLock.
        uint256 sigmaX;
        // realReward * 1e18
        uint256 reward;
        // lock or unlock: true: false;
        bool lockStatus;
    }

    // user's address => user's lockInfo
    mapping(address => lockInfo) public lockInfoList;

    /**
     * @param _stakingToken staking ERC20 Token address.
     */
    constructor(address _stakingToken) {
        stakingToken = IERC20(_stakingToken);
    }

    modifier isUnPaused() {
        require(paused == false, 'Contract paused.');
        _;
    }

    modifier isLocked() {
        require(
            lockInfoList[msg.sender].lockStatus == true,
            'StakingVault: You must be create lock.'
        );
        _;
    }

    modifier isApproved(address user, uint256 amount) {
        require(
            stakingToken.allowance(user, address(this)) >= amount,
            'StakingVault: You must be approve.'
        );
        _;
    }

    modifier isNotZero(uint256 amount) {
        require(amount > 0, 'amount is zero.');
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
    function lock(uint256 amount, uint256 period)
        external
        isUnPaused
        isNotZero(amount)
        isApproved(msg.sender, amount)
    {
        require(
            lockInfoList[msg.sender].lockStatus == false,
            'StakingVault: You have already locked it.'
        );
        require(
            MINIMUM_LOCK_PERIOD <= period && period <= MAXIMUM_LOCK_PERIOD,
            'StakingVault: period error.'
        );
        _lock(msg.sender, amount, period);
        totalLockedAmount += amount;
        stakingToken.transferFrom(msg.sender, address(this), amount);
    }

    /**
     * @dev increase lock with amount and period.
     * @param amount amount for increase lock.
     * @param period period for increase lock.
     */
    function increaseLock(uint256 amount, uint256 period)
        external
        isUnPaused
        isLocked
        isNotZero(amount)
        isApproved(msg.sender, amount)
    {
        lockInfo storage LockInfo = lockInfoList[msg.sender];
        require(
            period + LockInfo.period <= MAXIMUM_LOCK_PERIOD,
            'StakingVault: increase period error.'
        );
        require(
            block.timestamp <= LockInfo.startTime + LockInfo.period,
            "StakingVault: Lock's deadline has expired."
        );
        _updateReward(msg.sender);
        LockInfo.period += period;
        LockInfo.amount += amount;
        totalLockedAmount += amount;
        stakingToken.transferFrom(msg.sender, address(this), amount);
    }

    /**
     * @dev unlock locked tokens with rewards.
     * @param amount amount for unlock.
     */
    function unLock(uint256 amount) external isUnPaused isLocked isNotZero(amount) {
        lockInfo storage LockInfo = lockInfoList[msg.sender];
        require(
            block.timestamp - LockInfo.startTime >= 7 days + LockInfo.period,
            'StakingVault: You can unlock after lock period.'
        );
        require(amount <= LockInfo.amount, 'StakingVault: unlock amount error.');
        _updateReward(msg.sender);
        uint256 reward = LockInfo.reward;
        totalRewards -= reward;
        totalLockedAmount -= amount;
        LockInfo.reward = 0;
        LockInfo.amount -= amount;
        if (LockInfo.amount == 0) {
            LockInfo.startTime = 0;
            LockInfo.updateTime = 0;
            LockInfo.lockStatus = false;
            LockInfo.period = 0;
        }
        stakingToken.transfer(msg.sender, amount + reward);
    }

    /**
     * @dev you can get user's claimable rewards.
     * @param user user's address
     * @return reward
     */
    function getClaimableRewards(address user) public view isUnPaused returns (uint256 reward) {
        reward = _earned(user) + lockInfoList[user].reward;
    }

    /**
     * @dev claim user's rewards
     * @param user user's address for claim
     */
    function claimRewards(address user) external isUnPaused {
        require(user == msg.sender, 'StakingVault: Not permission.');
        _updateReward(msg.sender);
        lockInfo storage LockInfo = lockInfoList[user];
        uint256 reward = LockInfo.reward;
        if (reward > 0) {
            LockInfo.reward = 0;
            stakingToken.transfer(user, reward);
        }
    }

    /**
     * @dev lock user's rewards token into vault again.
     * @param user user's address for increaselock
     * @param rewards reward for increaselock
     */
    function compound(address user, uint256 rewards) external isUnPaused isLocked {
        require(user == msg.sender, 'StakingVault: Not permission.');
        lockInfo storage LockInfo = lockInfoList[user];
        require(
            block.timestamp <= LockInfo.startTime + LockInfo.period,
            "StakingVault: Lock's deadline has expired."
        );
        _updateReward(msg.sender);
        require(rewards <= LockInfo.reward, 'StakingVault: Not Enough compound rewards.');
        LockInfo.amount += rewards;
        totalLockedAmount += rewards;
        totalRewards -= rewards;
        LockInfo.reward -= rewards;
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
    ) external onlyOwner isNotZero(amount) isApproved(user, amount) {
        require(
            lockInfoList[user].lockStatus == false,
            'StakingVault: You have already locked it.'
        );
        require(
            MINIMUM_LOCK_PERIOD <= period && period <= MAXIMUM_LOCK_PERIOD,
            'StakingVault: period error.'
        );
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
     * @param status (pause or unPause) => true or false
     */
    function setPause(bool status) external onlyOwner {
        paused = status;
    }

    /**
     * @dev RewardDistributor function
     */
    function notifyRewardAmount(uint256 reward)
        external
        onlyRewardDistributor
        isNotZero(reward)
        isApproved(msg.sender, reward)
    {
        stakingToken.transferFrom(msg.sender, address(this), reward);
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
    ) internal {
        lockInfo storage LockInfo = lockInfoList[user];
        LockInfo.amount = amount;
        LockInfo.period = period;
        LockInfo.startTime = block.timestamp;
        LockInfo.updateTime = block.timestamp;
        LockInfo.lockStatus = true;
    }

    /**
     * @dev you can get user's rewards via this function.
     * @param user user's address
     * @return reward
     */
    function _earned(address user) internal view returns (uint256 reward) {
        lockInfo storage LockInfo = lockInfoList[user];
        uint256 period = block.timestamp - LockInfo.updateTime;
        if (block.timestamp > LockInfo.startTime + LockInfo.period) {
            period = LockInfo.startTime + LockInfo.period - LockInfo.updateTime;
        }
        reward = (period * LockInfo.amount) * _getRewardPerTokenForOneSecond();
        reward /= 1e18;
    }

    function _updateReward(address _user) internal {
        lockInfo storage LockInfo = lockInfoList[_user];
        uint256 addReward = _earned(_user);
        if (addReward > 0) {
            LockInfo.reward += addReward;
            totalRewards += addReward;
            LockInfo.updateTime = block.timestamp;
        }
    }

    function _getRewardPerTokenForOneSecond() internal view returns (uint256 secondReward) {
        secondReward =
            ((totalRewards * 1e18) / (totalLockedAmount == 0 ? 1 : totalLockedAmount)) /
            MAXIMUM_LOCK_PERIOD;
    }
}
