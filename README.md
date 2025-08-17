# LiquidStress 💧

Monte Carlo simulation for emergency fund optimization. Models bucket-strategy portfolios with cascading liquidity tiers under stochastic unforeseen expenses. Stress-tests cash reserves, emergency funds, and asset allocation to minimize costly liquidations during financial emergencies. Built in Julia.

## 🎯 Why LiquidStress?

The traditional "3-6 months of expenses" emergency fund rule is oversimplified. **LiquidStress** goes beyond this by:

- 📊 **Modeling realistic emergencies** with stochastic distributions (frequency + magnitude)
- 🏗️ **Testing bucket strategies** that cascade from liquid to illiquid assets
- 📈 **Optimizing liquidity** to balance emergency preparedness with investment returns
- 🎲 **Monte Carlo simulation** to stress-test your strategy across thousands of scenarios

## 🪣 Portfolio Architecture

LiquidStress uses a **bucket/cascade design** with prioritized liquidity tiers:

[Liquid] → [Semi-Liquid] → [Illiquid] → [Long-term] Cash Savings Bonds Stocks/ETFs


**Deposit Logic**: Money flows to the next bucket only after the previous one reaches its minimum reserve.

**Withdrawal Logic**: Money is withdrawn from the most liquid bucket first, cascading deeper only when necessary.

**Bucket Types**:
- `SinkBucket`: Unlimited capacity (e.g., stocks)
- `BoundedBucket`: Fixed capacity with min/max limits
- `TransactionBucket`: Minimum transaction amounts (e.g., bonds)

## 🎯 The Simulation

**Input Parameters**:
- Monthly salary and fixed expenses
- Emergency event distributions (Poisson frequency + Gamma magnitude)
- Portfolio configuration (bucket sizes, reserves, constraints)
- Simulation parameters (trajectories, time horizon)

**Simulation Process**:
1. **Monthly cycle**: Deposit salary → Withdraw expenses + emergencies
2. **Emergency modeling**: Compound Poisson process for realistic event clustering
3. **Portfolio tracking**: Record which buckets are accessed each month
4. **Statistical analysis**: Extract breach frequencies, risk metrics, optimization insights

## 📊 Key Outputs

- **Bucket access frequencies**: How often do you need each liquidity tier?
- **Balance trajectories**: Mean evolution and confidence intervals
- **Risk metrics**: Worst-case scenarios and tail risk analysis
- **Optimization insights**: Right-size your emergency funds

## 📚 Usage
Check the `Pluto` notebook for detailed usage and methodology.
