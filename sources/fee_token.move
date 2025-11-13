module fee_token::fee_token;

use std::type_name::{Self, TypeName};
use sui::balance::{Self, Balance};
use sui::coin::TreasuryCap;
use sui::coin_registry::{CurrencyInitializer, MetadataCap, new_currency};
use sui::derived_object;
use sui::event;
use sui::package;
use sui::table::{Self, Table};
use sui::vec_map::{Self, VecMap};

// Constants
const MAX_BPS: u16 = 10000;

// Errors
const EAlreadyRegistered: u64 = 1;
const ETreasuryCapSupplyIsNotZero: u64 = 2;
const EAccessDenied: u64 = 3;
const EInvalidFeeMode: u64 = 4;
const EInvalidTotalFee: u64 = 5;
const ENotEnoughBalance: u64 = 6;
const EDepositLockAmountIsNotZero: u64 = 7;

// OTW
public struct FEE_TOKEN has drop {}

// Initializer
public struct FeeTokenInitializer<phantom FT> {
    initializer: CurrencyInitializer<FT>
}

// Registry
public struct FeeTokenRegistry has key {
    id: UID,
    policies: Table<TypeName, ID>,
}

// Policy
public struct FeeTokenPolicy<phantom FT> has key {
    id: UID,
    fee_modes: Table<address, u64>,
    total_fee: u16,
    fees: VecMap<address, u16>,
    balances: VecMap<address, Balance<FT>>,
}

public struct FeeTokenPolicyCap<phantom FT> has key, store {
    id: UID,
    policy_id: ID,
}

// Fee Token
public struct FeeToken<phantom FT> has key {
    id: UID,
    fee_mode: u64,
    owner: address,
    balance: Balance<FT>,
}

public struct FeeTokenKey<phantom FT> has copy, drop, store {
    owner: address,
}

public struct FeeTokenRef has key {
    id: UID,
    token_type: TypeName,
    token_id: ID,
    token_owner: address,
}

// Lock
public struct DepositLock<phantom FT> {
    amount: u64,
    include_fee: bool,
}

// Events
public struct NewFeeTokenEvent has copy, drop {
    token_type: TypeName,
    token_id: ID,
    token_owner: address,
}

public struct WithdrawFeeTokenEvent has copy, drop {
    token_type: TypeName,
    token_id: ID,
    token_owner: address,
    amount: u64,
}

public struct DepositFeeTokenEvent has copy, drop {
    token_type: TypeName,
    token_id: ID,
    token_owner: address,
    amount: u64,
    fee: u64,
}

// Init method
fun init(otw: FEE_TOKEN, ctx: &mut TxContext) {
    package::claim_and_keep(otw, ctx);

    let registry = FeeTokenRegistry {
        id: object::new(ctx),
        policies: table::new(ctx),
    };

    transfer::share_object(registry);
}

// Public methods
public fun init_fee_token_currency<FT>(
    registry: &mut FeeTokenRegistry,
    initializer: CurrencyInitializer<FT>,
    ctx: &mut TxContext,
): (FeeTokenInitializer<FT>, FeeTokenPolicy<FT>, FeeTokenPolicyCap<FT>) {
    let initializer = FeeTokenInitializer { initializer };

    let policy = FeeTokenPolicy<FT> {
        id: object::new(ctx),
        fee_modes: table::new(ctx),
        total_fee: 0,
        fees: vec_map::empty(),
        balances: vec_map::empty(),
    };

    let cap = FeeTokenPolicyCap<FT> {
        id: object::new(ctx),
        policy_id: object::id(&policy),
    };

    let token_type = type_name::with_defining_ids<FT>();

    assert!(!registry.policies.contains(token_type), EAlreadyRegistered);
    registry.policies.add(token_type, object::id(&policy));

    (initializer, policy, cap)
}

public fun mint_fee_token_balance<FT>(
    initializer: &mut FeeTokenInitializer<FT>,
    mut cap: TreasuryCap<FT>,
    supply: u64,
    _ctx: &mut TxContext,
): (Balance<FT>, DepositLock<FT>) {
    assert!(cap.total_supply() == 0, ETreasuryCapSupplyIsNotZero);

    let balance = cap.mint_balance(supply);
    initializer.initializer.make_supply_burn_only(cap);

    (balance, DepositLock { amount: supply, include_fee: false })
}

public fun finalize_fee_token_currency<FT>(
    initializer: FeeTokenInitializer<FT>,
    policy: FeeTokenPolicy<FT>,
    ctx: &mut TxContext,
): MetadataCap<FT> {
    transfer::share_object(policy);

    let FeeTokenInitializer {
        initializer
    } = initializer;

    initializer.finalize(ctx)
}

public fun add_fee<FT>(
    policy: &mut FeeTokenPolicy<FT>,
    cap: &FeeTokenPolicyCap<FT>,
    receiver: address,
    fee_bps: u16,
) {
    assert!(policy.id.to_inner() == cap.policy_id, EAccessDenied);

    if (policy.fees.contains(&receiver)) {
        let (_, old_fee) = policy.fees.remove(&receiver);
        policy.total_fee = policy.total_fee - old_fee;
    };

    policy.total_fee = policy.total_fee + fee_bps;
    assert!(policy.total_fee <= MAX_BPS, EInvalidTotalFee);

    policy.fees.insert(receiver, fee_bps);

    if (!policy.balances.contains(&receiver)) {
        policy.balances.insert(receiver, balance::zero());
    };
}

public fun remove_fee<FT>(
    policy: &mut FeeTokenPolicy<FT>,
    cap: &FeeTokenPolicyCap<FT>,
    receiver: address,
) {
    assert!(policy.id.to_inner() == cap.policy_id, EAccessDenied);

    let (_, old_fee) = policy.fees.remove(&receiver);
    policy.total_fee = policy.total_fee - old_fee;
}

public fun withdraw_fee<FT>(token: &mut FeeToken<FT>, policy: &mut FeeTokenPolicy<FT>) {
    if (policy.balances.contains(&token.owner)) {
        let balance = policy.balances.get_mut(&token.owner).withdraw_all();
        token.balance.join(balance);

        if (!policy.fees.contains(&token.owner)) {
            let (_, balance) = policy.balances.remove(&token.owner);
            balance.destroy_zero();
        };
    };
}

public fun new<FT>(
    registry: &mut FeeTokenRegistry,
    owner: address,
    ctx: &mut TxContext,
): FeeToken<FT> {
    let id = derived_object::claim(&mut registry.id, FeeTokenKey<FT> { owner });
    let token = FeeToken<FT> { id, fee_mode: 0, owner, balance: balance::zero() };
    let ref = FeeTokenRef {
        id: object::new(ctx),
        token_type: type_name::with_defining_ids<FT>(),
        token_id: object::id(&token),
        token_owner: owner,
    };

    transfer::transfer(ref, owner);

    event::emit(NewFeeTokenEvent {
        token_type: type_name::with_defining_ids<FT>(),
        token_id: object::id(&token),
        token_owner: owner,
    });

    token
}

public fun set_fee_mode<FT>(
    token: &mut FeeToken<FT>,
    policy: &mut FeeTokenPolicy<FT>,
    cap: &FeeTokenPolicyCap<FT>,
    fee_mode: u64,
) {
    assert!(policy.id.to_inner() == cap.policy_id, EAccessDenied);
    assert!(fee_mode < 3, EInvalidFeeMode);

    if (policy.fee_modes.contains(token.owner)) {
        policy.fee_modes.remove(token.owner);
    };

    if (fee_mode > 0) {
        policy.fee_modes.add(token.owner, fee_mode);
    };

    token.fee_mode = fee_mode;
}

public fun share<FT>(token: FeeToken<FT>) {
    transfer::share_object(token);
}

public fun withdraw_from_address<FT>(
    token: &mut FeeToken<FT>,
    amount: u64,
    ctx: &mut TxContext,
): (Balance<FT>, DepositLock<FT>) {
    assert!(token.owner == ctx.sender(), EAccessDenied);
    assert!(token.balance.value() >= amount, ENotEnoughBalance);

    event::emit(WithdrawFeeTokenEvent {
        token_type: type_name::with_defining_ids<FT>(),
        token_id: object::id(token),
        token_owner: token.owner,
        amount,
    });

    let balance = token.balance.split(amount);
    let lock = DepositLock<FT> { amount, include_fee: (token.fee_mode < 2) };

    (balance, lock)
}

public fun withdraw_from_object<FT>(
    token: &mut FeeToken<FT>,
    object: &UID,
    amount: u64,
): (Balance<FT>, DepositLock<FT>) {
    assert!(token.owner == object.uid_to_address(), EAccessDenied);
    assert!(token.balance.value() >= amount, ENotEnoughBalance);

    event::emit(WithdrawFeeTokenEvent {
        token_type: type_name::with_defining_ids<FT>(),
        token_id: object::id(token),
        token_owner: token.owner,
        amount,
    });

    let balance = token.balance.split(amount);
    let lock = DepositLock<FT> { amount, include_fee: (token.fee_mode < 2) };

    (balance, lock)
}

public fun deposit<FT>(
    token: &mut FeeToken<FT>,
    mut balance: Balance<FT>,
    lock: &mut DepositLock<FT>,
    policy: &mut FeeTokenPolicy<FT>,
) {
    let amount = balance.value();
    let mut fee: u64 = 0;

    if (lock.include_fee && token.fee_mode == 0) {
        policy.fees.keys().do_ref!(|receiver| {
            let fee_amount = mul_div!(amount, *policy.fees.get(receiver), MAX_BPS);
            let fee_balance = balance.split(fee_amount);
            fee = fee + fee_balance.value();
            policy.balances.get_mut(receiver).join(fee_balance);
        });
    };
    lock.amount = lock.amount - amount;
    token.balance.join(balance);

    event::emit(DepositFeeTokenEvent {
        token_type: type_name::with_defining_ids<FT>(),
        token_id: object::id(token),
        token_owner: token.owner,
        amount,
        fee,
    });
}

public fun destroy_lock<FT>(lock: DepositLock<FT>) {
    assert!(lock.amount == 0, EDepositLockAmountIsNotZero);
    let DepositLock { .. } = lock;
}

// Private methods
macro fun mul_div($a: _, $b: _, $c: _): u64 {
    (($a as u128) * ($b as u128) / ($c as u128)) as u64
}