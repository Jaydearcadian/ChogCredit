# $CHOG in Chog Credit, and how a holder could earn more of it

Facts are from the research notes in `docs/evidence/` and the Oct 2026 market pages cited there (Kuru, OpenSea, CoinGecko, chog.xyz). Prices move; treat as order of magnitude. Rewards below are proposals. Nothing here is built, promised or agreed with the Chog team.

## Where $CHOG stands in the product today

- **Held in a vault: yes.** It is on the vault allowlist as a vault-only token with zero credit value (Gate E3). A holder can keep $CHOG in their Chog's vault and a buyer of the package receives it.
- **Received: yes.** With `claimReceived`, $CHOG sent to a vault can be counted into it. It still adds no borrowing power. The Receive wireframe (S24) says so on the card.
- **Collateral: no.** Measured depth is thin (token market cap about $1.5M to $2M, about $95K to $111K liquidity across pools, 24h volume in the low thousands of dollars), and a liquidation would have almost nothing to sell into.
- **Can the protocol give out $CHOG?** Only if it first holds some. We do not control the token's supply, and the credit pool has no fee or reserve: all interest goes to lenders. So rewards need an outside source.

## The size of the prize

1,969 Chogs, about 978 owners, 1B $CHOG supply. If the Chog team set aside 1% of supply (10M $CHOG) and split it evenly per Chog, each Chog gets about 5,080 $CHOG, about $7.60 at $0.0015. Rewards of this kind are a thank-you, not income. The value is in the utility, so any promise of "earning" should be modest and honest.

## Ways a Chog holder could accrue more $CHOG

Ranked by how well they fit the product and how little risk they add.

1. **Team airdrops delivered to the vault (best fit).** The Chog team (or community treasury) sends $CHOG to each Chog's vault address, per Chog, from a snapshot. Receive makes this deliverable even to Chogs with no vault yet, and the $CHOG travels with the Chog when it is sold. One Chog is one account, so it cannot be split to farm more. Source of funds: the team. Our work: Receive, plus a simple CSV or script for the team to run.
2. **Time-in-vault rewards.** The team streams $CHOG to Chogs that keep a vault open and escrowed, weighted by days. Reuses the escrow record we already have. Source of funds: the team. Risk: rewards the Chog for being locked rather than for any service, which looks closer to yield (see legal below).
3. **Share of protocol revenue, bought back as $CHOG.** Not possible today because there is no protocol fee. It would need a fee switch added to the pool and a buyback. With about $100K of liquidity, buybacks must be tiny or they move the price. Defer.
4. **Lender incentives.** Pay $CHOG to those who supply USDC to the pool. This is liquidity mining: it brings money in fast and leaves fast. It rewards lenders, not the average Chog holder. Only worth it if the pool needs depth.
5. **Points first, token later.** Count activity (days in vault, repaid loans, payments received) as off-chain points with no promise attached, and let the Chog team decide later whether points turn into an airdrop. Cheapest and the safest first step.

## What I recommend

1. Ship Receive so any airdrop can land in a Chog's vault.
2. Offer the Chog team a one-off airdrop tool (option 1) and say clearly it is their decision and their tokens.
3. Run points (option 5) with the words "no promise of value" until legal review.
4. Do not add rewards that pay for borrowing, since that rewards taking on debt.

## Risks to name

- **Borrow to farm.** Any reward tied to borrowing invites loops that raise risk for lenders.
- **Dump pressure.** 5,000 $CHOG each is small, but 1,969 holders selling into $100K of liquidity can move the price. Vesting or streaming softens it.
- **Securities and consumer law.** A reward that pays holders of an NFT for holding it can look like a return. The research note (`docs/research/NFT_CREDIT_PRIOR_ART_AND_PAYMENTS.md`) lists the flags. Needs a lawyer before any live reward. This is not legal advice.
- **Chog team permission.** Using the Chog art, wordmark and the token in marketing is still unconfirmed in writing.
- **Token contract.** We have not reviewed the $CHOG implementation. A fork test showed a deposit works, not that it is safe against future changes.
