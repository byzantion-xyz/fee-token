# Fee Token Module

A Sui Move module for managing fee-based token systems with automatic fee distribution capabilities.

## Overview

The Fee Token module provides a comprehensive system for creating and managing tokens with built-in fee mechanisms. It allows for:
- Token creation with customizable fee policies
- Automatic fee distribution to multiple recipients
- Secure token management with access controls
- Deposit/withdrawal operations with automatic fee deduction
- Fee mode system to independently control incoming and outgoing fee behavior per account

## Features

- **Multi-recipient fee distribution**: Configure multiple fee recipients with different percentages
- **Derived object system**: Uses Sui's derived object pattern for deterministic token addresses
- **Lock mechanism**: Ensures proper handling of deposits and withdrawals with fee calculations
- **Event emission**: Comprehensive event logging for all major operations
- **Separated access control**: Separate capabilities for fee configuration and fee mode management
- **Fee mode system**: Control fee behavior with four modes (ALL_ON, IN_OFF, OUT_OFF, ALL_OFF)

## Core Components

### 1. FEE_TOKEN (OTW)
One-time witness struct used for module initialization and package claims.

### 2. FeeTokenInitializer
Wrapper for CurrencyInitializer that manages the token currency initialization process.

### 3. FeeTokenRegistry
Central registry that tracks all registered fee token policies. Created and shared during module initialization.

### 4. FeeTokenPolicy
Manages fee configuration for a specific token type:
- Fee modes table for per-address fee settings
- Total fee percentage (up to 100%)
- Individual fee recipients and their percentages
- Balance tracking for fee recipients

### 5. FeeTokenPolicyFeesCap
Capability object for managing fee configuration:
- Add/remove fee recipients
- Modify fee percentages

### 6. FeeTokenPolicyFeeModeCap
Capability object for managing fee modes:
- Set fee mode for individual token owners

### 7. FeeToken
The actual token object containing:
- Unique derived ID
- Fee mode
- Owner address
- Token balance

### 8. DepositLock
Ensures atomic deposit operations with proper fee calculations. This is a hot-potato object (no abilities) that must be consumed within a single transaction.

## Key Operations

### Deposit & Withdraw
- `withdraw_from_address` / `withdraw_from_object`: Withdraw tokens, returns balance and a deposit lock
- `assess_deposit_fee`: Estimate the fee amount for a deposit. Accepts an `is_gross` flag: when `true`, the amount is the gross (pre-fee) amount; when `false`, the amount is the net (post-fee) amount and the function reverse-calculates the fee
- `deposit`: Deposit tokens with automatic fee deduction

### Burn
- `burn_balance_from_address` / `burn_balance_from_object`: Burn tokens permanently

### Fee Management
- `add_fee` / `remove_fee`: Configure fee recipients and percentages
- `withdraw_fee`: Fee recipients can claim their accumulated fees
- `set_fee_mode`: Set fee mode for a token owner

## Fee Modes

The module supports four fee modes that independently control incoming and outgoing fee behavior:

| Constant | Value | Description |
|----------|-------|-------------|
| `FEE_MODE_ALL_ON` | 0 | Default - fees apply on both incoming and outgoing transfers |
| `FEE_MODE_IN_OFF` | 1 | Incoming fees disabled - receiver opts out of paying fees |
| `FEE_MODE_OUT_OFF` | 2 | Outgoing fees disabled - sender opts out of triggering fees |
| `FEE_MODE_ALL_OFF` | 3 | All fees disabled - both incoming and outgoing fees off |

## Error Codes

- `EFeeTypeAlreadyRegistered` (1): Token type already registered
- `ETreasuryCapSupplyIsNotZero` (2): Treasury cap must have zero supply before minting
- `EAccessDenied` (3): Unauthorized access attempt
- `EInvalidFeeMode` (4): Invalid fee mode
- `EInvalidReceiverFee` (5): Fee receiver percentage must be greater than zero
- `EInvalidTotalFee` (6): Total fees exceed 100%
- `EFeeTypeNotRegistered` (7): Fee type not registered
- `ENotEnoughBalance` (8): Insufficient token balance
- `EDepositAmountIsTooLow` (9): Deposit amount too small (fee would round to zero)
- `EDepositLocksAreNotCompatible` (10): Deposit locks have incompatible fee settings
- `EDepositLockAmountIsNotZero` (11): Lock must be fully consumed

## Events

The module emits the following events:
- `NewFeeTokenEvent`: When a new token is created
- `WithdrawFeeTokenEvent`: When tokens are withdrawn
- `DepositFeeTokenEvent`: When tokens are deposited (includes fee amount)
- `BurnBalanceFeeTokenEvent`: When tokens are burned

## Security Considerations

1. **Separated Access Control**: Fee configuration and fee mode management use separate capabilities
2. **Immutability Option**: Capabilities can be destroyed to make configuration immutable
3. **Balance Protection**: Withdrawals require proper ownership verification
4. **Fee Limits**: Total fees cannot exceed 100% (10000 basis points)
5. **Atomic Operations**: Deposit locks (hot-potato) ensure complete operations within a single transaction
6. **Package Immutability**: For full immutability, make the package immutable after destroying caps
7. **Minimum Deposit Amount**: Deposits must be large enough that each fee recipient receives at least 1 unit, preventing rounding exploits
8. **Non-zero Fee Requirement**: Fee recipients must have a fee percentage greater than zero