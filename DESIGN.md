# 🚩 Staking-Vault Contract Design.

## **StakingVault** contract

- FlashBorrow Contract:  User's contract `whiteListed Contract`
- Vault Contract:  `Main Contract`
- Proxy Contract: `UUPS contract`
- Proxiable Contract: `UUPS contract`

## **StakingVault Variables** 📋

> constant MIN_LOCK_DAYS and MAX_LOCK_DAYS 
```js
  uint256 public constant MIN_LOCK_DAYS = 30 days;
  uint256 public constant MAX_LOCK_DAYS = 1460 days;
```

> uint256 **totalRewards**
  At this time StakingVault's reward amount.

> uint256 **totalLockedAmount**
  At this time StakingVault's locked amount.

> address **distributor**
  user who add reward into stakingVault for calculating reward.

> address **stakingToken**
  stakingVault's ERC20Token address

> struct **LockInfo**
- Contract's status and approved users.
```js
  struct LockInfo {
    uint256 amount;
    uint256 period;
    uint256 createdTime;
    uint256 updatedTime;
    uint256 reward;
  }
```

> mapping **lockInfoList**
```js
  // mapping (User address => (LockId => LockInfo))
  mapping(address => mapping(uint256 => LockInfo)) public lockInfoList;
```

> mapping **lockIdList**
```js
  // mapping (User address => LockMaxId)
  mapping(address => uint256) public lockIdList;
```

## **StakingVault** Contract (Main Action) 🔧

> function **lock**()     
```js
  /**@dev User can lock with below params.
   * @param amount amount to create lock.
   * @param period period to create lock.
   * @return lockId When create lock, User can get lockId.()
   */
  function lock(
    uint256 amount,  
    uint256 period,
  ) external returns(uint256 lockId);
```

> function **increaseLock**()     
```js
  /**@dev User can increaselock with below params.
   * @param lockId lockId to increase.
   * @param amount amount to increase lock.
   * @param amount period to increase lock.
   */
  function increaseLock(
    uint256 lockId,
    uint256 amount,  
    uint256 period,
  ) external ;
```

> function **unLock**()     
```js
  /**@dev User can unlock with below params.
   * @param lockId lockId to withdraw.
   * @Notice if lockId is 0, updateReward function can calculate all rewards.
   * @param amount period to increase lock.
   * @param withRewards true: claim reward. false: claim reward.
   */
  function unLock(
    uint256 lockId,
    uint256 amount,  
    bool withRewards  
  ) external ;
```

> function **getClaimableRewards**()     
```js
  /**@dev User can view their claimable rewards.
   * @param lockId lockId to withdraw.
   * @Notice if lockId is 0, updateReward function can calculate all rewards.
   * @param user user's address.
   * @param rewards user's reward
   */
  function getClaimableRewards(
    uint256 lockId,
    address user  
  ) external returns(uint256 rewards);
```

> function **claimRewards**()     
```js
  /**@dev User can get their claimable rewards.
   * @param lockId lockId to withdraw.
   * @Notice if lockId is 0, updateReward function can calculate all rewards.
   * @param user user's address.
   * @param rewards user's reward
   */
  function claimRewards(
    uint256 lockId,
    address user  
  ) external;
```

> function **compound**()     
```js
  /**@dev User can lock their rewards into vault again.
   * @param lockId lockId to compound.
   * @param user user's address.
   * @param rewards user's reward to compound
   */
  function compound(
    uint256 lockId,
    address user,
    uint256 rewards  
  ) external;
```

## **StakingVault** Contract (Admin Actions) 🤖

> function **lockFor**()     
```js
  /**@dev admin can lock with below params for user.
   * @param user amount to create lock.
   * @param amount amount to create lock.
   * @param period period to create lock.
   * @return lockId When create lock, User can get lockId.()
   */
  function lockFor(
    address user,  
    uint256 amount,  
    uint256 period,
  ) external returns(uint256 lockId);
```

> function **setPause**()
```js
  /**
   * @dev Admin can pause/unpause all the above main functions.
   * @param _paused paused status(true: pause, false: unpause)
   */
  function setPause(
    bool _paused
  ) external;
```
> function **setRewardDistributor**()
```js
  /**
   * @dev owner can set rewardDistributor using this func.
   * @param _distributor distributor address for set
   */  
  function setRewardDistributor(
    address distributor
  ) external;
```

> function **addRewards**()
```js
  /**
   * @dev distributor can add reward into vault using this function.
   * @Notice msg.sender must be distributor. 
   * @param reward reward to add
   */
  function addRewards(
    uint reward
  ) external;
```


## **StakingVault** Contract (Other Actions) 💢

> function **_earn**()
```js
  /**
   * @dev you can get user's rewards via this function.
   * @param user user's address
   * @param lockId locked id
   * @return reward user's reward for lockId
   */
  function _earn(
    address user,
    uint256 lockId
  ) internal returns (uint256 reward);
```

> function **_updateReward**()
```js
  /**
   * @dev users can update user's rewards via this function.
   * @param user user's address
   */
  function _updateReward(
    address user,
    uint256 lockId
  ) internal ;
```

> function **_getRewardPerTokenForOneSecond**()
```js
  /**
   * @dev users can get formula's rewards_per_token_for_one_second via this function.
   * @return secondReward rewards_per_token_for_one_day = (total_rewards / total_locked_amount) / 4_years_in_days
   */
  function _getRewardPerTokenForOneSecond() internal return (uint256 secondReward);
```

> function **_lock**()
```js
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
  ) internal;
```