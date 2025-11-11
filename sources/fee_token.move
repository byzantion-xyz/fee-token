module fee_token::fee_token;

use sui::balance::{Self, Balance};
use sui::coin::{Self, TreasuryCap};
use sui::coin_registry::{CurrencyInitializer, MetadataCap};
use sui::derived_object;
use sui::package;
use sui::table::{Self, Table};
use std::type_name::{Self, TypeName};
use sui::event::emit;
use sui::vec_map::{Self, VecMap};

// Constants
const DENOMINATOR: u128 = 10000;

// Errors
const EAlreadyRegistered: u64 = 1;
const ETreasuryCapSupplyIsNotZero: u64 = 2;
const EAccessDenied: u64 = 3;
const EInvalidTotalFee: u64 = 4;
const ENotEnoughBalance: u64 = 5;
const EDepositLockAmountIsNotZero: u64 = 6;

// OTW
public struct FEE_TOKEN has drop {}

// Registry
public struct FeeTokenRegistry has key {
    id: UID,
    policies: Table<TypeName, ID>,
}

// Policy
public struct FeeTokenPolicy<phantom FT> has key {
    id: UID,
    total_fee: u64,
    fees: VecMap<address, u64>,
    balances: VecMap<address, Balance<FT>>,
}

public struct FeeTokenPolicyCap<phantom FT> has key, store {
    id: UID,
    policy_id: ID,
}

// Fee Token
public struct FeeToken<phantom FT> has key {
    id: UID,
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
        policies: table::new(ctx)
    };
    transfer::share_object(registry);
}

// Public methods
public fun register<FT>(
    registry: &mut FeeTokenRegistry,
    _intlzr: &CurrencyInitializer<FT>,
    ctx: &mut TxContext
): (FeeTokenPolicy<FT>, FeeTokenPolicyCap<FT>) {
    let policy = FeeTokenPolicy<FT> {
        id: object::new(ctx),
        total_fee: 0,
        fees: vec_map::empty(),
        balances: vec_map::empty()
    };

    let cap = FeeTokenPolicyCap<FT> {
        id: object::new(ctx),
        policy_id: object::id(&policy)
    };

    let token_type = type_name::with_defining_ids<FT>();

    assert!(!registry.policies.contains(token_type), EAlreadyRegistered);
    registry.policies.add(token_type, object::id(&policy));

    (policy, cap)
}

public fun mint<FT>(
    policy: FeeTokenPolicy<FT>,
    supply: u64,
    mut intlzr: CurrencyInitializer<FT>,
    mut cap: TreasuryCap<FT>,
    ctx: &mut TxContext
): (Balance<FT>, DepositLock<FT>, MetadataCap<FT>) {
    transfer::share_object(policy);

    assert!(cap.total_supply() == 0, ETreasuryCapSupplyIsNotZero);

    let balance = coin::mint_balance(&mut cap, supply);

    intlzr.make_supply_burn_only(cap);
    let metadata_cap = intlzr.finalize(ctx);

    (balance, DepositLock<FT> { amount: supply, include_fee: false }, metadata_cap)
}

public fun add_fee<FT>(
    policy: &mut FeeTokenPolicy<FT>,
    cap: &FeeTokenPolicyCap<FT>,
    receiver: address,
    fee: u64
) {
    assert!(object::id(policy) == cap.policy_id, EAccessDenied);

    if (policy.fees.contains(&receiver)) {
        let (_, old_fee) = policy.fees.remove(&receiver);
        policy.total_fee = policy.total_fee - old_fee;
    };

    policy.total_fee = policy.total_fee + fee;
    assert!(policy.total_fee <= DENOMINATOR as u64, EInvalidTotalFee);

    policy.fees.insert(receiver, fee);

    if (!policy.balances.contains(&receiver)) {
        policy.balances.insert(receiver, balance::zero());
    };
}

public fun remove_fee<FT>(
    policy: &mut FeeTokenPolicy<FT>,
    cap: &FeeTokenPolicyCap<FT>,
    receiver: address
) {
    assert!(object::id(policy) == cap.policy_id, EAccessDenied);

    let (_, old_fee) = policy.fees.remove(&receiver);
    policy.total_fee = policy.total_fee - old_fee;
}

public fun withdraw_fee<FT>(
    token: &mut FeeToken<FT>,
    policy: &mut FeeTokenPolicy<FT>
) {
    if (policy.balances.contains(&token.owner)) {
        let balance = policy.balances.get_mut(&token.owner).withdraw_all();
        token.balance.join(balance);

        if (!policy.fees.contains(&token.owner)) {
            let (_, balance) = policy.balances.remove(&token.owner);
            balance.destroy_zero();
        };
    };
}

public fun new<FT>(registry: &mut FeeTokenRegistry, owner: address, ctx: &mut TxContext): FeeToken<FT> {
    let token = FeeToken<FT> {
        id: derived_object::claim(&mut registry.id, FeeTokenKey<FT> { owner }),
        owner,
        balance: balance::zero<FT>()
    };

    let ref = FeeTokenRef {
        id: object::new(ctx),
        token_type: type_name::with_defining_ids<FT>(),
        token_id: object::id(&token),
        token_owner: owner
    };
    transfer::transfer(ref, owner);

    emit(NewFeeTokenEvent {
        token_type: type_name::with_defining_ids<FT>(),
        token_id: object::id(&token),
        token_owner: owner
    });

    token
}

public fun share<FT>(token: FeeToken<FT>) {
    transfer::share_object(token);
}

public fun withdraw_from_address<FT>(token: &mut FeeToken<FT>, amount: u64, ctx: &mut TxContext): (Balance<FT>, DepositLock<FT>) {
    assert!(token.owner == ctx.sender(), EAccessDenied);

    assert!(token.balance.value() >= amount, ENotEnoughBalance);
    let balance = token.balance.split(amount);

    emit(WithdrawFeeTokenEvent {
        token_type: type_name::with_defining_ids<FT>(),
        token_id: object::id(token),
        token_owner: token.owner,
        amount,
    });

    (balance, DepositLock<FT> { amount, include_fee: true })
}

public fun withdraw_from_object<FT>(token: &mut FeeToken<FT>, object: &UID, amount: u64): (Balance<FT>, DepositLock<FT>) {
    assert!(token.owner == object.uid_to_address(), EAccessDenied);

    assert!(token.balance.value() >= amount, ENotEnoughBalance);
    let balance = token.balance.split(amount);

    emit(WithdrawFeeTokenEvent {
        token_type: type_name::with_defining_ids<FT>(),
        token_id: object::id(token),
        token_owner: token.owner,
        amount,
    });

    (balance, DepositLock<FT> { amount, include_fee: true })
}

public fun deposit<FT>(token: &mut FeeToken<FT>, mut balance: Balance<FT>, lock: &mut DepositLock<FT>, policy: &mut FeeTokenPolicy<FT>) {
    let amount = balance.value();
    let mut fee: u64 = 0;

    if (lock.include_fee) {
        policy.fees.keys().do_mut!(|receiver| {
            let fee_balance = balance.split(((amount as u128) * (*policy.fees.get(receiver) as u128) / DENOMINATOR) as u64);
            fee = fee + fee_balance.value();
            policy.balances.get_mut(receiver).join(fee_balance);
        });
    };

    token.balance.join(balance);
    lock.amount = lock.amount - amount;

    emit(DepositFeeTokenEvent {
        token_type: type_name::with_defining_ids<FT>(),
        token_id: object::id(token),
        token_owner: token.owner,
        amount,
        fee
    });
}

public fun destroy_lock<FT>(lock: DepositLock<FT>) {
    assert!(lock.amount == 0, EDepositLockAmountIsNotZero);
    let DepositLock { amount: _ , include_fee: _} = lock;
}