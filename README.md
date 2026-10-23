# Chog Credit

A vault and a credit line for a Chog Genesis NFT on Monad. Lock a Chog in its own vault, add assets, borrow USDC from a lender pool, and get the Chog back when you repay. Or sell the whole vault, loan included, in one signed step.

**Live (Monad testnet, mock assets, unaudited):** https://chog-credit.vercel.app

You do not need a wallet to look around. The **Chogs** tab lists every vault; any account, its Activity and the Risk page are read-only from the chain. A wallet is asked for only when you act.

## What it does

- **The Chog is the key, not the collateral.** It is never priced and never taken. It sits in escrow while its vault holds assets or owes money; empty the vault and repay and it comes back.
- **Assets in the vault back the loan.** WMON counts toward the limit; `$CHOG` can be held but counts for nothing. Uniswap V3 positions can count at the oracle price (contracts done and tested; not switched on in the testnet deployment).
- **Lend USDC** to the pool and earn the interest borrowers pay.
- **Sell with Vault.** The buyer signs exactly what they take on (a ceiling on the loan, a floor on vault value and health); the seller completes the sale. A sale with a loan can pay part of the loan off from the price.
- **If prices fail, borrowing and withdrawing stop; repaying never does.** Health shows only with a loan.

## Try it in two minutes

1. Open the live site, press **Look around first**, and open a vault from the Chogs tab (read-only).
2. Connect a wallet on Monad testnet. No test MON? Ask for some from the Monad testnet faucet.
3. **Pick your Chog**: press **Get a test Chog**, then **Open vault** (the Chog moves into escrow).
4. **Add assets**: **Get test tokens**, add WMON. See the borrow limit move before you sign.
5. **Borrow** USDC: watch health and the status chip before you sign. Then **Repay**.
6. Open **Lend**, supply some USDC, withdraw it.
7. **Sell** (with a second wallet): write an offer with a price and a part-payoff; the buyer opens the link, approves and signs; you complete the sale.
8. The wallet that deployed the test contracts sees **Settings, Test controls**: pause the mock prices and watch Borrow lock while Repay stays.

## Testnet deployment (Monad testnet, chain 10143)

| | |
|---|---|
| Registry | `0x54Cd5CF6907eA09c5E279143A3dBc5450F92abc0` |
| Pool | `0xB3b7b18d2aa26e5d763C98f18B6E38c783479476` |
| Escrow | `0xf4e19B246F1b3c7d453c4541F04B310ED40d2C22` |
| Sale coordinator | `0xba02316BB390EAf2737D6E725d38786D55Af334f` |
| Test Chog faucet | `0x0be53D767B2eEB55fa5C7A7Ba271125fdaAabb48` |
| Mock USDC / WMON / $CHOG | `0x92A3890EF30589b5A67e34955C4628EC059DFd33` / `0x16E1Bd42F7C0FfD28D10919C87CaD22d05f2aA29` / `0x36f30B2E5fa115bC7D1A1a6177a523202aC1b730` |

All assets are mocks, the price source is an owner-set mock, and the Chog collection is a mock. Nothing here touches the real Chog Genesis collection.

## Repo map

- `contracts/` Foundry project: account registry, vault, escrow, sale coordinator, credit pool, oracle adapter, factory, mocks, tests (unit, fuzz, invariants, mutation scripts, mainnet-fork), deploy and smoke scripts.
- `app/` the web app (React, TypeScript, viem, RainbowKit on wagmi). See `app/README.md`.
- `docs/` product docs, specs, evidence per build gate, the brand (`docs/brand/`) and UX flows (`docs/ux/`). Start at `docs/README.md`; the honest status is `docs/IMPLEMENTATION_STATUS.md`.
- `config/`, `scripts/` Monad reference data and measurement scripts (feed analysis, liquidity model, contrast check).
- `index.html`, `backend/` an earlier prototype, kept for history. Not part of the product.

## Run it locally

```
cd contracts && forge test                 # unit, fuzz and invariant tests
cd ../app && npm install && npm run abis
./e2e/reset.sh                             # local chain, deployment, a lender
npm run dev                                # http://127.0.0.1:5173/?dev=1
```

`app/e2e/` has browser walks: `flow`, `motion`, `live`, `sell`, `lend`, `browse` (local) and `testnet`, `testnet-sale`, `testnet-pause` (real testnet, throwaway keys).

## Honest limits

- Testnet only. Not audited. No real funds.
- The price source is a mock. The real Chainlink feeds were measured (`docs/evidence/FEED_ANALYSIS.md`); wiring them in, and sizing caps against measured exit depth, come before any mainnet.
- Legal review is pending for selling accounts that carry debt. The Chog team has not confirmed use of the Chog name or art, so art is a neutral placeholder.
- Admin and emergency-recovery roles are switched off. Phone wallets over WalletConnect need a WalletConnect project ID (`VITE_WALLETCONNECT_PROJECT_ID`).
- Real browser wallets and phones have had limited testing; the browser walks use a stand-in wallet.

## Keeping testnet prices real

The testnet price source is a mock oracle. `app/scripts/price-keeper.mjs` copies the live MON/USD Chainlink price from Monad mainnet onto it, and onto the mock Uniswap pool so pool positions stay priceable:

```bash
cd app && KEEPER_KEY=<deployer testnet key> node scripts/price-keeper.mjs            # every 5 minutes
cd app && KEEPER_KEY=<deployer testnet key> node scripts/price-keeper.mjs --once     # one pass
```

It refuses mainnet, skips while a Pause Drill is on, skips a stale feed, and writes only when the price moved by 0.5% or 30 minutes passed. The key must be the oracle owner (the deployer) and must be a testnet-only key.
