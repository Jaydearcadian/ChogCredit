# Sale sequence: Sell with Vault

Covers the seller's offer, the buyer's signed bounds, execution, and the branch where execution reverts.

```mermaid
sequenceDiagram
    actor S as Seller
    participant UI as UI S10 S11
    actor Y as Buyer
    participant C as Coordinator contract
    participant P as Pool
    S->>UI: Open Sell with Vault
    UI->>P: Read loan and health
    P-->>UI: Current loan
    UI-->>S: Package with loan, vault value and payoff option
    S->>UI: Create sale offer
    UI-->>Y: Offer link opens S11
    Y->>UI: Set bounds: loan at most X, vault value at least Y, health at least Z, deadline
    Y->>C: Sign bounds
    C-->>UI: Bounds accepted, waiting for seller
    S->>UI: Execute sale
    alt Prices or loan moved outside signed bounds
        C->>P: Read current loan
        P-->>C: Loan outside bounds
        C-->>UI: Execution reverts (bounds not met)
        UI-->>S: Can't complete, with reason; account unchanged
    else Bounds still hold
        UI->>C: Execute with signed bounds
        alt Execution succeeds
            C->>P: Apply payoff from price if signed
            C-->>UI: Package transferred as one unit
            UI-->>S: Final, recorded in Activity
            UI-->>Y: Final, package owned
        else Execution fails
            C-->>UI: Reverted with reason
            UI-->>S: Nothing transferred
        end
    end
```

Notes

- The package moves as one unit, or it does not move. There is no partial transfer.
- Execution reverts, and the app shows it as can't complete, when prices or the loan move outside the signed bounds before execution.
- Execution is not offered while prices are paused, since the bounds depend on vault value and health. This is to be confirmed against the coordinator spec.
