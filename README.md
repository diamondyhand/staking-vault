# Staking Vault

- Users will lock ERC20 token into the vault for up to 4 years and earn more as rewards.
- Users can create multiple locks.
- User's lock period should be longer than MIN_LOCK_DAYS (1 month = 30 days) and smaller than MAX_LOCK_DAYS (4 years = 1460 days)
- Locks can be created only after there're some rewards to distribute on the vault contract.
- Users can't withdraw before their lock period, but can claim rewards if there're.

## Main logic

### Reward Mechanism

User rewards will be calculated based on days of lock.

- rewards_per_token_for_one_day

```
rewards_per_token_for_one_day = (total_rewards / total_locked_amount) / 4_years_in_days
```

- user_rewards_per_lock

```
user_rewards_per_lock = (locked_amount * rewards_per_token_for_one_day) * (locked_period_in_days)
```

- User rewards are total sum of user_rewards_per_lock.

## Functions

### User side functions

#### lock

- create lock with token amounts and lock period (max period is 4 years)
- return lockId

```
function lock(uint256 amount, uint256 period) external returns {uint256 lockId}
```

#### increaselock

- increase lock amount or period

```
function increaselock(uint256 lockId, uint256 amount, uint256 period) external {}
```

#### unlock

- unlock locked tokens with rewards (only after minimum lock period of 1 month)
- if tokenId is 0, then it will unlock all locks.

```
function unlock(uint256 lockId, uint256 amount, bool withRewards) external {}
```

#### getClaimableRewards

- returns user's claimable rewards
- if lockId is 0, then will calculate total rewards for all locks

```
function getClaimableRewards(uint256 lockId, address user) external returns (uint256) {}
```

#### claimRewards

- claim user's rewards
- if lockId is 0, then will claim total rewards for all lcoks

```
function claimRewards(address user) external {}
```

### compound

- lock user's rewards into vault again
- this is for one lock.

```
  function compound(uint256 lockId, address user, uint256 rewards) external {}
```

### Admin Functions

#### lockFor

- create lock for other user

```
function lockFor(address user, uint256 amount, uint256 period) external {}
```

#### pause/unpause functions

### Adding tokens to distribute as rewards

#### addRewards: this function will retrieve rewards from caller for reward distribution.

```
function addRewards(uint256 reward) external {}
```
