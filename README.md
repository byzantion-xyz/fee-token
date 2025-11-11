# Fee Token Module

A Sui Move module for managing fee-based token systems with automatic fee distribution capabilities.

## Overview

The Fee Token module provides a comprehensive system for creating and managing tokens with built-in fee mechanisms. It allows for:
- Token creation with customizable fee policies
- Automatic fee distribution to multiple recipients
- Secure token management with access controls
- Deposit/withdrawal operations with automatic fee deduction

## Features

- **Multi-recipient fee distribution**: Configure multiple fee recipients with different percentages
- **Derived object system**: Uses Sui's derived object pattern for deterministic token addresses
- **Lock mechanism**: Ensures proper handling of deposits and withdrawals with fee calculations
- **Event emission**: Comprehensive event logging for all major operations
- **Access control**: Policy-based management with capability objects

## Core Components

### 1. FeeTokenRegistry
Central registry that tracks all registered fee token policies.

### 2. FeeTokenPolicy
Manages fee configuration for a specific token type:
- Total fee percentage (up to 100%)
- Individual fee recipients and their percentages
- Balance tracking for fee recipients

### 3. FeeToken
The actual token object containing:
- Unique derived ID
- Owner address
- Token balance

### 4. DepositLock
Ensures atomic deposit operations with proper fee calculations.

## Error Codes

- `EAlredyRegistered` (1): Token type already registered
- `ETreasuryCapSupplyIsNotZero` (2): Treasury cap must have zero supply before minting
- `EAccessDenied` (3): Unauthorized access attempt
- `EInvalidTotalFee` (4): Total fees exceed 100%
- `ENotEnoughBalance` (5): Insufficient token balance
- `EDepositLockAmountIsNotZero` (6): Lock must be fully consumed

## Events

The module emits the following events:
- `NewFeeTokenEvent`: When a new token is created
- `WithdrawFeeTokenEvent`: When tokens are withdrawn
- `DepositFeeTokenEvent`: When tokens are deposited (includes fee amount)

## Security Considerations

1. **Access Control**: Only policy cap holders can modify fee configurations
2. **Balance Protection**: Withdrawals require proper ownership verification
3. **Fee Limits**: Total fees cannot exceed 100% (10000 basis points)
4. **Atomic Operations**: Deposit locks ensure complete operations

## Dependencies

- Sui Framework (mainnet version)
- Move Standard Library