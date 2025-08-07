# Yield Vault - Smart Contract Documentation

## Overview
Yield Vault is an automated yield aggregation protocol featuring risk-tiered pools, compound rewards, and dynamic APY optimization for maximizing DeFi returns.

## Problem Solved
- **Yield Fragmentation**: Aggregates yields across strategies
- **Manual Compounding**: Automated compound with bounty incentives
- **Risk Management**: Tiered pools for different risk appetites
- **Gas Inefficiency**: Socialized compounding costs

## Key Features

### Risk Tiers
- **Stable**: Low-risk, stable returns
- **Balanced**: Medium-risk, moderate yields
- **Aggressive**: High-risk, maximum yields

### Core Functionality
- Auto-compounding with bounty rewards
- Lock period bonuses
- Emergency withdrawal system
- Dynamic APY adjustments
- Share-based accounting

## Contract Functions

### Pool Management

#### `create-pool`
- **Parameters**: name, tier, min-deposit, max-capacity, lock-period, compound-frequency, base-apy, strategy-id
- **Returns**: pool-id
- **Access**: Owner only

#### `deposit`
- **Parameters**: pool-id, amount
- **Returns**: shares received
- **Requirements**: Min deposit, capacity check

#### `withdraw`
- **Parameters**: pool-id, shares
- **Returns**: net amount
- **Requirements**: Lock period elapsed

#### `compound-pool`
- **Parameters**: pool-id
- **Returns**: {rewards, bounty}
- **Effect**: Compounds yields, pays bounty

#### `emergency-withdraw`
- **Parameters**: pool-id
- **Returns**: amount
- **Requirements**: Emergency mode active

### Admin Functions
- `pause-pool`: Pause/unpause deposits
- `toggle-emergency-shutdown`: Emergency mode
- `update-pool-apy`: Adjust APY rates
- `update-fees`: Modify fee structure
- `withdraw-fees`: Collect protocol fees

### Read Functions
- `get-pool`: Pool details
- `get-user-position`: User's shares and earnings
- `calculate-user-value`: Current position value
- `get-pending-rewards`: Claimable rewards
- `can-compound`: Check if compounding available

## Usage Examples

```clarity
;; Create a stable yield pool
(contract-call? .yield-vault create-pool
    u"Stable STX Vault"
    "stable"
    u100000      ;; 0.1 STX minimum
    u100000000   ;; 100 STX capacity
    u1440        ;; 1 day lock
    u144         ;; Compound every 2.4 hours
    u500         ;; 5% base APY
    u1)

;; Deposit into pool
(contract-call? .yield-vault deposit u1 u1000000)

;; Compound and earn bounty
(contract-call? .yield-vault compound-pool u1)

;; Withdraw position
(contract-call? .yield-vault withdraw u1 u500)
```

## Fee Structure
- **Performance Fee**: 2% on yields
- **Withdrawal Fee**: 0.1%
- **Compound Bounty**: 0.05% to compounder

## Security Features
1. **Lock Periods**: Prevent hot money
2. **Emergency Shutdown**: Crisis management
3. **Pool Pausing**: Temporary halts
4. **Maximum Capacities**: Risk limits
5. **Share-based Accounting**: Rounding protection

## Pool Mechanics

### Share Calculation
```
shares = (deposit * total_shares) / total_deposits
value = (shares * total_deposits) / total_shares
```

### APY Boost
- Base APY + Tier bonus + Lock bonus
- Stable: +1%, Balanced: +1.5%, Aggressive: +2%
- Lock bonus: 0.01% per day locked

## Deployment
1. Deploy contract
2. Create pools with strategies
3. Set initial APY rates
4. Configure fee structure
5. Monitor and compound regularly

## Testing Checklist
- Pool creation with all tiers
- Deposit/withdraw cycles
- Compounding rewards calculation
- Emergency withdrawal flow
- Fee collection
- APY updates and snapshots

## Risk Management
- Tiered pool structure
- Maximum capacity limits
- Lock period requirements
- Emergency shutdown capability
- Regular APY adjustments
- Performance monitoring
