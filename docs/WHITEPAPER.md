# Chog Credit

## Financial utility for Chog NFTs on Monad

**Document:** Product and protocol whitepaper  
**Version:** 0.2  
**Status:** Proposed design, not a claim of a live or audited deployment  
**Date:** 22 October 2026  
**Target ecosystem:** Chog / Monad  
**Working product name:** Chog Credit

> **Status and risk notice**  
> Chog Credit is a proposed product design. The currently bundled prototype still uses a newly minted `ChogPositionNFT` and does not integrate the existing Chog NFT collection. It must not be treated as implementation of this revised architecture. The current code has not been compiled, test-verified, deployed or audited in the present environment. The collection address below is a candidate reference observed on NFT-marketplace listings and must be verified against the project's official source and on-chain bytecode before use. No real funds should be deposited into the existing prototype.

---

## Abstract

Chog Credit gives an existing Chog NFT a financial role. Instead of asking the user to mint a second, competing “position NFT,” the product associates the user's Chog NFT with a controlled financial account. The account can hold supported assets and DeFi positions, expose its financial state, and use eligible collateral to borrow USDC from a funded liquidity pool.

The Chog NFT remains the canonical identity for the package. A registry maps the collection contract and token ID to a portfolio account. The account holds the assets and positions; it also records the obligations that arise from borrowing. A user may be able to access liquidity without closing an eligible position. In a later phase, the portfolio package can be traded through a protocol-controlled transfer flow that discloses and preserves account-level obligations.

This distinction matters technically. An ERC-721 token cannot automatically carry contract storage, assets or debt simply because its metadata points to them. Those financial state changes must be enforced by contracts. Further, if the original collection contract permits ordinary transfers and has no integration hook, a separate lending contract cannot prevent every transfer of that NFT. Chog Credit therefore proposes locking the original Chog NFT in protocol escrow once the account holds portfolio assets/positions or secured obligations. A portfolio-bearing Chog must trade through a protocol-controlled package-transfer flow so the buyer sees and acquires the associated state, not only the image. Debt-bearing transfers require an additional explicit debt-acceptance workflow. Once the account is empty and all obligations are settled, the NFT can be released to its beneficial owner and traded normally again.

The credit line is based on recoverable collateral, not on the mere existence of an NFT. Eligible portfolio assets and positions can count toward borrowing capacity when the protocol can value, control and liquidate them. The original Chog NFT itself may count as an additional collateral class only when there is a reviewed, executable recovery path and conservative valuation policy. A marketplace floor price by itself is not enough.

Chog Credit borrows USDC supplied by lenders, a treasury or another clearly disclosed liquidity source. It does not mint Circle-issued USDC. A separate protocol-issued stablecoin would require its own issuance, reserve, redemption and legal design.

## 1. The product in one sentence

**Chog Credit turns a Chog NFT into the identity of a financial package that can hold supported positions and, when sufficiently collateralized, access USDC credit without automatically exiting those positions.**

### Product promise

“Your Chog. More than a collectible.”

The promise is not that every Chog immediately becomes borrowable, that every NFT has a reliable credit value, or that the product eliminates financial risk. Eligibility depends on verified ownership, supported collateral, real pool liquidity, valuation quality and on-chain risk checks.

## 2. Problem and opportunity

### 2.1 Existing NFTs are not financial accounts

A collectible NFT normally identifies an item and its ownership. Assets, DeFi positions, debt, permissions and history usually live in other contracts. Those references do not themselves give the NFT custody, control or enforceable financial behavior.

### 2.2 Liquidity can require an unwanted exit

A user or business can have capital in an eligible on-chain position and want to act in another market without unwinding the first position. Credit can make that possible, but only where collateral is valued conservatively and the lending facility can recover it after default.

### 2.3 The product opportunity is the package, not the picture

Chog Credit connects three elements under one account identity:

1. **The original Chog NFT:** the collection asset selected by the owner and the stable identity key (`collectionAddress + tokenId`).
2. **The portfolio account:** the vault and supported adapters holding assets and positions associated with that Chog.
3. **The credit facility:** the debt, interest, risk limits, repayment path and liquidation rights associated with that account.

The NFT image or metadata is not where assets are stored. The account registry and vault implement the financial relationship.

### 2.4 Account transfer introduces a separate problem

A normal ERC-721 transfer can change NFT ownership without requiring a buyer to accept the associated account's debt. If the NFT is freely transferable outside the protocol, the protocol cannot claim it has enforced buyer acceptance. Chog Credit must therefore use escrow whenever an account carries assets/positions or secured obligations, or adopt a different collection-level integration that can be formally verified. Otherwise, an ordinary marketplace sale could transfer control of the portfolio without package-aware buyer consent. The initial proposal is escrow because it does not assume control over the existing collection contract.

## 3. Product principles

- **Use the existing Chog NFT.** Do not mint a separate Position NFT as the product's primary identity. Any optional receipt or wrapper must be justified as infrastructure, not presented as a replacement for Chog.
- **The original NFT is the account key.** Each account is uniquely identified by chain, configured Chog collection address and token ID.
- **Financial value must be enforceable.** Assets, debt and permissions live in contracts with clear authority checks, not merely in metadata or a backend database.
- **Recoverable value over display value.** Collateral contributes to credit only if the protocol can realize it through an approved path.
- **NFT market value is not automatically credit value.** Chog Genesis collectible value can only count if there is a reviewed liquidation method, conservative valuation source, caps and sufficient market depth. Floor prices alone are insufficient.
- **Do not force a position exit to borrow.** Where the selected collateral and protocol adapter allow it, the user can keep the existing position while the credit facility lends USDC.
- **The package must remain intact.** While an account carries assets/positions or secured obligations, the Chog NFT remains held by escrow. A package-bearing transfer must be coordinated and atomic; when debt exists, buyer consent must explicitly bind the debt and risk state.
- **USDC is borrowed, not minted.** The pool lends existing USDC liquidity. Mock USDC is strictly a local/testnet development token.
- **Start narrow.** One Chog collection, one borrowing asset, a limited collateral set and a restricted adapter set are preferable to unsupported generalized claims.
- **Distinguish source from evidence.** A proposed requirement, source file, passing test, verified testnet deployment, audit and mainnet release are distinct states.

## 4. Product components

### 4.1 Chog NFT identity

The product targets the existing Chog NFT collection. A candidate reference for **Chog Genesis on Monad** is collection contract `0xc96d31f8626c6d03fae5dcd3d61e3fb9f4a73763`. Public marketplace records describe token IDs from that collection as ERC-721 items on Monad. This is a research lead, not sufficient release verification. Before configuration, the team must confirm the address from an official Chog-controlled source, verify `eth_chainId`, inspect bytecode and ERC-721 behavior, and establish the exact collection in the hackathon brief.

The collection address is configuration, not a hard-coded assumption. If the intended collection is a different official Chog NFT collection, the deployment manifest and product configuration must change before integration. Fake or lookalike collections must never be accepted just because they use the Chog name or artwork.

### 4.2 Chog Account Registry

The registry maps `(chainId, collectionAddress, tokenId)` to one account record and vault. It prevents duplicate account creation, records account versions and exposes the current control mode. It does not invent NFT value or mint a second identity NFT.

### 4.3 Portfolio Account Vault

The account vault holds accepted fungible collateral and supported position receipts. It exposes portfolio state and allows owner-authorized actions subject to account state, escrow state, approved adapters, debt obligations and risk checks. Unsupported tokens may be displayed as ineligible but contribute zero borrowing capacity.

The vault is not a generalized arbitrary-call wallet in the first release. It can interact only with approved tokens, adapters, targets and function selectors. All actions that can impair collateral recovery must be checked against account-level policy.

### 4.4 Chog Credit Pool

The pool accepts USDC liquidity from disclosed suppliers and lends available cash against account collateral. Production design must account for supplier claims/shares, accrued interest, fees, reserves, withdrawals, bad debt, caps and losses. A narrow prototype can use capped test liquidity, but it must not be represented as production lender accounting.

### 4.5 Chog NFT Escrow and Account Controller

Because an external NFT contract may not expose a hook that allows Chog Credit to reject wallet-to-wallet transfers, the protocol must escrow the original Chog NFT before it accepts a portfolio asset/position or activates secured credit. The escrow records the beneficial owner and exposes controlled release/transfer functions. During escrow, the ERC-721 `ownerOf(tokenId)` returns the escrow contract, while the product registry identifies the beneficial account owner.

- An empty account may be registered while the NFT stays in the user's wallet. Control is derived from the verified current collection owner.
- Before the first portfolio asset/position is deposited, or before credit becomes active, the user approves and deposits the original NFT into Chog Credit escrow.
- While assets, positions, debt or secured pending operations remain in the account, the NFT cannot be withdrawn to an ordinary wallet. A portfolio-bearing sale must pass through the account transfer coordinator so the buyer accepts the package state. Debt-bearing sales also require explicit acceptance of the exact debt and risk state.
- Only when the account is empty and all obligations/pending operations are cleared can escrow return the NFT to the beneficial owner.

This creates a clear trade-off: while an account carries positions/assets or debt, standard third-party NFT marketplaces will not see the collectible held in the owner's wallet. A protocol-controlled package market can transfer the NFT together with its account state; broader external marketplace compatibility is a later integration and cannot bypass escrow.

### 4.6 Collateral registry and valuation adapters

Every collateral class must specify its contract, valuation adapter, liquidation adapter, LTV, liquidation threshold, haircut, price freshness, caps and pause behavior. LP or receipt positions require protocol-specific adapters that calculate underlying amounts and execute a recoverable unwind path. If a reliable price or unwind is missing, that collateral contributes zero credit value.

The Chog collectible itself is a possible collateral class only if the protocol can execute a compliant sale or auction to repay debt. A third-party collection floor price is not an oracle. Until the NFT recovery path and market assumptions have been tested, NFT-specific collateral value is zero in the credit calculation; supported assets inside the associated vault may still qualify.

### 4.7 Optional history and delegation

The account can expose deposited assets, borrows, repayments, interest, liquidation events, fees and position changes. History must distinguish account-level events from the activity of the owner/operator at the time. It cannot imply that a new NFT holder personally earned prior results. Permissioned automation is a later phase with limits, expiry, revocation and action allowlists.

## 5. Core user journeys

### 5.1 Discover and connect a Chog

1. User connects a wallet on the supported Monad network.
2. Application verifies chain ID and configured collection address.
3. Backend/indexer or direct RPC reads only token IDs belonging to the configured collection and verifies ownership on-chain.
4. User selects a Chog NFT they own.
5. The system creates or retrieves the account record keyed by collection and token ID. No new Position NFT is minted.
6. The product shows the Chog, linked vault address, accepted assets, account history and which actions are currently available.

### 5.2 Associate positions

1. User selects an explicitly supported asset or position.
2. Interface explains custody, valuation method, liquidation treatment and relevant risks.
3. If this is the first non-zero portfolio deposit, the user approves and deposits the original Chog NFT into escrow first.
4. The user approves and deposits the supported asset/position into the account vault.
5. Registry and valuation adapter confirm custody and eligible value.
6. Unsupported positions remain visible as “not eligible” and contribute zero collateral value.

### 5.3 Activate a credit line

1. UI computes indicative capacity from eligible account collateral and pool liquidity.
2. Before borrowing, the user reviews loan terms, collateral values, interest, caps, health factor and liquidation policy.
3. If the account is not already escrowed, the user signs a transaction to deposit the original Chog NFT into protocol escrow and associate the beneficial owner with the escrowed account.
4. The contract confirms the expected collection address, `ownerOf`, token approval, unique account mapping and safe-transfer state.
5. User approves/initiates the borrow. The pool rechecks collateral, liquidity, debt, price freshness and caps on-chain.
6. USDC is transferred to the portfolio vault by default, or to a pre-approved receiver under the explicit product mode. The default vault destination supports the “use liquidity in another market” workflow.
7. The app waits for a confirmed transaction and reads the post-transaction state from chain.

### 5.4 Use liquidity in another market

Borrowed USDC can be held in the account or deployed through an allowlisted integration. The adapter must specify accepted target, assets, min-out/slippage limit, deadline, and post-action collateral policy. A UI-only simulation does not count as the market integration. If no real adapter is implemented, the product labels this step as a simulation and disables real transaction claims.

### 5.5 Repay and release

1. UI retrieves debt including accrued interest and applicable fees.
2. User repays USDC with an explicit allocation policy for interest, fees and principal.
3. Contract verifies the actual received amount and updates state.
4. When the portfolio is empty, all debt/fees are settled and no operation is pending, the escrow releases the original Chog NFT to the beneficial owner.
5. Normal external transfers resume because the portfolio is empty and the protocol no longer needs to preserve package integrity in escrow.

### 5.6 Trade a Chog carrying positions

1. Seller creates a listing for the account package, not merely the artwork.
2. Buyer sees token ID, linked positions/assets, conservative recoverable values, debt and interest if any, account health, permissions, valuation block/time, and restrictions.
3. Buyer signs acceptance for the exact account state/nonce, price/settlement terms and expiry. If debt exists, the signature also binds maximum debt and minimum health factor.
4. The coordinator checks signatures, expiry, pause status, portfolio state, market terms, current beneficial owner and all account controls.
5. A single atomic transaction settles payment and updates beneficial ownership. The original NFT remains escrowed as long as portfolio assets/positions or debt remain.
6. If any check fails, the transfer reverts. Direct withdrawal from escrow is impossible while the account contains assets or secured obligations.

## 6. Credit and collateral model

### 6.1 Sources of credit

The protocol lends funded USDC. The credit limit is the minimum of:

- risk-adjusted capacity from supported portfolio collateral;
- any separately approved value from the Chog NFT itself, where a recoverable NFT liquidation route exists;
- account and asset caps;
- pool debt caps; and
- available USDC liquidity.

### 6.2 Conservative value

For collateral class `i`:

`eligibleValue_i = conservativeGrossValue_i × (1 − valuationHaircut_i)`

`weightedBorrowValue_i = eligibleValue_i × maxLTV_i`

`availableToBorrow = max(0, min(sum(weightedBorrowValue_i) − currentDebt, accountCapRoom, poolCapRoom, availablePoolLiquidity))`

All values are integer-scaled on-chain. Collateral rounds down; debt rounds up. Borrowing capacity is not a promise to lend if pool liquidity is unavailable.

### 6.3 Position valuation

A position's valuation must reflect what a liquidator can recover, not merely a dashboard mark. It should account for underlying token amounts, accepted token prices, uncollected fees only where realizable, slippage, liquidation costs, concentration, protocol risk and unwind time. Unsupported positions contribute zero.

### 6.4 Chog NFT collateral

The original Chog NFT is central to account identity and transfer semantics. Its financial market value must be handled as a separate risk module. The product may later count a conservative amount from the NFT's own resale value if the protocol has an executable and reviewed sale path, market-depth assumptions, manipulation controls, caps, auction rules and explicit collection-specific parameters. It must not use a marketplace floor number as if it were cash-equivalent collateral. In the absence of those controls, the NFT's contribution to borrowing capacity is zero, while positions held in its vault can still support credit.

### 6.5 Health factor and liquidation

`healthFactor = liquidationAdjustedCollateralValue / totalDebt`

A health factor below `1.0` can trigger liquidation according to the collateral policy. Exact calculations, close factors, collateral seizure, incentives, partial liquidations and bad-debt accounting must be implemented and tested for the actual collateral type. An admin-set demo price is unsuitable for real funds.

### 6.6 Interest and lender accounting

The production pool needs deterministic interest accrual, supplier share accounting, cash/debt/reserve reconciliation, withdrawal availability, bad-debt recognition and documented loss allocation. An interaction-triggered prototype interest update and nominal liquidity records are not a production pool model.

## 7. Differentiation

NFT-backed loans and token-bound accounts already exist in the wider ecosystem. Chog Credit should not claim that NFT collateral by itself is novel. The proposed differentiated product combines:

- the existing Chog NFT as the recognizable account identity rather than a second minted Position NFT;
- portfolio state and selected supported positions attached to that NFT's account;
- collateral-backed liquidity with visible risk and recoverable-value constraints;
- a controlled escrow and account-transfer path that can preserve liabilities and buyer consent; and
- a Chog-native interface that makes financial utility understandable to collectors and DeFi users.

These are hypotheses to validate, not claims of exclusive technology or guaranteed competitive advantage.

## 8. Architecture overview

```text
Existing Chog ERC-721 collection
             |
             | (collection address, tokenId)
             v
     ChogAccountRegistry  ----> account state / current control mode
             |
             v
   AccountVault / adapters <----> CollateralRegistry / ValuationRouter
             |                               |
             | collateral                    | eligible value / freshness
             v                               v
        ChogCreditPool <---------------- risk validation
          |     |     |
          |     |     +--> Liquidation / recovery paths
          |     +--------> debt + interest + lender accounting
          +--------------> funded USDC liquidity

Portfolio-bearing account / secured operations:
Existing Chog NFT -> ChogCreditEscrow -> TransferCoordinator (later)
                       | beneficial owner
                       +-- external transfer/release disabled while account is non-empty

Off-chain: wallet UI, read API/indexer, transaction/activity monitor, deployment manifest
```

The original collection's public owner and the account's beneficial owner are distinct while the NFT is escrowed. APIs and interfaces must expose that state rather than falsely reporting the escrow address as the user. Escrow is required while the account is non-empty, not only while debt exists, so ordinary transfers cannot silently separate the collectible from its portfolio.

## 9. Security model

Key controls include exact collection allowlisting, ERC-721 ownership verification, unique account mapping, escrow accounting, safe-transfer checks, vault authorization, conservative valuations, oracle freshness, debt and pool invariants, adapter allowlists, reentrancy protection, debt-aware transfer consent, role separation, monitoring, caps, pause matrices and invariant/fuzz tests.

The escrow is a core trust boundary. It must not allow an admin or arbitrary caller to redirect a Chog NFT or account assets. Beneficial owner updates must only occur through a documented release or transfer path. NFT approval must be limited to the specified escrow/market flow and must not grant arbitrary spend permission over unrelated assets.

The original Chog collection contract is external. Chog Credit cannot upgrade it, add transfer hooks to it, or assume all NFT transfers pass through Chog Credit. Locking the NFT in protocol escrow while account assets/positions or credit obligations are attached is therefore a product requirement, unless independent verification establishes a stronger supported integration.

## 10. Phased delivery

### Phase 0: collection and scope verification

- Confirm exact official Chog NFT collection and address, token standard, transfer behavior, rights/branding permissions and hackathon requirements.
- Define the first collateral class, liquidation route, USDC source and lending economics.
- Approve architecture for the account registry and escrow.

### Phase 1: test harness and account identity

- Remove the newly minted Position NFT as primary identity.
- Integrate a configurable Chog collection interface.
- Test owner verification, `(collection, tokenId)` account uniqueness, vault mapping, deposit/withdrawal and escrow locking using a test Chog ERC-721.
- Add a local fork test against the real collection where practical.

### Phase 2: funded testnet credit loop

- Use test tokens for USDC and eligible collateral.
- Implement deposit, conservative valuation for the selected test collateral, borrow, repay, restrictions and liquidation tests.
- Verify escrow behavior for first portfolio deposit, package transfer and active debt.
- Connect wallet transactions and read back confirmed state.

### Phase 3: actual position adapter and destination market

- Integrate one actual supported Monad position only after verifying valuation and liquidation behavior.
- Add one approved second-market adapter if the product promises deployment of borrowed USDC.
- Test slippage, failures, exits and solvency after the operation.

### Phase 4: controlled collection integration and debt-free package trading

- Verify the live collection address and deploy manifest.
- Implement package transfer for escrowed, debt-free accounts, requiring buyer acceptance of the disclosed account state and atomic settlement.
- Decide how live collection ownership will be verified and how users enter escrow.
- Conduct security review, economic simulations, access-control review and incident planning.
- Use conservative caps; do not launch public credit based on admin-set prices.

### Phase 5: debt-bearing transfer and richer credit

- Extend the package-transfer coordinator with atomic buyer acceptance of outstanding debt, accrued interest and account health while the original NFT remains escrowed.
- Add multiple position types, verified portfolio history and limited delegated strategies only after each adapter has its own risk review.

## 11. Success criteria

- Users understand that Chog is the original collection NFT and not a separately minted account collectible.
- The interface consistently maps a real eligible Chog to one portfolio account.
- No duplicate account can be created for the same chain, collection and token ID.
- Active debt cannot be bypassed by transferring or releasing the NFT.
- Borrowing never exceeds eligible collateral value, configured caps or actual pool cash.
- Repayments, accrued debt and pool accounting reconcile under tests.
- Any claimed second-market deployment is a real verified contract interaction, not a UI simulation.
- The app clearly labels test tokens, demo state, supported collateral and unavailable features.

## 12. Decisions required before a funded deployment

1. Which official Chog NFT collection is in scope for the hackathon: Chog Genesis or another collection?
2. What exact official source confirms the collection contract address and transfer behavior?
3. Will the Chog NFT's own collectible market value contribute to collateral, and if so, what liquidation route and valuation policy support it?
4. What position type is the first real collateral and how can it be liquidated on Monad?
5. Should borrowed USDC default to the account vault, and what is the first approved destination market?
6. Who supplies initial USDC liquidity and what are the interest, withdrawal and loss-allocation rules?
7. Is an in-protocol marketplace acceptable for debt-bearing transfers while the NFT is escrowed?
8. Which rights/branding permissions apply to displaying official Chog artwork in the product?

## References and verification leads

- Chog Genesis token pages on OpenSea identify collection `0xc96d31f8626c6d03fae5dcd3d61e3fb9f4a73763` as an ERC-721 collection on Monad. This is a marketplace observation, not substitute for official project confirmation: https://opensea.io/item/monad/0xc96d31f8626c6d03fae5dcd3d61e3fb9f4a73763/532
- ChogWorks also refers to Chog Genesis and shows the shortened collection address `0xc96d…3763`; this is a third-party integration, not collection-owner authority: https://chogworks.fun/
- ERC-721 standard: https://eips.ethereum.org/EIPS/eip-721
- ERC-6551 token-bound accounts (optional pattern, not the default product identity): https://eips.ethereum.org/EIPS/eip-6551
- Chainlink Data Feeds guidance: https://docs.chain.link/data-feeds
- Revert Lend supported NFT position lending is useful prior art; it demonstrates that “NFT-backed lending” alone is not a sufficient novelty claim: https://revert.finance/

