# Borrow sequence: credit preview, then borrow

Covers the credit preview on S6, the borrow transaction, and the oracle-unavailable branch.

```mermaid
sequenceDiagram
    actor B as Borrower
    participant UI as UI S6
    participant W as Wallet
    participant P as Pool contract
    participant O as Oracle
    B->>UI: Open Borrow and enter amount
    UI->>O: Read prices and freshness
    alt Prices available
        O-->>UI: Prices with freshness
        UI->>P: Read pool cash and terms
        P-->>UI: Cash and terms
        UI-->>B: Credit preview with health after borrow
        B->>UI: Confirm borrow
        UI->>W: Request signature
        W-->>UI: Signed transaction
        UI->>P: Submit borrow
        P->>O: Check price is usable
        O-->>P: Price is usable
        P-->>UI: Debt increased, state Submitted
        UI-->>B: Confirmed, then Final
    else Oracle unavailable
        O-->>UI: No usable price
        UI-->>B: Prices paused, Borrow is off
        Note over UI: No transaction is sent
    end
```

Notes

- If the oracle fails between the preview and the submit, the pool refuses the borrow (fail closed) and the UI shows Reverted with the reason.
- Thresholds that set Watch, At risk and Liquidatable come from the pool settings. They are not shown here.
