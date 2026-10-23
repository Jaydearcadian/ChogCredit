# Has this been done? Prior art, payments and money-in for a Chog

Research run with the Parallel search API on 2026-10-23: six topic searches, 60 results. I read the returned excerpts, not full pages, so every claim below is only as strong as the excerpt behind it. Absence of a competitor in these results is not proof that none exists.

## 1. What exists

**NFT-backed lending (loans against a JPEG).** Done, and mostly shrinking.
- NFTfi, the first protocol of this kind, announced on 2026-06-02 that it is shutting down. Its front end goes offline on 2026-08-31. Its own post cites about $737M lifetime volume across 82,000+ peer-to-peer loans.
- DappRadar reported NFT lending volume down 97% from peak, with about $82M outstanding across Blend, Gondi and others. A quoted view: models built on volatile, illiquid NFT collateral were fragile.
- BendDAO nearly failed in August 2022. A paper on it reports a 94% liquidation failure rate at the peak, because auctions for NFTs could not clear.

Lesson for us: lending against the NFT's price is the failed model. Chog Credit lends against fungible assets in the vault and uses the Chog only as the key, so this failure does not apply. Keep it that way, and never count Chog floor price as collateral.

**NFT-bound accounts (ERC-6551).** The standard exists and is final-ish prior art for "an account per NFT". I found the standard itself but no lending protocol built on it in these results. That does not prove there is none.

**Streams as NFTs.** Sablier wraps every stream in an ERC-721 and says the stream is tradable and usable as DeFi collateral (it even sketches lending against future income). Superfluid does recurring streams and subscriptions on several chains, not Monad in the pages I saw.

**Undercollateralised and cash-flow credit.** Goldfinch (off-chain collateral, community-vetted), Maple, TrueFi, Wildcat, plus a field of on-chain credit scores (Cred, Spectral, RociFi, ChainAware). A 2026 arXiv paper (zLend) builds underwriting from reconstructed on-chain cash flow. This is real but is the high-risk end of DeFi.

**Rentals.** ERC-4907 and ERC-5501 add a time-limited "user" role to NFTs. The standard's own text mentions a rental platform and a mortgage platform sharing one NFT.

**Not found in these results:** a product that gives each NFT its own vault, escrows the NFT while the vault is funded or indebted, and lets the whole thing, debt included, be sold in one signed step. I cannot claim it is unique, only that these searches did not surface it.

## 2. Monad context (why now)

From Monad's own posts (July to September 2026; figures differ between posts, so treat as order of magnitude):
- USDC is native on Monad (Circle), with CCTP.
- Stablecoin market cap stated as above $550M, $684M and $767M in different posts. DeFi TVL above $1.02B (Aug 31).
- Visa and Mastercard support stablecoin payments on Monad; Rain issues cards that spend stablecoins; an Agentic Payments Alliance led by Rain has 26 members.
- An Aave V4 deployment on Monad is proposed, with USDC and USDT0 borrowable. That is a lending competitor for fungible borrowers, not for a Chog-keyed account.

## 3. Payments and money tied to a Chog: options

The Chog is a stable identity with a deterministic vault address, so money can be tied to it. Ranked by fit and risk.

1. **Pay to a Chog (low risk, strong fit).** Anyone can pay USDC straight into a Chog's vault, so the Chog has an address that receives. The vault address is predictable before the vault exists (`predictVault`), which could allow payment links per Chog. Needs a test: tokens sent to the address before the clone is deployed must still be usable once it is. Also show the sender's note off-chain only.
2. **Earnings land in the vault, which already backs credit.** A creator, game or community pays holders into the vault. Inflow raises collateral on its own, with no new credit logic. This is the cleanest "money inflow tied to a Chog" and needs no new risk model.
3. **Sell the vault with its inflow history.** Buyers see a record of payments received. Informational only. Do not price it into the loan.
4. **Streams into the vault (medium).** Point a Sablier or Superfluid stream at the vault. The vault currently refuses ERC-721 transfers except accepted positions, so it cannot hold a stream NFT, but a stream whose recipient is the vault address would deliver tokens. Needs checking per protocol and per chain support on Monad.
5. **Cash-flow credit (high risk, later).** A higher limit because of steady inflow. This is undercollateralised lending. Do not build before an audit, a loss model and a legal view. Park it.
6. **Rentals via ERC-4907 (separate product).** Possible, but the escrow holds the Chog, so a rental would need the "user" role set by the escrow. Do not mix with the credit launch.

Recommendation: ship 1 and 2 first as a "receive" feature (a Receive screen with a payment link per Chog). They reuse what is built, add no credit risk, and give the product a reason to be opened daily rather than only when borrowing.

## 4. Legal and regulatory flags (not advice)

- US: a law-firm alert (Crowell, 2026-08-11) says digital-asset collateral earns no capital relief for banks, nonbank lenders may need state licensing, and New York's UCC Article 12 took effect 2026-06-03, changing how a security interest in digital assets is perfected. Lending to consumers against vault assets may need licensing in some places.
- Securities: an NFT that pays revenue or dividends can look like a security. A Blockchain Association letter to the SEC makes this point about NFTs programmed to pay dividends, and the SEC published a March 2026 interpretive release on crypto assets that I did not read in detail. For options 2 and 3, the payer sends money to a holder's vault, but the Chog itself should not promise any return. Do not market the Chog as an income product.
- Payments: receiving and sending stablecoins through an app can create money-transmission questions in some jurisdictions. A non-custodial design (the user's own vault, no pooling by us) helps but does not settle it.
- All of this needs a lawyer before mainnet. The existing assumed-debt-transfer review is still open.

## 5. What to decide next

1. Do we add a Receive screen (options 1 and 2) to the wireframes? Recommended: yes, one screen, and one board note.
2. Test counterfactual payment to a not-yet-deployed vault address on Anvil before promising it.
3. Keep cash-flow credit and rentals on the roadmap only.
