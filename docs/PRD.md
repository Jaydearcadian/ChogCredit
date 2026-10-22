# Product Requirements Document: Chog Credit

**Version:** 0.2  
**Status:** Revised target requirements; implementation not yet aligned  
**Date:** 22 October 2026  
**Target ecosystem:** Chog / Monad  
**Primary identity:** existing Chog NFT, keyed by collection address and token ID

## 1. Product summary

Chog Credit adds a portfolio account and collateral-backed credit utility to an existing Chog NFT. The user selects a Chog NFT they already own; the product associates it with a controlled vault for supported assets and positions. Where eligible collateral and liquidity permit, the account can borrow USDC without automatically closing the underlying position. The existing Chog NFT remains the account's canonical identity. The initial architecture must not require the user to mint a new Position NFT.

The initial collection candidate is Chog Genesis on Monad at `0xc96d31f8626c6d03fae5dcd3d61e3fb9f4a73763`, based on public NFT-marketplace records. This address is not approved for production configuration until the team verifies it through official Chog sources, on-chain bytecode, chain ID and ERC-721 behavior. The collection contract must be configurable, not silently hard-coded.

The product does not mint Circle-issued USDC. It borrows USDC from funded liquidity. The Chog NFT's collectible value may be a future collateral component only if an executable recovery path and conservative valuation model are approved. A marketplace floor alone is not a credit oracle.

## 2. Problem statement

Chog NFTs are currently recognizable collection assets; the product hypothesis is that they can become the identity for a financial package that also holds eligible positions, tracks obligations and supports credit. A user who needs liquidity should not automatically be forced to close an otherwise supportable position. But simply attaching metadata to an NFT does not create custody or enforce debt. The system must define which contracts own assets, who can control them, how value is recovered and what happens when the Chog NFT is transferred.

## 3. Goals

### Product goals

1. Let a user select an eligible existing Chog NFT they already own.
2. Create or retrieve exactly one account for each `(chainId, collectionAddress, tokenId)` without minting a new identity NFT.
3. Associate a controlled vault with the Chog account and hold only explicitly supported assets and positions.
4. Display collateral composition, valuation source/freshness, available credit, debt, interest, health factor and transaction history.
5. Allow borrow and repay against funded USDC liquidity with on-chain solvency checks.
6. Keep supported collateral positions open during borrowing where the selected integration allows it.
7. Prevent a transfer or release of the Chog NFT from detaching a non-empty portfolio or bypassing an active debt obligation.
8. Provide an accurate testnet demo and evidence of successful contract transactions before claiming working on-chain credit.

### Product learning goals

- Validate whether Chog holders value financial utility attached to the existing NFT more than a separate account collectible.
- Measure whether the portfolio account and credit line are understandable to NFT holders and DeFi users.
- Validate first-collateral valuation and liquidation assumptions before real liquidity is introduced.
- Test user acceptance of locking the Chog NFT in protocol escrow whenever its account carries positions/assets or secured credit.
- Test whether buyers and sellers understand portfolio-package transfers and, later, debt-bearing transfers and their liabilities.

## 4. Non-goals for initial release

- Minting a new Position NFT as the product identity.
- Minting Circle-issued USDC.
- Treating the Chog NFT's unverified marketplace floor price as automatically borrowable collateral.
- Accepting every NFT, ERC-20, LP position or DeFi receipt.
- Arbitrary calls from the account vault.
- Cross-chain credit or bridge-based collateral.
- Unlimited/recursive leverage or fully autonomous financial agents.
- Claiming account history predicts future returns or guarantees repayment.
- Debt-bearing transfers through normal ERC-721 transfers while the NFT remains externally transferable.
- Public mainnet lending before reliable valuation, liquidation, accounting and independent security review.

## 5. Personas and jobs to be done

### U1: Chog holder

“I own a Chog NFT. Show me what it unlocks, what account it is connected to and how I can keep control of the NFT.”

### U2: Position holder

“My capital is deployed in a supported position. Show me whether it can support a credit line and let me borrow without closing it if the protocol can safely support that.”

### U3: Active on-chain operator

“I need USDC for another opportunity. Tell me how much I can borrow, where the money will go, how debt grows and what can trigger liquidation.”

### U4: Liquidity supplier

“Show me available cash, borrower exposure, interest, withdrawals, reserve policy and how losses are allocated.”

### U5: Portfolio buyer (later release)

“Show me the Chog identity, positions, value, debt, account permissions and transfer conditions before I acquire the package.”

### U6: Risk/liquidation operator

“Identify unhealthy accounts and execute permitted recoveries under deterministic rules.”

## 6. Release scope

### Release A: design and UI prototype

- Chog Credit branding and existing-Chog-first user journey.
- Clearly labelled sample/demo state.
- UI concepts for portfolio, collateral, credit, repay, health and transfer restrictions.
- No claim that sample account data, borrowing or contract addresses are live.

### Release B: local/testnet contract plumbing

- Configurable Chog-like ERC-721 test collection (mock only for test environments).
- Account registry keyed by collection and token ID; no new Position NFT.
- One account vault per Chog identifier.
- Escrow the original Chog NFT before the first portfolio asset/position enters the vault or secured credit activates; release only after the account is empty and obligations are settled.
- Mock USDC, one explicitly supported test collateral class and capped test liquidity.
- Borrow, repay, collateral deposit/withdraw checks, liquidatable-state tests and wallet-connected testnet UI.
- Local-fork tests for the actual Chog collection where practical. A mock-collection test does not prove integration with the live collection.

### Release C: live collection ownership verification

- Verify the exact official collection address, token standard and transfer behavior.
- Read and display the user's real Chog NFTs from the configured collection.
- Verify wallet owns a selected token on-chain before account creation/deposit.
- Never accept a lookalike collection or metadata-only ownership claim.
- Decide whether first public demo remains testnet-only, uses a local mainnet fork, or performs limited live mainnet transactions. No default real-funds mode.

### Release D: one genuine supported position adapter

- Implement one actual Monad position integration only after verifying its valuation method and unwind path.
- Use conservative LTV/haircut, price freshness, caps and liquidation testing.
- The app shows the position remains open after borrowing if that exact integration truly permits it.

### Release E: portfolio package market

- Transfer a portfolio-bearing, debt-free Chog account through an atomic coordinator, with buyer acceptance of account state and settlement.
- Keep the original Chog NFT escrowed while its account carries assets/positions.
- Do not claim ordinary third-party NFT marketplace compatibility unless a verified integration preserves package integrity.

### Release F: debt-aware package market and further collateral

- Add buyer-signed acceptance of outstanding debt, accrued interest, minimum health, state nonce and expiry.
- Add marketplace settlement for debt-bearing accounts.
- Additional positions, collectible-NFT collateral valuation (if separately approved), account history and constrained automation follow their own risk reviews.

## 7. Functional requirements

Priority definitions: **P0** blocks safe functional testnet prototype; **P1** required for credible collection integration or usable testnet; **P2** later capability.

### FR-01: Network and collection configuration (P0)

- System MUST verify the connected chain ID against the deployment manifest.
- The Chog collection contract MUST be explicitly configured by address and environment.
- The system MUST verify the selected contract's ERC-721 behavior and `ownerOf(tokenId)` result before granting control.
- Production configuration MUST require a reviewed collection address. The candidate Chog Genesis address is a research lead, not a silent constant.
- The UI MUST show network, contract mode and whether the asset is a live Chog NFT or a test collection token.

### FR-02: Chog identity and account lookup (P0)

- User MUST be able to select an existing Chog NFT they own.
- System MUST derive the account key from `chainId + collectionAddress + tokenId`.
- The same account key MUST NOT create a duplicate vault or duplicate debt ledger.
- The product MUST NOT require minting a separate Position NFT.
- Account creation must store collection address, token ID, vault address, account version and creation block/transaction.

### FR-03: Account vault custody (P0)

- Vault MUST hold only explicitly supported assets and position receipts.
- Owner actions MUST be checked against account state, escrow status, protocol pauses and collateral lock state.
- Unsupported assets MUST be reported as ineligible and contribute zero credit capacity.
- The vault MUST NOT expose unrestricted arbitrary calls.
- Actual received token balance, not the requested transfer amount alone, MUST determine recognized deposits.

### FR-04: Deposit and supported position registry (P0)

- Deposit UI MUST list exact supported assets with address, valuation source, haircut, LTV, liquidation threshold and exit route.
- A deposit MUST fail for an unsupported asset or when required price/adapter checks fail.
- Position-specific NFT receipts require a verified adapter for custody, valuation and unwind.
- Deposited position state MUST be updated from confirmed chain state.

### FR-05: Credit valuation (P0)

- Credit value MUST derive only from supported, recoverable collateral and approved policies.
- The Chog collectible NFT itself MUST contribute zero to capacity unless a specific NFT valuation and recovery module is approved, tested and configured.
- A marketplace floor price, rarity trait or metadata field MUST NOT directly determine credit limit.
- Collateral values MUST round down; debt MUST round up.
- Stale, missing, negative or implausible valuation data MUST fail closed for new borrowing and risk-increasing actions.

### FR-06: Borrow availability (P0)

- Contract MUST cap borrowing by account capacity, current debt, available USDC pool cash, account/pool caps and collateral state.
- UI MUST distinguish collateral capacity from actual available pool liquidity.
- Available credit MUST never be shown as cash already held by the user.
- Loan terms and post-borrow health factor MUST be previewed before wallet signature.

### FR-07: Escrow lock before portfolio custody or active credit (P0)

- Before the first portfolio asset/position is deposited, or before secured credit becomes active, the original Chog NFT MUST be transferred into approved protocol escrow unless an independently verified collection-level mechanism can enforce equivalent transfer controls.
- Escrow MUST verify caller authorization and current owner, exact collection, token ID and approval.
- While any portfolio assets/positions, secured debt/obligation or blocking pending operation remains, direct release of the Chog NFT MUST fail.
- Escrow MUST record beneficial owner separately from ERC-721 `ownerOf`.
- No arbitrary administrator path may change beneficial owner or withdraw the NFT.

### FR-08: Borrow USDC (P0)

- Borrow MUST use existing funded USDC pool liquidity or a clearly identified test token.
- Borrow MUST recheck current collateral value, price freshness, debt, pool cash, caps, pause state and post-borrow health on-chain.
- Default product mode SHOULD deliver borrowed USDC to the account vault so it can be deployed into an allowed market; any wallet withdrawal mode must be explicit and account for the resulting asset/debt state.
- UI and docs MUST say “borrow USDC,” not “mint USDC,” unless a separately designed protocol-issued token exists.

### FR-09: Interest and debt display (P0)

- UI MUST show principal, accrued interest, fees where applicable and total debt.
- Interest model, accrual timing, rounding and repayment priority MUST be specified.
- The displayed debt MUST be derived from a chain read or clearly labelled indexer snapshot with block/time.
- Prototype linear interest MUST be marked as a prototype simplification.

### FR-10: Repayment (P0)

- User MUST be able to repay partial or full debt according to the declared accounting policy.
- Contract MUST use safe token transfers and actual amounts received.
- Full settlement MUST update escrow/registry state atomically or make NFT release available only after fresh on-chain checks confirm the account is empty, all debt/fees are settled and no blocking operation remains.
- Failed transactions MUST not mark the account as repaid.

### FR-11: Collateral withdrawal (P0)

- Withdrawal MUST be prohibited if it would break collateral lock, account solvency or other pending obligations.
- When debt exists, the first release may disable partial withdrawal for simplicity.
- UI MUST state whether withdrawals are restricted by debt or pool policy.

### FR-12: Liquidation and recovery (P0 before funded/public credit)

- The system MUST calculate liquidation eligibility on-chain from validated current prices.
- Liquidation MUST specify close factor, repay cap, incentive, seize/unwind method, debt remainder and bad-debt treatment.
- Healthy accounts MUST not be liquidatable under the same valid state.
- If collateral has no tested recovery path, it MUST NOT be accepted as credit collateral.
- Liquidation cannot depend on an admin manually changing a price.

### FR-13: Lender liquidity and accounting (P0 before external liquidity)

- Public liquidity requires supplier claims/shares, cash availability, debt receivables, interest, fee/reserve and loss reconciliation.
- Withdrawals MUST reflect available cash and any documented withdrawal queue.
- UI MUST show the actual pool balance and withdrawal restrictions.
- The one-account testnet pool may be simplified with test funds but MUST not be labelled public/production lending.

### FR-14: Account history (P1)

- Show deposit, borrow, repay, interest, liquidation, escrow, release and transfer events.
- Attribute each event to account and actor/operator at that time.
- UI MUST distinguish account history from the current owner's personal track record.

### FR-15: Package transfer and NFT release (P1)

- Any account with portfolio assets/positions or secured obligations MUST keep the original Chog NFT in protocol escrow.
- When a portfolio-bearing, debt-free account is sold, the approved coordinator MUST transfer beneficial control atomically and bind buyer acceptance to the account state.
- NFT release to an ordinary wallet requires an empty portfolio, zero debt/fees, no liquidation in progress and no blocking pending operation.
- When the NFT is wallet-held and the account is empty, account control follows verified `ownerOf(tokenId)`. After release, ordinary collection transfer mechanics resume.

### FR-16: Debt-bearing transfer (P2)

- Active-debt package transfer MUST occur only through the account's approved coordinator while the Chog NFT remains escrowed.
- Buyer MUST sign the exact account ID/state nonce, maximum debt, minimum health, price/settlement terms and expiry.
- Transfer MUST be atomic with state/ownership update and settlement rules.
- Ordinary NFT marketplace transfers cannot be claimed supported during escrow unless a separately audited integration proves the full path.

### FR-17: NFT collectible value as collateral (P2)

- It may be enabled only with an approved valuation method, executable auction/sale recovery, market-depth constraints, caps and stress tests.
- No simple collection floor feed or trait/rarity score is sufficient.
- If conditions are not met, the NFT component contributes zero borrowing value and positions inside the account may still qualify.

### FR-18: Approved second-market execution (P1 for “use elsewhere” demo)

- A real second-market step MUST call a verified, allowlisted integration and show the confirmed receipt/position after execution.
- Adapter MUST bound target, selector, supported assets, slippage, deadline and expected output.
- Post-action collateral solvency MUST be checked in the same transaction where observable.
- If not implemented on-chain, the UI MUST label it as a simulation and not show it in the live transaction ledger.

### FR-19: Admin and emergency behavior (P0)

- Production role separation, multisig, timelock and guardian pause MUST be specified.
- Emergency pause MUST not give arbitrary power to seize NFTs or user assets.
- Pause behavior for borrow, repay, liquidation, safe exit, escrow release and adapter execution MUST be explicit and tested.

### FR-20: Security events and monitorability (P1)

- Emit events for account creation, escrow, release, beneficial owner change, deposit, borrow, repay, collateral config updates, adapter calls, liquidation and pause changes.
- Indexer must reconcile events with direct contract reads and handle chain reorganizations.

## 8. UX requirements

### Required screens

1. **Chog selection:** actual owned NFTs from the configured collection, with collection provenance and token IDs.
2. **Chog account overview:** original NFT art, linked vault, supported portfolio, debt, credit capacity, account state and owner/escrow status.
3. **Collateral detail:** accepted asset, amount, valuation source, freshness, haircut, LTV, liquidation threshold, recoverability and exit method.
4. **Credit preview:** requested borrow, actual pool cash, rate/fees, post-borrow health and what happens to escrow/NFT custody.
5. **Borrow/repay:** wallet-signed transaction, clear pending/confirmed/failed state and actual transaction hash.
6. **Market use:** approved destinations only; simulations visibly separated from real transactions.
7. **Activity/evidence:** contract events with transaction links and block timestamps.
8. **Transfer:** package-aware transfer for escrowed portfolios, NFT release only after the account is empty, and debt-bearing transfer only when its coordinator is implemented.
9. **Risk & terms:** liquidation explanation, eligibility rules, protocol risks and liquidity limits.

### Mandatory copy rules

- Say **“Chog NFT”** for the existing collection token; do not describe a new Position NFT as the product anchor.
- Say **“associated account/vault”** for the financial state linked to the token.
- Say **“borrow USDC from pool liquidity”**, not “mint USDC.”
- Label mock tokens, local forks, sample numbers and simulated market interactions.
- State that the original NFT is escrowed while its account holds portfolio assets/positions or secured obligations, unless verified collection-level controls enforce equivalent package-transfer restrictions.
- Never say “risk-free,” “guaranteed credit,” or “your floor price is your credit limit.”

## 9. Analytics and evaluation

Measure: eligible Chog selection success; account creation success; time from selection to account overview; supported collateral deposits; borrow/repay success; credit preview abandonment; failed transactions by reason; escrow lock/release correctness; collateral utilization; realized liquidation recovery in simulations; pool liquidity availability; account transfer test outcomes; and user comprehension of the escrow/transfer trade-off.

Do not optimize only for total borrowing or NFT trading volume. Monitor liquidations, near-liquidations, losses, user confusion, failed exits and concentration alongside product usage.

## 10. Non-functional requirements

- **Security:** no private-key custody by backend; strict adapter allowlists; reentrancy protection; conservative arithmetic; safe transfer semantics; tested access control.
- **Reliability:** manifest-driven addresses; chain ID verification; read-after-write confirmation; graceful RPC failures; reorg-aware indexing.
- **Transparency:** exact contract addresses and verification status shown for every environment.
- **Performance:** first wallet/account read should be responsive under normal RPC conditions; API caches must show freshness and never override chain truth.
- **Accessibility:** contrast, keyboard paths, explicit labels and non-color-only risk states.
- **Privacy:** do not infer off-chain personal credit score from public transaction history; public chain data and operational analytics must be described accurately.

## 11. Release gates

### Gate G0: collection/product definition

Official collection selected; address confirmed; legal/brand permissions checked; product scope and custody/escrow trade-off approved.

### Gate G1: source and local correctness

Pinned dependencies and compiler; reproducible build; account-key uniqueness; ERC-721 integration tests; escrow state machine; unit/fuzz/invariant tests.

### Gate G2: risk and economics

First collateral class and liquidation route verified; oracle/source, haircut, caps, interest and pool accounting reviewed; bad-debt scenarios simulated.

### Gate G3: testnet flow

Deploy and verify contracts; wallet UI uses matching deployment manifest; complete create/select → deposit → escrow → borrow → repay → release flow verified with test tokens; all transactions evidenced by hashes.

### Gate G4: restricted pilot

Independent security review, critical/high finding remediation, multisig/timelock, monitoring, runbooks, pool liquidity and exposure limits.

### Gate G5: public/mainnet credit

Legal review, all G0-G4 passed, verified collection integration, approved collateral recovery, functioning liquidation, lender accounting and no unresolved critical/high issues.

## 12. Definition of done

The revised product is aligned only when the actual existing Chog NFT is the primary account identifier in the UI, registry, contracts and docs; no second Position NFT is required; account assets/debt are enforced on-chain; portfolio-bearing NFTs cannot be transferred outside the package coordinator while account state is attached; and every live capability has compile/test/deployment evidence. A coherent document set alone does not meet technical completion.

## 13. Explicit unresolved decisions

1. Which official collection is the exact Chogathon target? Chog Genesis is the present candidate, not a final hard-coded choice.
2. Can the original Chog NFT's own sale value contribute to credit, and what protocol-run recovery/auction path makes that value realizable?
3. What is the first genuine portfolio position/asset collateral class?
4. Who provides USDC liquidity, and what are lender withdrawal/loss rules?
5. Is protocol escrow acceptable while positions/assets are attached, and should package trading use an integrated marketplace? What transfer experience is acceptable when debt is active?
6. Which second market can be integrated safely on Monad within the hackathon scope?

