# Chog Credit app

React + TypeScript + viem, with RainbowKit on wagmi for wallets. Anyone can look around without a wallet: the Chogs tab lists every vault, and any account, its Activity and the Risk page are read-only from the chain. A wallet is asked for only when you act.

Wallets: browser-extension wallets (MetaMask, Rabby, Phantom and others) and Coinbase Wallet work with no key. Phone wallets over WalletConnect (QR code or deep link) need a WalletConnect Cloud projectId, which RainbowKit requires; set `VITE_WALLETCONNECT_PROJECT_ID` to turn them on. Without it, a phone browser with no wallet is offered links that open the app inside MetaMask, Phantom, Coinbase Wallet or Trust. Styling follows `docs/brand/DESIGN.md`; screens follow the wireframes (`docs/ux/`).

Built so far: Connect, Pick your Chog, Open a vault, Account overview, Add assets, Borrow and Repay, Withdraw, Release, plus Risk and Settings. Not built yet: Sell, Activity, Lend, Receive. All of it runs against test deployments with mock assets.

## Brand and motion

Screens are built from the brand board, not just `DESIGN.md`: board 4 (app screens: Account overview, Borrow preview, the Pause Drill), board 3 (the cream landing hero, used for Connect), board 2 (the Account Card), board 6 (the Slip, the Full Stop wordmark, the Pixel Key) and board 7 (motion, sound and haptics). Styles live in `src/styles/` as real stylesheets: `tokens.css`, `base.css`, `components.css`, `cream.css` (the Chog register) and `motion.css`.

Motion moments, all with a reduced-motion form:
- screen entrance (rise 12 px, 60 ms stagger) and route changes through View Transitions, with the header and tab bar held still and the Chog frame morphing between Pick, Open and Account
- Vault Door when a Chog goes in; the stamp pulses once
- the health dot slides and the arc follows (300 ms); changed digits roll, up or down
- Safe to Watch chip swap; the bubble pops (the only overshoot)
- the Pause Drill: Borrow locks in place with the padlock closing, Repay does not move (checked by `e2e/live.mjs`)
- transaction steps that fill only when reached, with the Confirmed pop and tick draw
- error shake (3 x 9 px) with the message staying, and a one-tap fix
- skeletons after 100 ms; button press under 100 ms with a 200 ms settle
- the once-ever tear-off of the Slip's stub after the first borrow; sparkles and "Debt-free. Look at you." on a full repay
- the landing card's 6 px float, wide screens only, with a pause control

Sound and haptics follow board 7 (`src/feedback.ts`): sound off by default and offered once after the first confirmed transaction, risk sounds a separate switch, haptics off under reduced motion. The Account screen refreshes every 5 seconds while visible, so price moves play out in place.

## Run it on a local chain

```
cd contracts && forge build            # ABIs come from the Foundry build
cd ../app && npm install && npm run abis
./e2e/reset.sh                         # fresh Anvil, deployment, and a lender with 5,000 USDC
npm run dev                            # http://127.0.0.1:5173/?dev=1
```

`?dev=1` (dev server only, local chain only) signs with Anvil's first test key so no browser wallet is needed. Without it the app asks the browser wallet to connect and switch network. For another network, put its deployment manifest at `public/deployment.json`.

## Check it

`npm run typecheck`, then with the dev server running and after `./e2e/reset.sh`: `node e2e/flow.mjs` walks the money flow, `node e2e/motion.mjs` walks the motion moments, and `node e2e/live.mjs` flips the mock oracle from outside while the Account screen is open (the Pause Drill, live). Each fails on the first broken step.

## Honest limits

- Test deployments only. The Watch and At-risk lines are sample values (`src/chain/status.ts`).
- The "after adding" borrow limit ignores per-account caps, so it is an estimate.
- Final means the block is below Monad's finalized tag (two blocks on a local chain).
- Chog art is a neutral placeholder: art permission is not confirmed.
- Not tested with a real browser wallet or on phones.
