//SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.0;
import 'hardhat/console.sol';
import './interfaces/IERC20.sol';
import '@openzeppelin/contracts/access/Ownable.sol';

/**
 * @dev Staking Vault Contract
 */
contract StakingVault is Ownable {
    uint256 public constant MINIMUM_LOCK_PERIOD = 30 days;
    uint256 public constant MAXIMUM_LOCK_PERIOD = 4 * 365 + 1 days;

    uint256 public total_rewards;
    uint256 public total_locked_amount;

    bool public paused;
    address public distributor;
    IERC20 public stakingToken;

    struct lockInfo {
        uint256 amount;
        uint256 period;
        uint256 startTime;
        uint256 updateTime; // update time by increaselock
        uint256 xSum; // Σ user_locked_amount * locked_period_in_seconds created when increaseLock.
        bool lockStatus; // lock or unlock: true: false;
        // bool isCreated; // created: true
    }

    mapping(address => lockInfo) public lockInfoList;

    constructor(address _stakingToken) {
        stakingToken = IERC20(_stakingToken);
    }

    modifier isPeriod(uint256 period) {
        require(
            period >= MINIMUM_LOCK_PERIOD && period <= MAXIMUM_LOCK_PERIOD,
            'StakingVault: period error.'
        );
        _;
    }

    modifier isUnPaused() {
        require(paused == false, 'Contract paused.');
        _;
    }

    /// user side functions

    /**
     * @dev create lock with amount and period.
     * Note: maximum period is 4 years, minimum period is one month.
     * @param amount amount for lock.
     * @param period period for lock.
     */
    function lock(uint256 amount, uint256 period) external isUnPaused isPeriod(period) {
        _lock(msg.sender, amount, period);
    }

    /**
     * @dev increase lock with amount and period.
     * @param amount amount for increase lock.
     * @param period period for increase lock.
     */
    function increaselock(uint256 amount, uint256 period) external isUnPaused {
        lockInfo storage LockInfo = lockInfoList[msg.sender];
        require(LockInfo.lockStatus == true, 'StakingVault: You must be create lock.');
        uint256 lockedPeriod = block.timestamp - LockInfo.updateTime;
        lockedPeriod = lockedPeriod >= LockInfo.period ? LockInfo.period : lockedPeriod;
        LockInfo.xSum += LockInfo.amount * lockedPeriod;
        LockInfo.period += period;
        LockInfo.amount += amount;
        LockInfo.updateTime = block.timestamp;
        total_locked_amount += amount;
    }

    /**
     * @dev unlock locked tokens with rewards.
     * @param amount amount for unlock.
     * @param period period for unlock.
     */
    function unlock(uint256 amount, uint256 period) external isUnPaused isPeriod(period) {
        lockInfo storage LockInfo = lockInfoList[msg.sender];
        require(LockInfo.lockStatus == true, 'StakingVault: You must be create lock.');
        require(block.timestamp - LockInfo.startTime >= 7 days, "StakingVault: You can't unlock.");
        LockInfo.lockStatus = false;
        // LockInfo.amount += amount;
        // LockInfo.period += period;
        // LockInfo.deadline = block.timestamp + period;
    }

    /**
     * @dev you can get user's claimable rewards.
     * @param user user's address
     * @return reward
     */
    function getClaimableRewards(address user) public view isUnPaused returns (uint256 reward) {
        require(user == msg.sender, 'StakingVault: Not permission.');
        lockInfo storage LockInfo = lockInfoList[user];
        reward =
            (LockInfo.xSum + block.timestamp * LockInfo.updateTime) *
            getRewardPerTokenForOneSecond();
    }

    /**
     * @dev claim user's rewards
     * @param user user's address for claim
     */
    function claimRewards(address user) external isUnPaused {
        require(user == msg.sender, 'StakingVault: Not permission.');
        // stakingToken.transfer(user, getClaimableRewards(user));
    }

    /**
     * @dev lock user's rewards token into vault again.
     * @param user user's address for increaselock
     * @param rewards reward for increaselock
     */
    function compound(address user, uint256 rewards) external isUnPaused {
        require(user == msg.sender, 'StakingVault: Not permission.');
        require(rewards < getClaimableRewards(user), 'StakingVault: Not Enough compound rewards.');

        stakingToken.transfer(user, rewards);
        uint256 userReward = getClaimableRewards(user) - rewards;
        // _increaselock(user, rewards, 0);
    }

    function getRewardPerTokenForOneSecond() internal view returns (uint256 secodeReward) {
        secodeReward = (total_rewards / total_locked_amount) / MAXIMUM_LOCK_PERIOD;
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
     * @param status (pause or unPause) => true or false
     */
    function setPause(bool status) external onlyOwner {
        paused = status;
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
        lockInfo storage newInfo = lockInfoList[user];
        total_locked_amount += amount;
        newInfo.amount = amount;
        newInfo.period = period;
        newInfo.startTime = block.timestamp;
        newInfo.updateTime = block.timestamp;
        newInfo.lockStatus = true;
    }
}
