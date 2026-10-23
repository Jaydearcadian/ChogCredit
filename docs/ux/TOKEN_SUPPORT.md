# Why not every token, and what MON would take

This is a deliberate limit, not something impossible. Facts are from the contracts as they stand.

## Where the limit comes from

- The registry allowlist (`isTokenAllowed`) is filled in the constructor. There is no function to add a token later. Adding one means deploying a new registry, and vaults are tied to the registry that made them.
- The credit pool's collateral list (`CollateralConfig[]`) is also fixed at construction, with a haircut, a cap and a price feed per token.
- A token that is allowed in the vault but not in the pool's list is held at zero credit value. `$CHOG` is the live example.

## Why the allowlist is closed on purpose

1. **Price and liquidity.** Every collateral token needs a feed we trust and enough market depth to sell during a liquidation. The feed and liquidity work (`docs/evidence/FEED_ANALYSIS.md`, `LIQUIDITY_MODEL.md`) covered a few tokens, not "any ERC-20".
2. **Token behaviour.** The vault measures balance changes and rejects fee-on-transfer tokens on deposit. Rebasing tokens, tokens that can freeze or blacklist an address (USDC itself can), and tokens with transfer hooks all break the "balance equals what we recorded" assumption or let a third party interfere with a liquidation.
3. **No admin key.** A token-adding function would need an owner. The design avoids one on purpose (the rescuer and multisig are disabled), so changing the list is a redeploy that users can see.
4. **Griefing.** Open lists invite worthless tokens. The app would have to filter them.

## Native MON

MON is not an ERC-20, and the vault has no `receive()`, so a MON transfer to a vault reverts. This protects senders from losing it. WMON is on the allowlist and is real collateral today.

Options if we want MON to work:
- **Wrap in the app (recommended).** The Add and Receive screens wrap MON to WMON in the same transaction bundle. No contract change.
- **A payable entry point.** Add `depositNative()` that wraps to WMON inside the vault. Small, but it adds an ether path to the vault and a reentrancy surface, so it needs its own tests and review.
- **Accept a plain MON send.** Add `receive()` that wraps. Not recommended: any contract that forwards MON would then change vault state, and it widens what a stranger can do to the vault.

## Adding other tokens

Feasible, with a process rather than a switch: pick the token, show it has a trusted feed and a way to sell it, test its behaviour (fee, rebase, hooks, blacklist), then include it in the next deployment's allowlist and pool config with a cap. A shared "vault-only" tier already exists for tokens that should be held but not borrowed against.
