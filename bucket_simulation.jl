using Distributions, StatsPlots, Statistics
import Random: Random, AbstractRNG
include("portfolio.jl") 

"""
    Unforseen{T<:DiscreteUnivariateDistribution, Q<:ContinuousUnivariateDistribution}

A structure to model unforeseen events with stochastic frequency and magnitude.
Combines a discrete distribution for event occurrence with a continuous distribution for event values.

# Fields
- `db_event::T`: Discrete distribution modeling the frequency/number of unforeseen events
- `db_value::Q`: Continuous distribution modeling the magnitude/cost of each unforeseen event
"""
struct Unforseen{T<:DiscreteUnivariateDistribution,Q<:ContinuousUnivariateDistribution}
    db_event::T
    db_value::Q
    function Unforseen(DB1::T, DB2::Q) where {T<:DiscreteUnivariateDistribution,Q<:ContinuousUnivariateDistribution}
        new{T,Q}(DB1, DB2)
    end
end

"""
    Unforseen(mean_frequency::Float64, mean_value::Float64, std_value::Float64) -> Unforseen

Convenience constructor for unforeseen events using common parameters.

Creates an `Unforseen` struct with:
- Poisson distribution for event frequency (discrete)
- Gamma distribution for event magnitude (continuous)

# Arguments
- `mean_frequency::Float64`: Average number of unforeseen events per time period
- `mean_value::Float64`: Average cost/magnitude of each unforeseen event
- `std_value::Float64`: Standard deviation of the cost/magnitude

# Returns
- `Unforseen`: Configured unforeseen event model

# Example
```julia
# Model emergency expenses: 1.5 events per month, avg cost 2000, std dev 800
emergency_expenses = Unforseen(1.5, 2000.0, 800.0)

# Sample number of events this period
num_events = rand(emergency_expenses.db_event)

# Sample the cost of each event
total_cost = sum(rand(emergency_expenses.db_value) for _ in 1:num_events)
```
"""
function Unforseen(mean_frequency::Float64, mean_value::Float64, std_value::Float64)
    db_event = Poisson(mean_frequency)
    db_value = Gamma(mean_value^2 / std_value^2, std_value^2 / mean_value)
    return Unforseen(db_event, db_value)
end

"""
    rand(unforseens::AbstractVector{Unforseen}) -> Float64

Sample the total cost of unforeseen events across multiple categories for one time period.

For each `Unforseen` in the vector:
1. Samples the number of events from the frequency distribution
2. Samples the cost of each event from the magnitude distribution  
3. Sums the total cost for that category

Returns the sum of costs across all unforeseen event categories.

# Arguments
- `unforseens::AbstractVector{Unforseen}`: Vector of different unforeseen event types

# Returns
- `Float64`: Total cost of all unforeseen events for this time period

# Example
```julia
unforeseen_events = [
    Unforseen(0.5, 3000.0, 1000.0),  # Major repairs
    Unforseen(1.2, 500.0, 200.0),   # Minor emergencies
    Unforseen(0.1, 10000.0, 5000.0) # Medical emergencies
]

# Sample total unforeseen costs for this month
total_unforeseen_cost = rand(unforeseen_events)
```
"""
function Base.rand(rng::AbstractRNG, unforseen::Unforseen)
    num_events = rand(rng, unforseen.db_event)
    return sum(rand(rng, unforseen.db_value, num_events))
end

# Convenience method without specifying RNG
function Base.rand(unforseen::Unforseen)
    return rand(Random.default_rng(), unforseen)
end

function run_simulation(
    portfolio::Portfolio,
    starting_capital::Float64,
    salary::Float64,
    fixed_expenses::Float64,
    unforseens::AbstractVector{<:Unforseen},
    N_trajectories::Int,
    N_months::Int,
)

    N_buckets = length(portfolio.buckets)
    trajectories = Matrix{Portfolio}(undef, N_months, N_trajectories)
    bucket_accesses = zeros(Bool, N_months, N_trajectories, N_buckets)

    for i in 1:N_trajectories
        traj_portfolio = deepcopy(portfolio)  # Create a copy for each trajectory
        deposit!(traj_portfolio, starting_capital)  # Initialize with starting capital

        for month in 1:N_months
            # Add salary to the portfolio
            deposit!(traj_portfolio, salary)

            expenses = fixed_expenses
            expenses += sum(rand(unforseen) for unforseen in unforseens)
            bucket_accesses[month, i, withdraw!(traj_portfolio, expenses)] = true  # Mark which buckets were accessed
            trajectories[month, i] = deepcopy(traj_portfolio)
        end
    end
    return trajectories, bucket_accesses
end


function get_balances(trajectories::Matrix{Portfolio})
    N_months, N_trajectories = size(trajectories)

    starting_portfolio = trajectories[1, 1]
    N_buckets = length(starting_portfolio.buckets)
    sim_balances = Array{Float64}(undef, N_buckets, N_months, N_trajectories)

    for (i_traj, traj) in enumerate(eachcol(trajectories))
        for (i_month, month_portfolio) in enumerate(traj)
            sim_balances[:, i_month, i_traj] = balances(month_portfolio)
        end
    end
    return sim_balances
end

function plot_trajectories(sim_balances::Array{Float64, 3}, bucket_names::Vector{String})
    N_buckets = size(sim_balances, 1)
    @assert N_buckets == length(bucket_names) "Number of buckets must match number of bucket names"

    # Create subplots layout
    n_cols = min(3, N_buckets)  # Max 3 columns
    n_rows = ceil(Int, N_buckets / n_cols)
    
    plots = []
    
    for bucket in 1:N_buckets
        p = plot(
            title = bucket_names[bucket],
            xlabel = "Month",
            ylabel = "Balance",
            legend = false,
            grid = true
        )
        
        # Use errorline! for this bucket's data
        errorline!(p, sim_balances[bucket, :, :])
        
        push!(plots, p)
    end
    
    # Combine all subplots
    return plot(plots..., 
                layout = (n_rows, n_cols),
                size = (300 * n_cols, 250 * n_rows),
                plot_title = "Bucket Balances Over Time")
end


"""
    get_bucket_usage_stats(bucket_accesses::Array{Bool, 3}, bucket_names::Vector{String}) -> Dict{String, Vector{Float64}}

Compute the distribution of bucket access frequencies across simulation trajectories.

For each bucket, returns a vector showing how many times that bucket level (or deeper) 
was accessed in each trajectory during the simulation period.

# Arguments
- `bucket_accesses::Array{Bool, 3}`: 3D boolean array with dimensions (N_months, N_trajectories, N_buckets).
  `bucket_accesses[month, traj, bucket]` is `true` if `bucket` was accessed in that month/trajectory.
- `bucket_names::Vector{String}`: Names of the buckets for labeling the output.

# Returns
- `Dict{String, Vector{Float64}}`: Dictionary mapping each bucket name to a vector of length `N_trajectories`.
  Each element in the vector represents the total number of months that bucket level (or deeper) 
  was accessed in that specific trajectory.

# Interpretation
- `stats["Emergency Fund"][i]` = number of months trajectory `i` needed to access the Emergency Fund or deeper buckets
- `stats["Deep Emergency"][i]` = number of months trajectory `i` needed to access the Deep Emergency or deeper buckets
- Higher values indicate trajectories that experienced more frequent financial stress requiring deeper bucket access

# Example Output
```julia
Dict(
    "Cash" => [12.0, 8.0, 15.0, 6.0, ...],        # Each trajectory's months accessing Cash+
    "Emergency Fund" => [3.0, 0.0, 7.0, 1.0, ...], # Each trajectory's months accessing Emergency+
    "Deep Emergency" => [0.0, 0.0, 2.0, 0.0, ...]  # Each trajectory's months accessing Deep Emergency+
)
```

# Usage for Further Analysis
This distribution can be used to:
- Calculate percentiles: `quantile(stats["Emergency Fund"], [0.5, 0.95])` for median and 95th percentile
- Compute summary statistics: `mean(stats["Emergency Fund"])` for average usage
- Analyze risk: `count(x -> x > 5, stats["Emergency Fund"])` for trajectories with >5 months of emergency fund usage
- Plot histograms: `histogram(stats["Emergency Fund"])` to visualize the distribution

# Notes
- Statistics are cumulative: accessing bucket N means buckets 1 through N were all insufficient
- The `bucket_accesses` array should have exactly one `true` per (month, trajectory) pair since only one bucket is accessed per withdrawal
- Vector length equals `N_trajectories` from the simulation
"""
function get_bucket_usage_stats(bucket_accesses::Array{Bool, 3}, bucket_names::Vector{String})
    N_months, N_trajectories, N_buckets = size(bucket_accesses)
    
    stats = Dict{String, Vector{Float64}}()
    
    for bucket in 1:N_buckets
        # Check if this bucket or any deeper bucket was accessed
        accessed_this_deep = dropdims(any((bucket_accesses[:, :, bucket:end]), dims=3), dims=3)

        stats[bucket_names[bucket]] = dropdims(sum(accessed_this_deep, dims=1), dims=1)
    end
    
    return stats
end