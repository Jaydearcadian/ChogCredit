# Receive: how paying a Chog would work

Status: the contract function `claimReceived` is built and tested (see below). The app screen, payment link and a local-chain run are not built yet.

## The idea

Every Chog already has a vault with a fixed address, known before the vault is opened (`predictVault`). A payer sends USDC to that address from any wallet or exchange. The Chog's keeper sees it in the app, taps once, and it becomes part of the vault, where it backs credit like any other deposit.

## What the contracts do today

Read from `AccountVault.sol`:

- `depositERC20` is controller-only and requires the Chog to be escrowed and the token allowlisted. A stranger cannot call it.
- A plain ERC-20 transfer from anyone still lands in the vault, because the token has no hook. The vault records it as unaccounted: it is not collateral, it does not count toward `isEmpty`, and the only thing the controller can do with it is `sweepUnaccounted` back out.
- The vault has no `receive()`, so a native MON transfer reverts. That protects payers from losing MON, but the app must say "USDC only".

So the idea works for the money arriving, but not for it counting. That needs the change below.

## The change (built)

One new controller-only function, say `claimReceived(token)`:

1. Requires the Chog is escrowed and the token is allowlisted (same checks as `depositERC20`).
2. Takes the difference between the token balance and `accounted[token]` and adds it to `accounted`.
3. Bumps `stateNonce`, so any signed sale terms are voided (the vault's contents changed).
4. Emits an event the app can index.

Why controller-only, and not "anyone can pay in and it counts": if anyone could credit the vault, anyone could void a pending sale at will by sending 1 unit, and could inflate the token count with dust. With a controller-only claim, strangers can send but only the keeper decides what counts.

Per-account collateral caps (`maxCounted`) still apply, so a large payment above the cap is held but not counted, shown the same way as on the Collateral screen.

## The payer's side

1. The keeper opens Receive and gets a link or QR for their Chog, resolving to the vault address. Example shape: `/pay/<collection>/<tokenId>`, optional `?amount=`.
2. The payer sees "Pay Chog #1234" with the address, the one accepted token (USDC), and a warning not to send anything else.
3. The payer sends a normal USDC transfer. No approval, no special contract, works from an exchange.
4. The payer sees the transfer on the explorer. The app can show a "received" event, but never a payer's name or note unless it is attached off-chain and clearly marked as unverified.

## The keeper's side (new Receive screen)

- Top: link, QR, address, "USDC only".
- A "Waiting to add" card appears when the vault holds more than it has accounted: "120 USDC arrived. Add it to your vault." One button, `claimReceived`. Dust below a small threshold is hidden.
- A received list in Activity, labelled by finality (Submitted, Confirmed, Final).
- If the Chog is not escrowed (no vault yet, or released), the card says why it can't be added and offers "Take it back" (`sweepUnaccounted`) once there is a vault.

## Edge cases to design for

- **Before the vault exists.** The address is deterministic, and an ERC-20 sent there is just a balance on an address with no code. When the vault is opened at that address the balance should show up as unaccounted and be claimable. This is the part that must be tested on Anvil before the link is offered pre-vault.
- **After release or sale.** Payments follow the Chog's vault, not a person. After a sale the new keeper receives them. The pay page should show the current keeper's status ("This Chog changed hands on [date]") so a payer with an old link is not surprised. For creators paying holders, this is the intended behaviour.
- **Wrong token.** Anything not allowlisted lands as unaccounted and can only be swept out. The app shows it under "Sent by mistake" with a Take it back button.
- **Empty check.** Unaccounted funds do not block releasing the Chog, so a keeper could release while a payment sits in the vault. The app should warn "Something arrived. Add or take it back first" before release. Contract change not needed, UI only.
- **Dust and spam.** Strangers can send worthless tokens. The app shows only allowlisted tokens above a threshold by default.
- **Pending sale.** A claim voids signed terms by design. The Receive screen warns when an offer is open.

## What this is not

- Not a promise of income. The Chog itself pays nothing; people choose to send money to a vault.
- Not custody by us. The vault is the keeper's own, and no pooled account exists.
- Not a Chog-team feature. Whether payer-facing pages may show Chog art is part of the still-unconfirmed art permission.

## To do before building

1. Add `claimReceived` with unit tests, a fuzz test (accounting never exceeds balance) and a test that a claim voids a signed sale.
2. Anvil test: transfer USDC to the predicted vault address, open the vault, claim it.
3. Add one Receive screen to the wireframes.
4. Legal check on the payments angle (see the research note).

## Built so far

`AccountVault.claimReceived(token)` is in, with 11 new tests (9 vault, 2 sale) and 7 hand-made mutants all caught: controller-only, escrow and allowlist gates, nonce bump, no double count, a payment sent before the vault exists, a fee-on-transfer token credited at what actually arrived, a fuzz that accounting never exceeds the balance, a claim voids a signed sale, and a stranger's unclaimed dust does not. Full suite: 281 passed, 0 failed (fork tests skipped without an RPC). Not done: the Anvil run of the whole path, slither on the change, and the Receive screen.

## Which tokens can be received

Only tokens on the registry allowlist, which is set when the registry is deployed and has no setter. Native MON cannot be sent at all (no `receive()`), only WMON. See the chat answer recorded in `docs/ux/TOKEN_SUPPORT.md`.
