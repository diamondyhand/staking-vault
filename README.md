# Staking Vault

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
rewards_per_token_for_one_second = (total_rewards / total_locked_amount) / 4_years_in_seconds
```

### Other Features

- User's lock period should be longer than MINIMUM_LOCK_PERIOD (1 month).

- Users can't withdraw before their lock period.

## Functions Functions

### User side functions

- lock: create lock with amount and period (max period is 4 years)

```
function lock(uint256 amount, uint256 period) external {}
```

- increaselock: increase lock amount or period

```
function increaselock(uint256 amount, uint256 period) external {}
```

- unlock: unlock locked tokens with rewards (only after minimum lock period of 1 week)

```
function unlock(uint256 amount, uint256 period) external {}
```

- getClaimableRewards: returns user's claimable rewards

```
function getClaimableRewards(address user) external returns (uint256) {}
```

- claimRewards: claim user's rewards

```
function claimRewards(address user) external {}
```

- compound: lock user's rewards tokens into vault again

```
  function compound(address user, uint256 rewards) external {}
```

### Admin Functions

- lockFor: create lock for other user

```
function lockFor(address user, uint256 amount, uint256 period) external {}
```

- setRewardDistributor: owner can set rewardDistributor using this function

```
function setRewardDistributor(address distributor) external {}
```

- pause/unpause contract

### rewardDistribution function

- notifyRewardAmount: rewardDistributor will call this function after adding funds to distribute as rewards

```
function notifyRewardAmount(uint256 reward) external onlyRewardDistributor {
    // The reward tokens must have already been transferred to this contract before calling this function
}
```
