# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Build and Test Commands

```bash
# Build the project
sui move build

# Run all tests
sui move test

# Run a specific test
sui move test transfer_fee_token_test
```

## Architecture Overview

This is a Sui Move module for managing fee-based token systems with automatic fee distribution.

### Core Flow

1. **Initialization**: `init_fee_token_currency` creates policy and returns two separate capability objects
2. **Minting**: `mint_fee_token_balance` creates initial supply with a deposit lock
3. **Finalization**: `finalize_fee_token_currency` shares the policy and completes setup
4. **Operations**: Withdraw creates a `DepositLock`, deposit consumes it while applying fees

### Key Design Patterns

- **Derived Objects**: `FeeToken` uses `derived_object::claim` for deterministic addresses based on owner
- **Separated Capabilities**: `FeeTokenPolicyFeesCap` (fee config) and `FeeTokenPolicyFeeModeCap` (fee modes) are separate for granular access control
- **Deposit Lock Pattern**: Withdrawals return a `DepositLock` that must be fully consumed by deposits - ensures atomic fee calculation

### Fee Mode System

Three modes control fee behavior:
- `FEE_MODE_ON` (0): Default - fees charged on deposit
- `FEE_MODE_OFF` (1): Receiver opts out of fees
- `FEE_MODE_FORCE_OFF` (2): Sender blocks fees regardless of receiver

Fee is charged only when: `lock.include_fee && token.fee_mode == FEE_MODE_ON`

### Immutability Strategy

For permanent configuration:
1. Destroy `FeeTokenPolicyFeesCap` via `destroy_fee_token_policy_fees_cap`
2. Destroy `FeeTokenPolicyFeeModeCap` via `destroy_fee_token_policy_fee_mode_cap`
3. Make package immutable: `sui client upgrade --upgrade-capability <cap-id> --make-immutable`