# Account health states

States of one account's health, and the events that move it between states.

```mermaid
stateDiagram-v2
    [*] --> DebtFree
    state "Prices paused" as PricesPaused
    state "At risk" as AtRisk
    DebtFree --> Safe : borrow
    Safe --> Watch : price falls
    Watch --> AtRisk : price falls further
    AtRisk --> Liquidatable : price falls further or debt grows
    Watch --> Safe : price recovers, repay or add assets
    AtRisk --> Watch : price recovers, repay or add assets
    Liquidatable --> AtRisk : partial liquidation or repay
    Safe --> DebtFree : repay in full
    Watch --> DebtFree : repay in full
    AtRisk --> DebtFree : repay in full
    Liquidatable --> DebtFree : debt cleared
    Safe --> PricesPaused : oracle down
    Watch --> PricesPaused : oracle down
    AtRisk --> PricesPaused : oracle down
    Liquidatable --> PricesPaused : oracle down
    PricesPaused --> Safe : oracle up
    PricesPaused --> Watch : oracle up
    PricesPaused --> AtRisk : oracle up
    PricesPaused --> Liquidatable : oracle up
    note right of DebtFree : borrow lands in the state its new health implies
    note right of Watch : limits come from pool settings
    note right of PricesPaused : oracle up returns the state computed from current prices
```

Notes

- Thresholds for Watch, At risk and Liquidatable come from the pool settings. No numbers are given here.
- Repay, adding assets and price moves are the events that change the state. Repay is always allowed. Adding assets is always allowed.
- While Prices paused is shown, Borrow and withdrawing while in debt are off.
- Open question: whether a debt-free account ever shows Prices paused. The diagram follows the debt states only.
