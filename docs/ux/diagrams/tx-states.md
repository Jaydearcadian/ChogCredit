# Transaction states in the UI

How one transaction moves through the UI, from preview to a final result.

```mermaid
stateDiagram-v2
    [*] --> Idle
    Idle --> Preview : user starts an action
    Preview --> AwaitingSignature : user confirms
    Preview --> Idle : user closes preview
    AwaitingSignature --> Submitted : wallet sends transaction
    AwaitingSignature --> Rejected : user cancels in wallet
    Rejected --> Preview : user edits and retries
    Submitted --> Confirmed : included in a block
    Submitted --> Reverted : failed on chain
    Submitted --> Dropped : never included
    Confirmed --> Final : final on Monad
    Reverted --> Preview : user retries
    Dropped --> Preview : user retries
    Final --> Idle : user returns to the screen
    note right of Rejected : transient, shown briefly
    note right of Reverted : persistent error with reason, stays until the user acts
    note right of Dropped : persistent error, stays until the user acts
    note right of Final : terminal success, also kept in S9 Activity
```

## Persistent and transient states

| State | Type | Notes |
|---|---|---|
| Idle | Resting | No transaction in progress. |
| Preview | Transient | Shows the numbers before signing. |
| AwaitingSignature | Transient | Waiting for the wallet. |
| Submitted | Transient | Sent. Shown as pending until it is confirmed. |
| Confirmed | Transient | Included. Final is still to come (Monad has speculative finality). |
| Final | Terminal success | Kept in S9 Activity. |
| Rejected | Transient | The user cancelled in the wallet. No error is kept. |
| Reverted | Persistent error | Shows the reason. Stays until the user retries or dismisses it. |
| Dropped | Persistent error | Not included. Stays until the user retries or dismisses it. |
