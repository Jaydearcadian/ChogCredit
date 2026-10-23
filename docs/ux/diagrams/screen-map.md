# Screen map

Navigation between the 16 screens (S0 to S15). Each node is one screen. Arrows show the main navigation.

```mermaid
flowchart TD
    S0["S0 Connect and network"]
    S1["S1 Pick your Chog"]
    S2["S2 Open vault"]
    S3["S3 Account overview"]
    S4["S4 Collateral detail"]
    S5["S5 Add assets"]
    S6["S6 Credit preview and Borrow"]
    S7["S7 Repay"]
    S8["S8 Withdraw and release Chog"]
    S9["S9 Activity"]
    S10["S10 Sell with Vault"]
    S11["S11 Buyer acceptance"]
    S12["S12 Risk and terms"]
    S13["S13 Lend"]
    S14["S14 Market use placeholder"]
    S15["S15 Settings"]
    S0 -->|"wallet connected"| S1
    S1 -->|"no account yet"| S2
    S1 -->|"account open"| S3
    S2 -->|"account created"| S3
    S3 --> S4
    S3 --> S5
    S3 --> S6
    S3 --> S7
    S3 --> S8
    S3 --> S9
    S3 --> S10
    S3 --> S13
    S3 --> S14
    S3 --> S15
    S4 -->|"exit"| S8
    S4 -->|"add more"| S5
    S5 --> S3
    S6 --> S12
    S6 --> S3
    S7 --> S3
    S8 -->|"released"| S1
    S9 --> S3
    S10 --> S11
    S11 --> S9
    S13 --> S3
    S15 --> S3
```

Notes

- S14 is a placeholder. It is not available yet.
- S0 is the entry point. Settings (S15) is also reachable from S0.
- Screens S6, S7 and S8 show the special states Prices paused, At risk, Liquidatable, error and pending in place. They are not separate screens.
