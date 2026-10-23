# Chog Credit app

React + TypeScript + viem. No wallet library: it talks to the browser wallet directly. Styling follows `docs/brand/DESIGN.md`; screens follow the wireframes (`docs/ux/`).

Built so far: Connect, Pick your Chog, Open a vault, Account overview, Add assets, Borrow and Repay, Withdraw, Release, plus a Risk explainer. Not built yet: Sell, Activity, Lend, Receive, Settings. All of it runs against test deployments with mock assets.

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
