"""
The idea of this bucket system is to manage funds across different types of buckets, each with specific rules for deposits and balances.

The `Portfolio` is a wrapper around a vector of buckets, with a priority order. Lower the index, higher the priority.

The first bucket is the most liquid and has higher priority, meaning that when depositing or withdrawing it will
be accessed first.

A bucket is accessed when depositing funds if, and only if, all previous buckets have at least a balance of `min_reserve`.

Similarly, when withdrawing funds, the bucket is accessed only if all previous buckets are empty.

"""

# Export bucket types
export AbstractBucket, SinkBucket, BoundedBucket, TransactionBucket, Portfolio

# Export main functions
export deposit!, withdraw!, rebalance!

# Export utility functions
export isfull, can_deposit, amount_too_small, bucket_names, balances


abstract type AbstractBucket end


"""
    SinkBucket(name::String, min_reserve::Float64, balance::Float64)
A bucket that acts as a sink for excess funds, with a minimum reserve that must be reached and mantained before filling the next bucket.
"""
mutable struct SinkBucket <: AbstractBucket
    name::String
    min_reserve::Float64
    balance::Float64
end

"""
    BoundedBucket(name::String, min_reserve::Float64, max_capacity::Float64, balance::Float64)
A bucket with a minimum reserve and a maximum capacity. It can hold funds up to its maximum capacity.
"""
mutable struct BoundedBucket <: AbstractBucket
    name::String
    min_reserve::Float64
    max_capacity::Float64
    balance::Float64
end

"""
    TransactionBucket(name::String, min_reserve::Float64, min_transaction::Float64, max_capacity::Float64, balance::Float64)
A bucket that allows transactions with a minimum transaction amount, a minimum reserve, and a maximum capacity
"""
mutable struct TransactionBucket <: AbstractBucket
    name::String
    min_reserve::Float64
    min_transaction::Float64
    max_capacity::Float64  # Always bounded
    balance::Float64
end

struct Portfolio
    buckets::Vector{AbstractBucket}
end

function Portfolio(buckets::Vararg{AbstractBucket})
    Portfolio(collect(buckets))
end

# Base.show overloads for pretty printing
function Base.show(io::IO, b::SinkBucket)
    print(io, "SinkBucket(\"$(b.name)\", balance=$(round(b.balance, digits=2)), min=$(b.min_reserve))")
end

function Base.show(io::IO, b::BoundedBucket)
    print(io, "BoundedBucket(\"$(b.name)\", balance=$(round(b.balance, digits=2)), min=$(b.min_reserve), max=$(b.max_capacity))")
end

# Base.show overload - simplified
function Base.show(io::IO, b::TransactionBucket)
    print(io, "TransactionBucket(\"$(b.name)\", balance=$(round(b.balance, digits=2)), min=$(b.min_reserve), max=$(b.max_capacity), min_tx=$(b.min_transaction))")
end

function Base.show(io::IO, p::Portfolio)
    println(io, "Portfolio with $(length(p.buckets)) buckets:")
    for (i, b) in enumerate(p.buckets)
        println(io, "  [$i] $b")
    end
end


############# Some utility functions #############

"""
    isfull(bucket::AbstractBucket) -> Bool

Check if a bucket has reached its maximum capacity.
Returns `false` for `SinkBucket` since it has unlimited capacity.
"""
isfull(b::AbstractBucket) = b.balance >= b.max_capacity
isfull(b::SinkBucket) = false  # SinkBucket has no max capacity

"""
    can_deposit(bucket::AbstractBucket, amount::Float64) -> Bool

Check if a bucket can accept a deposit of the given amount.
For `TransactionBucket`, also checks if the amount meets the minimum transaction requirement.
"""
can_deposit(b::AbstractBucket, ::Float64) = !isfull(b)
can_deposit(b::TransactionBucket, amount::Float64) = amount >= b.min_transaction && !isfull(b)

"""
    amount_too_small(bucket::AbstractBucket, amount::Float64) -> Bool

Check if the amount is too small for the bucket's transaction requirements.
Only relevant for `TransactionBucket` which has minimum transaction amounts.
"""
amount_too_small(b::AbstractBucket, ::Float64) = false
amount_too_small(b::TransactionBucket, amount::Float64) = amount < b.min_transaction

############# Deposit functions #############

"""
    deposit!(bucket::BoundedBucket, amount::Float64) -> Float64

Deposit funds into a bounded bucket up to its maximum capacity.
Returns the amount that could not be deposited due to capacity constraints.
"""
function deposit!(bucket::BoundedBucket, amount::Float64)
    amount <= 0 && return 0.0

    available = bucket.max_capacity - bucket.balance
    place = min(amount, available)
    bucket.balance += place
    return amount - place
end

"""
    deposit!(bucket::TransactionBucket, amount::Float64) -> Float64

Deposit funds into a transaction bucket, respecting minimum transaction amounts.
Returns the amount that could not be deposited due to capacity or transaction constraints.
"""
function deposit!(bucket::TransactionBucket, amount::Float64)
    amount <= 0 && return 0.0

    # Must meet minimum transaction
    amount < bucket.min_transaction && return amount

    available = bucket.max_capacity - bucket.balance
    place = min(amount, available)
    place < bucket.min_transaction && return amount

    bucket.balance += place
    return amount - place
end

"""
    deposit!(bucket::SinkBucket, amount::Float64) -> Float64

Deposit funds into a sink bucket, which accepts all funds without limit.
Always returns 0.0 since sink buckets have unlimited capacity.
"""
function deposit!(bucket::SinkBucket, amount::Float64)
    amount <= 0 && return 0.0
    bucket.balance += amount
    return 0.0
end

"""
When depositing funds, the function will iterate through the buckets in order of priority.
Once a bucket is filled above its `min_reserve`, it will attempt to deposit the excess into the next bucket.
If the following bucket is a `TransactionBucket` and the excess amount is less than its `min_transaction`, it will not deposit into that bucket
and the excess will remain in the current bucket. This also means that before a `TransactionBucket` there must always be a 
bucket that can hold an excess funds greater than or equal to the `min_transaction` of the next bucket.
"""
function deposit!(portfolio::Portfolio, amount::Float64; rebalance::Bool=true)
    amount <= 0 && throw(ArgumentError("Deposit amount must be positive"))
    remaining = amount

    for bucket in portfolio.buckets
        remaining <= 0 && break
        remaining = deposit!(bucket, remaining)
    end
    if remaining > 0
        throw(ArgumentError("Could not deposit all funds. Remaining: $remaining"))
    end
    rebalance && rebalance!(portfolio)
    return portfolio
end

function rebalance!(portfolio::Portfolio, bucket::TransactionBucket, bucket_idx::Int)
    # Do nothing - TransactionBucket should not be rebalanced
    return
end

"""
    rebalance!(portfolio::Portfolio, bucket::AbstractBucket, idx::Int)

Rebalance excess funds from a bucket to subsequent lower-priority buckets.
Moves funds above the bucket's `min_reserve` to the next available buckets,
respecting transaction minimums for `TransactionBucket`s.
"""
function rebalance!(portfolio::Portfolio, bucket::AbstractBucket, idx::Int)
    excess = bucket.balance - bucket.min_reserve
    if excess > 0
        for next_bucket in portfolio.buckets[idx+1:end]
            if amount_too_small(next_bucket, excess)
                break
            end

            if can_deposit(next_bucket, excess)
                remaining = deposit!(next_bucket, excess)
                deposited = excess - remaining
                bucket.balance -= deposited
                excess = remaining

                if excess <= 0
                    break
                end
            end
        end
    end
end

"""
    rebalance!(portfolio::Portfolio)

Rebalance all buckets in the portfolio, moving excess funds from each bucket
to subsequent buckets according to priority and capacity constraints.
"""
function rebalance!(portfolio::Portfolio)
    for (idx, bucket) in enumerate(portfolio.buckets)
        rebalance!(portfolio, bucket, idx)
    end
    return
end

############# Withdraw functions #############

"""
    withdraw!(portfolio::Portfolio, bucket::AbstractBucket, amount::Float64) -> Float64

Withdraw funds from a standard bucket (SinkBucket or BoundedBucket).
Returns the amount that could not be withdrawn (remaining needed).
"""
function withdraw!(::Portfolio, bucket::AbstractBucket, amount::Float64)
    amount <= 0 && return 0.0

    place = min(amount, bucket.balance)
    bucket.balance -= place
    return amount - place
end

"""
    withdraw!(portfolio::Portfolio, bucket::TransactionBucket, amount::Float64) -> Float64

Withdraw funds from a transaction bucket, respecting minimum transaction amounts.
If withdrawal amount is less than `min_transaction`, no withdrawal occurs.
If forced to withdraw more than requested (due to min_transaction), excess is
deposited back into the portfolio with rebalancing.
Returns the amount that could not be withdrawn.
"""
function withdraw!(port::Portfolio, bucket::TransactionBucket, amount::Float64)
    amount <= 0 && return 0.0

    if bucket.balance < bucket.min_transaction
        return amount  # Cannot withdraw if balance is less than min_transaction
    end

    place = min(amount, bucket.balance)
    place = max(place, bucket.min_transaction)  # Ensure we withdraw at least the minimum transaction amount

    bucket.balance -= place
    excess = place - amount
    if excess > 0
        # If we withdrew more than requested, we need to deposit the excess back
        deposit!(port, excess)
        return 0.0  # Successfully withdrew the requested amount
    end

    return amount - place
end

"""
    withdraw!(portfolio::Portfolio, amount::Float64) -> Int

Withdraw funds from the portfolio, accessing buckets in priority order.
Throws an error if insufficient funds are available.
Returns the index of the last bucket accessed during withdrawal.

# Arguments
- `portfolio::Portfolio`: The portfolio to withdraw from
- `amount::Float64`: The amount to withdraw

# Returns
- `Int`: Index of the last bucket that was accessed during withdrawal

# Throws
- `ArgumentError`: If withdrawal amount is non-positive or insufficient funds available
"""
function withdraw!(portfolio::Portfolio, amount::Float64)
    amount <= 0 && throw(ArgumentError("Withdrawal amount must be positive"))
    remaining = amount
    last_accessed = 0

    for (idx, bucket) in enumerate(portfolio.buckets)
        remaining <= 0 && break

        # if the bucket is empty
        if bucket.balance == 0
            continue  # Skip empty buckets
        end

        last_accessed = idx
        remaining = withdraw!(portfolio, bucket, remaining)

    end

    return last_accessed
end

function bucket_names(portfolio::Portfolio)
    return [b.name for b in portfolio.buckets]
end

function balances(portfolio::Portfolio)
    return [b.balance for b in portfolio.buckets]
end

function Base.deepcopy(portfolio::Portfolio)
    return Portfolio([deepcopy(bucket) for bucket in portfolio.buckets])
end

function Base.deepcopy(bucket::SinkBucket)
    return SinkBucket(bucket.name, bucket.min_reserve, bucket.balance)
end

function Base.deepcopy(bucket::BoundedBucket)
    return BoundedBucket(bucket.name, bucket.min_reserve, bucket.max_capacity, bucket.balance)
end

function Base.deepcopy(bucket::TransactionBucket)
    return TransactionBucket(bucket.name, bucket.min_reserve, bucket.min_transaction, bucket.max_capacity, bucket.balance)
end

# Example usage
function example()
    port = Portfolio(
        BoundedBucket("Liquidity", 2500, 2500, 0),
        SinkBucket("SavingAccount", 1000, 0),
        TransactionBucket("Bonds", 4000, 1000, 5000, 0),
        SinkBucket("ETF", 0, 0),
    )
    println("Initial Portfolio:")
    @show port
    for amount in [2000, 600, 400, 100, 2000, 1900, 2000]
        println("Depositing $amount")
        deposit!(port, float(amount))
        @show port
    end
    for amount in [2000, 600, 400, 100, 2000, 500, 2000]
        println("Withdrawing $amount")
        idx = withdraw!(port, float(amount))
        @show port
        println("Last accessed bucket index: $idx")
    end
end