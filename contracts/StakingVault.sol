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
    uint256 public constant MAXIMUM_LOCK_PERIOD = 4 * 365 days;
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
        uint256 sigmaX; // Σ user_locked_amount * locked_period_in_seconds created when increaseLock.
        uint256 reward; // realReward * 1e18
        bool lockStatus; // lock or unlock: true: false;
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

    modifier moreThanZero(uint256 amount) {
        require(amount > 0, 'amount is zero.');
        _;
    }

    modifier isLocked() {
        require(
            lockInfoList[msg.sender].lockStatus == true,
            'StakingVault: You must be create lock.'
        );
        _;
    }

    modifier isApproved(uint256 amount) {
        require(
            stakingToken.allowance(msg.sender, address(this)) >= amount,
            'StakingVault: You must be approve.'
        );
        _;
    }

    modifier updateReward(address _user) {
        lockInfo storage LockInfo = lockInfoList[_user];
        uint256 prevReward = LockInfo.reward;
        uint256 addReward = _getClaimableAddRewards(_user);
        if (addReward > 0) {
            LockInfo.sigmaX = 0;
            LockInfo.reward += addReward;
            total_rewards += addReward;
        }
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
        moreThanZero(amount)
        isPeriod(period)
        isApproved(amount)
    {
        require(
            lockInfoList[msg.sender].lockStatus == false,
            'StakingVault: You have already locked it.'
        );
        require(
            stakingToken.allowance(msg.sender, address(this)) >= amount,
            'StakingVault: You must be approve.'
        );
        stakingToken.transferFrom(msg.sender, address(this), amount);
        _lock(msg.sender, amount, period);
    }

    /**
     * @dev increase lock with amount and period.
     * @param amount amount for increase lock.
     * @param period period for increase lock.
     */
    function increaselock(uint256 amount, uint256 period)
        external
        isUnPaused
        isLocked
        moreThanZero(amount)
        isApproved(amount)
        updateReward(msg.sender)
    {
        lockInfo storage LockInfo = lockInfoList[msg.sender];
        require(
            period + LockInfo.period < MAXIMUM_LOCK_PERIOD,
            'StakingVault: increase period error.'
        );
        stakingToken.transferFrom(msg.sender, address(this), amount);
        uint256 lockedPeriod = block.timestamp - LockInfo.updateTime;
        lockedPeriod = lockedPeriod >= LockInfo.period ? LockInfo.period : lockedPeriod;
        LockInfo.sigmaX += LockInfo.amount * lockedPeriod;
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
    function unlock(uint256 amount, uint256 period)
        external
        isUnPaused
        isLocked
        moreThanZero(amount)
        updateReward(msg.sender)
    {
        lockInfo storage LockInfo = lockInfoList[msg.sender];
        require(
            block.timestamp - LockInfo.startTime >= 7 days + LockInfo.period,
            'StakingVault: You can unlock after lock period.'
        );
        require(amount <= LockInfo.amount, 'Amount error.');
        uint256 reward = LockInfo.reward;
        LockInfo.reward = 0;
        total_rewards -= reward;
        LockInfo.amount -= amount;
        total_locked_amount -= amount;
        stakingToken.transfer(msg.sender, amount + reward);
    }

    /**
     * @dev you can get user's claimable rewards.
     * @param user user's address
     * @return reward
     */
    function getClaimableRewards(address user) public view isUnPaused returns (uint256 reward) {
        lockInfo storage LockInfo = lockInfoList[user];
        reward = (_getClaimableAddRewards(user) + LockInfo.reward);
    }

    /**
     * @dev claim user's rewards
     * @param user user's address for claim
     */
    function claimRewards(address user) external isUnPaused updateReward(user) {
        require(user == msg.sender, 'StakingVault: Not permission.');
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
    function compound(address user, uint256 rewards) external isUnPaused {
        lockInfo storage LockInfo = lockInfoList[user];
        require(user == msg.sender, 'StakingVault: Not permission.');
        require(rewards <= LockInfo.reward, 'StakingVault: Not Enough compound rewards.');

        LockInfo.amount += rewards;
        LockInfo.reward -= rewards;
    }

    function getRewardPerTokenForOneSecond() internal view returns (uint256 secondReward) {
        secondReward =
            ((total_rewards * 1e18) / (total_locked_amount == 0 ? 1 : total_locked_amount)) /
            MAXIMUM_LOCK_PERIOD;
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
     * @dev RewardDistributor function
     */
    function notifyRewardAmount(uint256 reward) external onlyRewardDistributor isApproved(reward) {
        stakingToken.transferFrom(msg.sender, address(this), reward);
        total_rewards += reward;
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
        total_locked_amount += amount;
    }

    /**
     * @dev you can get user's claimable rewards.
     * @param user user's address
     * @return reward
     */
    function _getClaimableAddRewards(address user) internal view returns (uint256 reward) {
        lockInfo storage LockInfo = lockInfoList[user];
        reward = ((LockInfo.sigmaX + (block.timestamp - LockInfo.updateTime) * LockInfo.amount) *
            getRewardPerTokenForOneSecond());
        console.log('period is ', block.timestamp, LockInfo.updateTime);
        reward /= 1e18;
    }
}
