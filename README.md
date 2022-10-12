# 🚩 Staking Vault

Users will lock ERC20 token into the vault for up to 4 years and earn more as rewards. <br/>
Staking and reward Tokens are same. <br/>
Example: If you lock 100 USDT tokens, you will get more USDT tokens as rewwards when unlock. <br/>

## Main logic

### Reward Mechanism

- User rewards will be calculated with the below formula.

```
user_rewards = (user_locked_amount * rewards_per_token_for_one_second) * (locked_period_in_seconds)
```

- rewards_per_token_for_one_second will be updated using the below formula.

```
rewards_per_token_for_one_second = (totalRewards / totalLockedAmount) / 4_years_in_seconds
```

### Other Features

- User's lock period should be longer than MINIMUM_LOCK_PERIOD (1 month).

- Users can't withdraw before their lock period.

## Functions Functions

### User side functions

- lock: create lock with amount and period (max period is 4 years)

```js
function lock(uint256 amount, uint256 period) external {}
```

- increaselock: increase lock amount or period

```js
function increaseLock(uint256 amount, uint256 period) external {}
```

- unlock: unlock locked tokens with rewards (only after minimum lock period of 1 week)

```js
function unLock(uint256 amount, uint256 period) external {}
```

- getClaimableRewards: returns user's claimable rewards

```js
function getClaimableRewards(address user) external returns (uint256) {}
```

- claimRewards: claim user's rewards

```js
function claimRewards(address user) external {}
```

- compound: lock user's rewards tokens into vault again

```js
  function compound(address user, uint256 rewards) external {}
```

- specialUnLock 💢 : user can unlock before lock time but that time is bigger than admin's MINIMUM_UNLOCK.
  @notice At that time, user can't get reward.

```js
  function specialUnLock(uint256 amount) external {}
```


- transfer 💢 : user can tranfer reward amount from one to other user.

```js
  function transfer(address user, address receiver, uint256 reward) external {}
```

- flashLoan 💢 : users can call this function to do flashloan borrow using ERC3156 Flash Loan. If flashLoan status is successful, flashLoanFee will be tranferred to StakingVault.

```js
  function flashLoan(
      IERC3156FlashBorrower _receiver,
      address _token,
      uint256 _amount,
      bytes calldata _data
    ) external returns (bool)
 ```

### Admin Functions

- lockFor: create lock for other user

```js
function lockFor(address user, uint256 amount, uint256 period) external {}
```

- setRewardDistributor: owner can set rewardDistributor using this function

```js
function setRewardDistributor(address distributor) external {}
```

- pause/unpause contract


- unLockfor 💢 : admin can unlock user's amount..

```js
  function unLockFor(address user, uint256 reward) external {}
```

- updateCode 💢 : This contract is using UUPS proxy pattern and admin can upgrade using updateCode function.

```js
  function updateCode(address newCode) external {}
```

- updateFlashloanRate 💢 : Admin can update the flashLoanRate using this function.

```js
  function updateFlashloanRate(uint256 newRate) external {}
```

- emergencyUnLock 💢 : Admin can call this function to do emergency unLock Staking ERC20 token when the StakingVault is paused.

```js
  function emergencyUnLock(address user, uint256 amount) external {}
```

### rewardDistribution function

- notifyRewardAmount 💢 : rewardDistributor will call this function after adding or removing funds to distribute as rewards. (add: true, remove: false)

```js
function notifyRewardAmount(uint256 reward, bool status) external onlyRewardDistributor {
    // The reward tokens must have already been transferred to this contract before calling this function
}
```
