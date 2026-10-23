# Chog Credit app

React + TypeScript + viem. No wallet library: it talks to the browser wallet directly. Styling follows `docs/brand/DESIGN.md`; screens follow the wireframes (`docs/ux/`).

Built so far: Connect, Pick your Chog, Open a vault, Account overview, Add assets, Borrow and Repay, Withdraw, Release, plus a Risk explainer. Not built yet: Sell, Activity, Lend, Receive, Settings. All of it runs against test deployments with mock assets.

## Brand and motion

Ported from the brand board and motion board, not just `DESIGN.md`: the Account Card (Chog frame, status chip, ring with one pink dot, Chog bubble, tear line with notches, the three numbers), the Slip (favicon and Connect page), the Full Stop wordmark, the Vault Door, the Confirmed pop and tick, the Submitted/Confirmed/Final steps, error shake, the press settle, and entrance rise with stagger (`src/styles/motion.css`). Sound and haptics follow the board's table (`src/feedback.ts`): sound off by default, offered once after the first confirmed transaction, risk sounds a separate switch. Onboarding uses the cream Chog register; money screens use the dark Ledger register.

Not ported yet: the health-dot slide on change is a CSS transition (not the board's keyframes), digit roll, chip swap, Pause Drill, skeleton shimmer on every loading state, the once-ever tear-off, sticker sparkles on repay.

## Run it on a local chain

```
cd contracts && forge build            # ABIs come from the Foundry build
cd ../app && npm install && npm run abis
./e2e/reset.sh                         # fresh Anvil, deployment, and a lender with 5,000 USDC
npm run dev                            # http://127.0.0.1:5173/?dev=1
```

`?dev=1` (dev server only, local chain only) signs with Anvil's first test key so no browser wallet is needed. Without it the app asks the browser wallet to connect and switch network. For another network, put its deployment manifest at `public/deployment.json`.

## Check it

`npm run typecheck`, then with the dev server running: `node e2e/flow.mjs` walks the whole money flow in a headless browser and fails on the first broken step.

## Honest limits

- Test deployments only. The Watch and At-risk lines are sample values (`src/chain/status.ts`).
- The "after adding" borrow limit ignores per-account caps, so it is an estimate.
- Final means the block is below Monad's finalized tag (two blocks on a local chain).
- Chog art is a neutral placeholder: art permission is not confirmed.
- Not tested with a real browser wallet or on phones.
