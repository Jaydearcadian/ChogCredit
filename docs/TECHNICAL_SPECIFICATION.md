# Chog Credit: Full Technical Specification

**Version:** 0.2  
**Status:** Revised target architecture; existing source is not yet aligned  
**Date:** 22 October 2026  
**Network:** Monad EVM  
**Canonical identity:** existing Chog ERC-721 collection + token ID

> MUST / MUST NOT define normative requirements. SHOULD / SHOULD NOT define strong recommendations. MAY defines optional behavior. This is the target specification, not proof that the current source implements it. Current source creates a separate `ChogPositionNFT`; that component must be removed from the primary identity path or refactored before claiming alignment.

## 1. Scope and release boundaries

This specification covers the existing Chog NFT identity, registry/account creation, vault custody, escrow locking while account assets/positions or debt are attached, funded USDC credit, collateral valuation, liquidation, optional adapters, package-aware transfers, backend indexing/API, wallet UX, tests and deployment.

### 1.1 Explicit implementation states

- **Existing code slice:** an unrelated new `ChogPositionNFT`, a one-ERC20 collateral credit contract using an admin-set price, simple interaction-triggered interest, mock assets, a read-only Express/viem API and a disconnected HTML UI. This is a source scaffold, not the target architecture. Do not deploy it as the Chog Credit collection integration.
- **Required local/testnet prototype:** configurable collection interface using a Chog-compatible test ERC-721; registry key `chainId + collection + tokenId`; no new Position NFT; account vault; escrow state machine; mock USDC; capped pool; borrow/repay; safe release; wallet-connected UI and evidence ledger.
- **Required live collection integration:** verified official Chog collection address and on-chain ERC-721 behavior; real ownership reads; approval/escrow interactions; careful chain environment choices. Mock collection tests alone do not prove live collection integration.
- **Production target:** approved position adapters, independently reviewed oracle/valuation, liquidations, complete pool/share accounting, multisig and timelock, monitoring, external audit and controlled account trading.

### 1.2 Environment identity

| Environment | Chain ID | RPC | Collection/token policy |
|---|---:|---|---|
| Local Foundry/anvil | local configured ID | local node | test Chog ERC-721 and mock tokens only |
| Monad testnet | `10143` | `https://testnet-rpc.monad.xyz` | mock Chog-compatible collection and mock USDC; label as simulated/test environment |
| Monad mainnet | `143` | `https://rpc.monad.xyz` | actual approved Chog collection and approved tokens only; no mocks |

Every frontend, backend and deployment script MUST validate `eth_chainId` against the deployment manifest. A working RPC URL is not sufficient to establish network identity.

### 1.3 Chog collection configuration

A candidate Chog Genesis address surfaced in public NFT marketplace records is:

`0xc96d31f8626c6d03fae5dcd3d61e3fb9f4a73763`

Treat it as a **candidate to verify**, not a production constant. Before use, engineers MUST confirm the collection using an official Chog-controlled source or explicit project confirmation, inspect bytecode and ERC-721 behavior on Monad mainnet, verify `ownerOf`, `getApproved`/`isApprovedForAll`, safe transfer behavior, and test actual approved/escrow transfers. Configuration MUST permit another official collection if the hackathon definition names a different Chog NFT.

No name, symbol, image, collection metadata or third-party listing alone establishes official collection identity. The deployment manifest records the full address, chain ID, source of authority, code hash where applicable, ERC-165/interface results, verification timestamp and reviewer.

## 2. System architecture

```text
Wallet / browser
  |  read collection ownership, sign transactions
  v
Frontend --------------------------> Read API / indexer / monitoring
  | write calls                              ^ chain-derived read model
  v                                          |
Chog collection (external ERC-721)           |
  | collection + tokenId                     |
  v                                          |
ChogAccountRegistry ----> AccountFactory ----> AccountVault
  | account state/owner mode                     | assets/positions
  |                                              v
  |                                   allowlisted position adapters
  |                                              |
  +--> ChogCreditEscrow <----> TransferCoordinator (later)
            | holds original Chog NFT during secured credit
            | beneficial owner + lock state
            v
      ChogCreditPool <---- CollateralRegistry / ValuationRouter
        | USDC cash           | value/freshness/caps
        | debt/index          v
        |                 Liquidation/Recovery adapters
        +--> lender share accounting (production)

Config/admin: multisig + timelock; narrow guardian pause; event monitoring
```

### 2.1 Core contracts

| Contract/module | Required responsibility | Forbidden behavior |
|---|---|---|
| `ChogAccountRegistry` | One account record per `(chainId, collection, tokenId)`; owner/control mode; vault lookup; versions | Mint a replacement Chog identity; allow duplicate accounts; trust metadata for ownership |
| `AccountFactory` | Deploy/create one vault for an account key and initialize references | Give arbitrary target calls or uncontrolled delegatecall |
| `AccountVault` | Hold accepted assets/position receipts; account owner actions and adapter calls | Bypass collateral locks, debt constraints, delegate policy or pause rules |
| `ChogCreditEscrow` | Hold original Chog NFT while portfolio assets/positions or secured obligations exist; map beneficial owner; controlled release | Let arbitrary admin/caller withdraw token or silently reassign beneficial ownership |
| `ChogCreditPool` | USDC cash, debt, rates, borrow/repay and liquidation accounting | Mint Circle USDC or lend beyond cash/caps |
| `CollateralRegistry` | Supported assets, risk parameters, adapter/oracle refs and caps | Treat inclusion as proof of recoverability |
| `ValuationRouter` | Return conservative value, freshness and source metadata | Use stale/invalid source or marketplace floor as guaranteed value |
| `PositionAdapterRegistry` | Allowlist reviewed adapters, targets, selectors and versions | Permit arbitrary account `call(target,data)` or unchecked delegatecall |
| `LiquidationEngine` | Check unhealthy accounts and execute bounded recovery | Seize without debt/bonus calculations or leave untracked bad debt |
| `AccountTransferCoordinator` | Atomic package transfer, with extra debt/health consent when debt exists | Be bypassable via a direct NFT transfer or escrow release |
| `ProtocolConfig` | Risk parameter roles, caps, pauses and delays | Single EOA immediate unrestricted production control |

First testnet build MAY combine registry/config/liquidation logic to save deployment steps. Separation of account custody, escrow ownership and debt accounting must remain explicit in state and tests.

## 3. Canonical identity and account state

### 3.1 Account key

Use a unique key derived from:

```solidity
bytes32 accountKey = keccak256(
    abi.encode(block.chainid, collectionAddress, tokenId)
);
```

The account key MUST include chain ID and full collection address. Token ID alone is not globally unique. The registry stores collection, token ID, vault address, account creation block/time, implementation version, custody mode, beneficial owner, escrow status, state nonce and optional debt reference.

No separate `ChogPositionNFT` is required. The existing Chog NFT is the recognizable identity; the vault is a contract account referenced by registry state.

### 3.2 Wallet-held mode

When the Chog NFT is held in the user's wallet and the account is empty, the account controller may derive authority from `IChogCollection(collection).ownerOf(tokenId)`. Every privileged action MUST re-read current on-chain owner or use a verified owner snapshot that cannot survive an ownership change. Do not cache a wallet address indefinitely.

If the NFT transfers while wallet-held, its account MUST be empty; control then follows the verified current owner. Once a position/asset is to be deposited, the NFT moves into escrow first, and assets and supported positions are associated with the escrowed account so they can be transferred only as an acknowledged package.

### 3.3 Escrow-held mode for portfolio-bearing accounts

The existing collection contract is external and may not support credit-protocol transfer hooks. A separate contract cannot reject transfers that bypass it. Therefore, before an account can accept its first portfolio asset/position or active secured debt, the original Chog NFT MUST be transferred to `ChogCreditEscrow` using the collection's approved safe-transfer flow.

Escrow state includes:

```solidity
struct EscrowRecord {
    address collection;
    uint256 tokenId;
    address beneficialOwner;
    bytes32 accountKey;
    uint64 escrowedAt;
    uint64 stateNonce;
    bool locked;
}
```

When escrowed, `ownerOf(tokenId)` correctly returns the escrow contract. The registry/API MUST display both legal token holder (escrow) and beneficial account owner. Beneficial ownership changes only by the controlled release or transfer coordinator.

The NFT MUST NOT be released while any portfolio asset/position, debt, accrued interest, payable fee, pending liquidation, secured adapter operation, unsettled package sale, or blocking account lock remains. “Debt equals zero” alone is insufficient if a liquidation/settlement operation is pending.

### 3.4 Trade-off and supported transfer behavior

While an account holds positions/assets or debt, the original NFT is escrowed and standard external NFT marketplaces cannot treat the beneficial owner as the current ERC-721 owner. This is deliberate: a generic NFT listing must not sell an image while silently transferring associated positions, and a debt-bearing transfer must not evade buyer consent. The target behavior is:

- empty account: NFT may be released and traded normally; account control follows verified `ownerOf(tokenId)`;
- portfolio-bearing, debt-free account: package can be sold through the Chog Credit coordinator, with buyer acceptance of the disclosed account state;
- portfolio-bearing account with debt: later release requires buyer acceptance of exact debt, health and terms;
- no direct release from escrow while any account assets/positions or secured obligations remain.

Do not claim full OpenSea/third-party package-trade compatibility in the initial release. An external marketplace adapter is an additional integration and must preserve escrow/consent semantics. If escrow is rejected as a product trade-off, the architecture needs a separately verified collection-level control hook; it cannot simply assume the protocol can freeze a third-party ERC-721.

### 3.5 Escrow safety

- Only configured collection addresses may be escrowed.
- Only the actual current owner may begin escrow, with correct token approval.
- `onERC721Received` MUST validate collection, sender and an expected deposit state/nonce to prevent unsolicited or counterfeit deposits being registered.
- Deposit must be atomic with registry/account state transition or have safe rollback behavior.
- Escrow must not `delegatecall` untrusted targets.
- Admin roles must not be able to redirect assets or beneficial ownership through an emergency function.
- A recovery process for accidental NFT deposits must be explicit, narrowly scoped, event-emitting and incapable of bypassing an active debt lock.
- Collection address must be immutable or changed only through reviewed migration governance. Changing collection configuration must never make existing accounts ownerless.

## 4. Vault custody and adapter model

### 4.1 Vault creation

Factory function semantics:

```solidity
function getAccountKey(address collection, uint256 tokenId)
    external view returns (bytes32);
function getOrCreateAccount(address collection, uint256 tokenId)
    external returns (bytes32 accountKey, address vault);
function accountOf(bytes32 accountKey)
    external view returns (address vault);
```

Exact ABI may vary. Creation MUST verify the collection is allowlisted and `ownerOf(tokenId)` is valid. It MUST reject duplicate/colliding account identities and token ID zero only if the actual collection/product policy requires that restriction (ERC-721 token ID zero can be valid). `getOrCreateAccount` must be idempotent.

### 4.2 Vault controls

The vault MUST enforce:

- owner/beneficial owner authorization according to wallet-held or escrow-held mode;
- explicit delegate policies and expiry if delegates are enabled;
- supported token/position IDs and approved adapters only;
- collateral lock checks before withdrawals/actions;
- post-action health checks for risk-increasing operations where on-chain values are observable;
- nonce increments on material account/permission/asset/debt/transfer state changes;
- pause rules that preserve safe repayment where possible;
- non-reentrant and safe-transfer behavior.

### 4.3 Supported asset classes

Each asset class requires a registry entry and an independent valuation/recovery plan. Supported classes may include ordinary ERC-20 tokens, LP position NFTs, staking/yield receipts and later market positions. “Visible in account” does not imply “eligible collateral.” Unknown or unrecoverable assets have zero credit value.

### 4.4 Strategy execution

A strategy/second-market action is performed only through an allowlisted adapter. Adapter config defines target contracts, function selectors, accepted tokens, amount bounds, minOut/slippage, deadline, output asset and post-action collateral requirements. Any transaction path that moves USDC outside the vault MUST be clearly disclosed. A mock second-market contract may be used for a testnet demo; that is not evidence of a real market integration.

## 5. Collateral registry and valuation

### 5.1 Configuration

A collateral configuration SHOULD contain:

```solidity
struct CollateralConfig {
    address assetOrPositionManager;
    address valuationAdapter;
    address liquidationAdapter;
    uint16 maxLtvBps;
    uint16 liquidationThresholdBps;
    uint16 liquidationBonusBps;
    uint16 valuationHaircutBps;
    uint16 maxConcentrationBps;
    uint256 supplyCap;
    uint256 accountCap;
    uint32 maxPriceAgeSeconds;
    bool enabled;
}
```

The exact ABI may differ, but every risk parameter requires an event, bounds checking, an authorization role and a documented change delay in production. `maxLtvBps` must be lower than the liquidation threshold expressed under a consistent unit convention. Parameters should be versioned so the UI and indexer can explain which policy applied to an event.

### 5.2 Oracle requirements

For any collateral accepted for borrowing:

- source must be verified to exist on the target network and support the exact asset;
- decimals and quote units must be explicit;
- answer must be positive and timestamp/round state fresh;
- large deviation, stale feed and missing answer states must fail closed for risk-increasing actions;
- config changes must be timelocked, event-emitting and monitored;
- a spot DEX price alone must not be used for large collateral when manipulable;
- oracle outages must have defined repay, exit and liquidation behavior;
- an admin-set price may be used only in a mock/test-only environment with an explicit banner and no mainnet-real-funds configuration.

See Chainlink guidance at https://docs.chain.link/data-feeds. Feed availability for an asset on Monad must be verified at integration time; it cannot be assumed from general documentation.

### 5.3 LP position valuation

A position adapter MUST validate manager, pool, position ID and account custody; calculate real underlying token quantities from canonical pool/position state; price underlying tokens using approved sources; include fees only if claimable and not double-counted; apply haircuts for slippage, liquidity depth, concentrated-range risk, protocol risk, volatility and unwind time; and implement an actual liquidation adapter. An unverified manager or missing exit route makes the position ineligible.

### 5.4 Chog NFT collection asset valuation

The identity NFT and portfolio collateral are separate line items. The product MAY let the original Chog NFT itself contribute collateral value only after all of the following exist:

1. verified official collection and token contract;
2. executable sale/auction recovery contract or reliable liquidator path;
3. defensible valuation source beyond an unverified floor price;
4. market-depth, trait/rarity manipulation and wash-trading analysis;
5. conservative haircut and per-collection/per-account caps;
6. stress tests for rapid floor drops, no bids, thin liquidity and forced sale;
7. explicit liquidation and residual ownership semantics.

Until these conditions are met, `eligibleValue(chogNft) = 0`. The associated portfolio may still have eligible asset collateral. Do not use marketplace floor value as an automatic credit limit.

### 5.5 Value normalization

All contracts use integer arithmetic. If token amount `A` has decimals `d` and `P` is USDC raw units per one whole token:

`valueUsdcRaw = floor(A × P / 10^d)`

Use full-precision `mulDiv`, down-round collateral and up-round debt. Verify token decimals at deployment. Test 6/8/18 decimal combinations. Do not use floating-point math on-chain.

## 6. Credit math, debt and pool accounting

### 6.1 Debt

`totalDebt = principal + accruedInterest + applicableUnpaidFees` according to the declared accounting policy. The UI displays components and total. Debt changes only through borrow, time accrual, repayment, liquidation, approved write-off/loss accounting or a valid debt-bearing account transfer that leaves the liability unchanged unless explicitly settled.

### 6.2 Borrowing capacity

For every collateral class `i`:

`eligibleValue_i = conservativeGrossValue_i × (1 − valuationHaircut_i)`

`weightedBorrowValue_i = eligibleValue_i × maxLTV_i`

`availableToBorrow = max(0, min(sum(weightedBorrowValue_i) − totalDebt, accountCapRoom, poolCapRoom, availablePoolLiquidity))`

The Chog NFT's own collectible-market value is included only when its separate collateral module is enabled. The underlying positions use their own collateral policies. Correlated tokens/positions require concentration haircuts; simply summing nominal marks is unsafe for multi-position portfolios.

### 6.3 Health factor

`liquidationAdjustedValue = sum(conservativeGrossValue_i × liquidationThreshold_i)`

`healthFactor = liquidationAdjustedValue / totalDebt`

For zero debt, UI should show “No debt.” Production arithmetic uses a fixed-point scale and conservative rounding. Health factor below `1.0` makes an account eligible for liquidation under its policy; warning thresholds should be higher and separately configured.

### 6.4 Interest model

The test prototype may use a simple fixed/linear model only if labelled as such. Production SHOULD use a deterministic utilization-based model with defined accrual timing and a debt index. If using a kinked model:

- `U = totalDebt / (availableCash + totalDebt)` after declared reserves/unavailable cash;
- below optimal utilization, borrow rate follows base rate + slope 1;
- above the kink, borrow rate rises under slope 2;
- supplier yield, protocol fees and reserves reconcile to actual interest received.

Exact values must be simulated and reviewed. Rounding, partial repayment, update cadence and bad debt must be specified.

### 6.5 Lender shares and solvency

Before external/public liquidity, pool accounting MUST reconcile:

- cash USDC controlled by pool;
- borrower debt principal and accrued interest;
- supplier shares/claims;
- protocol fees and reserves;
- pending withdrawals or queue claims;
- realized and unrecognized bad debt;
- available cash for new loans and withdrawals.

A supplier share token or ERC-4626-inspired interface can be considered after audit; it is not required for the narrow mock demo. A model that records nominal provider amounts but doesn't allocate yield/loss proportionately is not production-ready. Liquidity withdrawals must not promise cash that is lent out or uncollectible.

### 6.6 Borrow and repay receiver semantics

Default borrow destination SHOULD be the account vault so borrowed USDC remains inside the associated financial package and can be deployed via an approved adapter. If a borrower may instead send proceeds to an EOA, the transaction must encode the receiver explicitly, check it against policy and reflect that the cash has left the portfolio while debt remains. The UI must not report withdrawn proceeds as remaining collateral.

Repayment should account for actual token received, define whether payment applies to fees/interest/principal and reject overpayment or handle it explicitly. Full repayment does not automatically release escrow unless debt and all pending operations are rechecked atomically or by a release function with fresh reads.

## 7. Required contract interfaces

The exact names/ABI may change while maintaining semantics and tests.

### 7.1 Collection adapter and registry

```solidity
interface IChogCollection {
    function ownerOf(uint256 tokenId) external view returns (address);
    function getApproved(uint256 tokenId) external view returns (address);
    function isApprovedForAll(address owner, address operator) external view returns (bool);
    function safeTransferFrom(address from, address to, uint256 tokenId) external;
}

interface IChogAccountRegistry {
    function accountKey(address collection, uint256 tokenId) external view returns (bytes32);
    function accountOf(bytes32 key) external view returns (address vault);
    function beneficialOwner(bytes32 key) external view returns (address);
    function isEscrowed(bytes32 key) external view returns (bool);
    function accountNonce(bytes32 key) external view returns (uint256);
    function getOrCreateAccount(address collection, uint256 tokenId)
        external returns (bytes32 key, address vault);
}
```

Registry MUST verify collection allowlist, real current owner and unique token mapping. Read functions MUST never rely on off-chain metadata. `getOrCreateAccount` must be idempotent. Collection and token ID form the key; token ID alone is never sufficient.

### 7.2 AccountFactory and AccountVault

```solidity
interface IAccountFactory {
    function getOrCreateAccount(address collection, uint256 tokenId)
        external returns (bytes32 accountKey, address vault);
}

interface IAccountVault {
    function accountKey() external view returns (bytes32);
    function assetSummary() external view returns (/* normalized summary */);
    function stateNonce() external view returns (uint256);
    function depositToken(address token, uint256 amount) external;
    function withdrawToken(address token, uint256 amount, address receiver) external;
    function executeAdapter(bytes32 adapterId, bytes calldata params) external;
}
```

Vault verifies beneficial control, accepted assets, collateral locks, adapter allowance, deadline and post-action risk checks. The example types can be adjusted to use concrete structs. No arbitrary `target, calldata` interface in the user-controlled public surface.

### 7.3 ChogCreditEscrow

```solidity
interface IChogCreditEscrow {
    function lockChogForPortfolio(address collection, uint256 tokenId) external returns (bytes32 accountKey);
    function releaseAfterSettlement(bytes32 accountKey) external;
    function beneficialOwner(bytes32 accountKey) external view returns (address);
    function locked(bytes32 accountKey) external view returns (bool);
    function transferBeneficialOwner(bytes32 accountKey, address buyer, bytes calldata proof) external;
}
```

`lockChogForPortfolio` verifies actual current owner and approval, collection allowlist, account key uniqueness and pending state before moving the NFT. The final signature design for `transferBeneficialOwner` is specified in Section 7.7. A release function MUST require an empty portfolio, zero debt/fees, and no pending liquidation or adapter operation. No unrestricted admin release.

### 7.4 CollateralRegistry / ValuationRouter

```solidity
function isCollateralEnabled(bytes32 collateralId) external view returns (bool);
function getCollateralConfig(bytes32 collateralId) external view returns (CollateralConfig memory);
function valueOf(bytes32 accountKey, bytes32 collateralId) external view returns (ValueQuote memory);
```

`ValueQuote` should include raw value, normalized units, price timestamp/block, adapter version and validity. It should not return a value without source/freshness context. Admin updates must be bounded, role-controlled, evented and timelocked in production.

### 7.5 ChogCreditPool

```solidity
function supply(uint256 assets, address receiver) external returns (uint256 shares);
function withdraw(uint256 assets, address receiver, address owner) external returns (uint256 shares);
function redeem(uint256 shares, address receiver, address owner) external returns (uint256 assets);
function borrow(bytes32 accountKey, uint256 assets, address receiver) external;
function repay(bytes32 accountKey, uint256 assets, address payer) external returns (uint256 repaid);
function accountDebt(bytes32 accountKey) external view returns (DebtView memory);
function availableLiquidity() external view returns (uint256);
function maxBorrow(bytes32 accountKey) external view returns (uint256);
function healthFactor(bytes32 accountKey) external view returns (uint256);
function liquidate(bytes32 accountKey, uint256 maxRepay) external returns (uint256 repaid, uint256 seizedValue);
```

Borrow MUST verify escrowed/secured NFT state when debt is activated, current eligibility, liquidity and post-borrow health. The contract must not mint USDC. If pool accounting is simplified for testnet, functions and UI must identify it as a test facility.

### 7.6 Liquidation engine

Must implement fresh price checks, health calculation, per-collateral close factor, repayment cap, bounded bonus/seizure, tested unwind, residual collateral/debt accounting and events. If a position's unwind requires an adapter, that adapter must be allowlisted and checked. Bad-debt state must be explicit and not hidden by reverting interest updates.

### 7.7 Portfolio package transfer coordinator

The coordinator requires typed signatures binding at minimum for every portfolio-bearing transfer:

- `chainId`, coordinator address and account key;
- collection and token ID;
- current beneficial owner and buyer;
- account state nonce/hash;
- maximum debt buyer accepts when debt exists;
- minimum health factor or required post-transfer risk state when debt exists;
- price/settlement terms and recipient;
- expiry/deadline and replay-safe nonce.

A single transaction MUST verify consent, escrow status, current beneficial owner, account state, market settlement and (where debt exists) live debt and health; update beneficial owner; increment account nonce; emit events; and leave NFT in escrow while any portfolio state remains. A direct escrow release or external NFT transfer cannot bypass the coordinator. Failed conditions revert atomically. Product-market settlement must prevent payment going to an attacker-controlled destination.

## 8. Backend and read API

Backend is a read/index and convenience layer. It MUST NOT hold borrower signing keys or make backend-only decisions about collateral eligibility. All security-critical capacity/health decisions are enforced on-chain.

### 8.1 Requirements

- Chain ID and deployment manifest assertion.
- ABI/version/address alignment and bytecode verification status where available.
- Read model sourced from events and periodic state reconciliation.
- Event keys idempotent under replays; reorg handling with block hash/confirmations.
- Rate limits, schema validation, CORS allowlist, structured errors and secret-free logs.
- Every returned snapshot includes chain ID, block number/hash, observed time, freshness and deployment version.

### 8.2 Suggested endpoints

- `GET /health`: process health, configured chain ID, RPC chain ID and RPC status.
- `GET /api/config`: deployment manifest, Chog collection address, registry, escrow, vault factory, pool, token addresses and explicit verification status. Never return secrets.
- `GET /api/chogs?owner=0x...`: enumerate owned token IDs only if provider/indexer supports it; cross-check current `ownerOf` or transfer logs. A generic ERC-721 has no standard enumerable function, so do not assume `tokenOfOwnerByIndex` exists.
- `GET /api/chogs/:tokenId`: collection identity, verified owner/escrow mode, account key, vault and metadata URI with source labels.
- `GET /api/accounts/:accountKey`: portfolio balances/positions, collateral eligibility, valuation timestamp, debt, interest, health and available credit.
- `GET /api/pool`: pool cash, debt, cap usage, supplier accounting summary, current rate and withdrawal policy.
- `GET /api/accounts/:accountKey/activity`: normalized chain events with transaction hash, block and confirmation state.
- `GET /api/transactions/:hash`: transaction status and logs tied to expected contract addresses.
- `GET /api/collateral`: enabled collateral assets, risk parameters and valuation/liquidation adapter versions.

`accountKey`, collection addresses and token IDs must be validated. For exact token-ID lookup, address is part of the route/config; never accept a token ID without confirming the configured collection.

## 9. Frontend and wallet behavior

### 9.1 Screens

1. Chog selection and collection verification.
2. Chog account overview and linked vault.
3. Position/collateral list with accepted vs unsupported states.
4. Credit preview with pool liquidity, max borrow, interest, post-borrow health and escrow disclosure.
5. Borrow/repay and confirmed transaction detail.
6. Approved second market with explicit real-vs-simulated mode.
7. Activity/history with block timestamps and evidence links.
8. Escrow/transfer screen explaining who controls the NFT, whether it is currently escrowed, and what is required to release or transfer it.
9. Risk settings and protocol disclosures.

### 9.2 Transaction state machine

`idle -> preflight -> wallet_confirmation -> submitted -> included -> confirmed -> refreshed` with terminal `rejected`, `failed`, `reverted` and `timeout/recheck` states. The UI MUST not update debt or account ownership as final before confirmation and post-transaction state reads. A chain reorg must permit status correction.

### 9.3 Preflight

Before credit activation: assert chain, collection allowlist, token ownership, token approval, unique account, escrow receiver support, collateral support, non-stale price, pool liquidity, caps, no pause, expected account nonce, gas balance, destination and post-borrow health. Wallet simulation or preflight is advisory; contract checks remain authoritative.

### 9.4 Required labels

- Live Chog NFT vs test Chog-compatible NFT.
- Mock USDC vs official USDC.
- Demo/simulated second market vs actual on-chain adapter.
- Wallet-held vs escrow-held NFT.
- Account asset valuation vs NFT collectible-market valuation.
- Credit capacity vs available pool cash.

## 10. Events and indexing

At minimum emit:

- `AccountCreated(accountKey, collection, tokenId, vault, creator)`
- `AssetDeposited(accountKey, token, amount, actor)`
- `AssetWithdrawn(accountKey, token, amount, receiver, actor)`
- `ChogEscrowed(accountKey, collection, tokenId, beneficialOwner)`
- `ChogReleased(accountKey, collection, tokenId, beneficialOwner)`
- `BeneficialOwnerChanged(accountKey, oldOwner, newOwner, stateNonce)`
- `CreditActivated(accountKey, principal, debt, collateralValue)`
- `Borrowed(accountKey, amount, receiver, debtAfter)`
- `Repaid(accountKey, amountReceived, principalRepaid, interestRepaid, debtAfter)`
- `InterestAccrued(accountKey or index, interestAmount, debtIndex)`
- `CollateralConfigUpdated(collateralId, version, configHash)`
- `AdapterExecuted(accountKey, adapterId, inputAsset, inputAmount, outputAsset, outputAmount)`
- `Liquidated(accountKey, liquidator, repaid, seized, debtRemaining)`
- `TransferProposed/TransferCompleted/TransferCancelled` where later implemented
- `PauseChanged`, `RoleChanged`, `OracleConfigUpdated`, `PoolLiquidityChanged`.

Event payloads must avoid ambiguous units. The indexer must recover after downtime by replaying events and comparing current contract state. Each account event records actor and beneficial owner at time of action when the contract has that data.

## 11. State machines

### 11.1 Account lifecycle

`Unregistered -> WalletHeldEmptyAccount -> EscrowedPortfolio -> CreditActive (optional) -> SettledButPortfolioHeld -> PortfolioTransfer or EmptyAndReleased` .

Additional terminal/problem states: `Paused`, `LiquidationEligible`, `Liquidating`, `Closed/Empty`. `Paused` is a control flag, not an erasure of the underlying financial state.

### 11.2 Escrow lifecycle

- `NOT_ESCROWED`: NFT is held in a wallet; control derives from current verified collection `ownerOf`; account must be empty.
- `DEPOSIT_PENDING`: expected safe transfer initiated; no portfolio deposit/credit activation until custody and registry state confirm.
- `ESCROWED_PACKAGE`: NFT is held by escrow and beneficial owner recorded; assets/positions may be associated with the account.
- `CREDIT_ACTIVE`: escrowed account has debt; release and ordinary transfer disabled.
- `TRANSFER_PENDING`: coordinator validates buyer acceptance, account nonce/state, settlement and debt rules; release disabled.
- `ESCROWED_PACKAGE` with updated beneficial owner after atomic package transfer.
- `RELEASE_PENDING`: release call rechecks that the portfolio is empty and all obligations/pending operations are cleared.
- `NOT_ESCROWED`: NFT returned to beneficial owner; normal ERC-721 transfers resume.

### 11.3 Failure policy

If ownership, oracle or escrow state cannot be verified, risk-increasing operations fail closed. Repayment remains available where safe. Emergency pause must not give administrators authority to redirect the NFT or user assets.

## 12. Invariants and threat model

### Accounting invariants

1. Pool cash changes by actual USDC in/out only.
2. Borrowed amount increases account debt by the same amount before interest/fee policy.
3. Repayment cannot reduce debt by more than actual accepted funds plus explicitly accounted write-offs.
4. Lender cash/shares/debt/fees/reserves/bad debt reconcile under every modeled state transition.
5. Collateral recorded never exceeds what the vault can recover using accepted token behavior.
6. NFT collectible value contributes zero unless its own approved recovery adapter is enabled.

### Authorization invariants

7. Only verified current NFT owner can open an account/escrow before portfolio custody or credit.
8. While wallet-held, the account must be empty and control follows real `ownerOf`.
9. Any non-empty portfolio or active secured credit implies the original Chog NFT is in configured escrow, unless a separately approved collection-level mechanism demonstrably enforces equivalent package-transfer restrictions.
10. Escrow release requires an empty portfolio, zero secured debt/fees and no blocking pending operation.
11. Beneficial owner changes while escrowed occur only through valid release or transfer coordinator.
12. No arbitrary admin can redirect the NFT, vault assets or beneficial owner.

### Solvency invariants

13. Borrow cannot exceed eligible capacity, account cap, pool cap or available pool cash.
14. Withdrawal/adapter execution cannot break the configured post-action health policy.
15. Stale/invalid prices block risk-increasing actions.
16. Liquidation only occurs at the defined unhealthy condition, with seizure bounded by repayment plus permitted incentive.
17. Debt-bearing transfer preserves debt and lender rights unless debt is settled by the same atomic transaction.
18. Account transfer signatures are chain-, contract-, account-state- and nonce-bound and expire.
19. Test-only prices and mock tokens cannot be used as production financial evidence.

## 13. Test specification

### 13.1 Baseline build

Pin Solidity version, optimizer settings, EVM target, Foundry version, remappings and dependency commit hashes. CI must run `forge fmt --check`, `forge build`, `forge test`, static analysis, dependency/security checks and TypeScript type/build checks. Store logs and source commit as evidence.

### 13.2 Collection and registry unit tests

- Correct collection address accepted; fake collection rejected.
- Owner lookup, invalid token ID and non-owner attempts.
- Duplicate account creation prevented; `getOrCreate` idempotent.
- Same token ID across two collections yields different account keys.
- Same collection/token on two chains cannot collide.
- Collection address mismatch and chain-ID mismatch fail closed.
- Wallet-held empty-account control follows transfer of Chog NFT; account cannot hold assets while the NFT is wallet-held.
- Account state and history do not reset on NFT transfer.

### 13.3 Escrow unit and adversarial tests

- Successful deposit of approved real/mock Chog ERC-721.
- First portfolio deposit requires escrow.
- A non-empty account cannot release the Chog NFT.
- Package transfer moves account control and associated positions atomically.
- Safe-transfer callback from unapproved collection rejected.
- Unsolicited transfer cannot create a valid account.
- Escrow record and beneficial owner update atomically.
- Any assets/positions block release, even if debt is zero.
- Zero-asset release succeeds only if there is zero debt/fee and no pending liquidation or blocking operation.
- Admin cannot redirect or release a non-empty/indebted account NFT.
- Direct transfer attempts fail while escrow is actual token holder.
- Portfolio package transfer requires correct buyer/seller signed state, nonce and expiry.
- Debt-bearing transfer additionally requires explicit debt/health acceptance.
- Replay, wrong chain, wrong coordinator, changed debt, changed state nonce, expired signature, unhealthy account and invalid payment all revert.

### 13.4 Credit/pool unit tests

ERC-20 deposits and real received amount; borrow cap; no liquidity; interest accrual; partial/full repayment; repayment rounding; zero/huge values; stale oracle; price manipulation sanity checks; account/pool caps; fee/reserve treatment; lender shares; pool withdrawal with illiquid debt; liquidation math; bad debt; reentrancy; pausing; role escalation; decimal conversion.

### 13.5 Position adapter tests

- Correct manager/pool/position ownership and custody.
- Amounts derived from canonical position math.
- Fee calculation and no double counting.
- Unsupported manager/selector rejected.
- Exit path realizes expected token amounts under bounded slippage.
- Adapter failure rolls back accounting.
- External protocol state changes or upgrade disable new risk and do not break repayment.

### 13.6 Stateful invariant/fuzz tests

Generate sequences of NFT transfer, escrow, deposit, borrow, time passage, price movement, repay, withdraw, pause, liquidation and transfer proposal. Invariants include no debt bypass, no NFT release with obligations, no duplicate account, pool reconciliation, no under-collateralized borrow above configured rules, no permission escalation and no seizure above limits.

### 13.7 Live-collection and fork tests

Use a local fork of Monad mainnet where the tooling supports it to test the candidate Chog collection interface and actual transfer semantics. Tests must confirm the collection can be escrowed and later returned using correct approvals. Do not call a testnet mock test proof of live collection integration. If the exact NFT is only available on Monad mainnet, the public testnet cannot literally hold that same token; document the distinction.

### 13.8 Testnet end-to-end gates

- Deploy mock Chog-compatible NFT, mock USDC, account registry/factory, vault, escrow and capped credit pool.
- Verify deployed bytecode/addresses and chain ID.
- Create or select mock Chog; create account; deposit supported collateral; escrow Chog; borrow; inspect emitted events and API; repay; release NFT.
- Demonstrate that any non-empty portfolio blocks release and active debt blocks release even after collateral value changes.
- Verify UI status only from chain reads and confirmed receipts, not local optimistic state.
- Publish manifest, tx hashes, logs, test results and known limitations.

### 13.9 Mainnet go/no-go

No mainnet real-credit release until collection source confirmed, exact addresses/code verified, collateral recovery tested, lender accounting completed, oracle sources verified, fuzz/invariant suites pass, critical/high audit findings are remediated, multisig/timelock and incident controls are tested, legal/regulatory review complete, initial pool capital and risk caps approved, and the UI cannot display mock data as live.

## 14. Deployment and configuration

### 14.1 Deployment manifest

Example fields (fill from verified deployment output, never invent values):

```json
{
  "product": "Chog Credit",
  "environment": "monad-testnet",
  "chainId": 10143,
  "rpcUrl": "https://testnet-rpc.monad.xyz",
  "chogCollection": "",
  "collectionAuthoritySource": "",
  "collectionCodeHash": "",
  "accountRegistry": "",
  "accountFactory": "",
  "accountVaultImplementation": "",
  "chogCreditEscrow": "",
  "creditPool": "",
  "usdcToken": "",
  "collateralRegistry": "",
  "valuationRouter": "",
  "adapterRegistry": "",
  "commit": "",
  "buildEvidence": "not-run",
  "testEvidence": "not-run",
  "deployedAtBlock": null
}
```

Public client configuration may contain public addresses and RPC endpoints. Never include private keys or sensitive credentials. At startup, backend/frontend compare expected chain ID and critical addresses with the manifest. If values disagree, disable write actions and show a configuration error.

### 14.2 Testnet sequence

1. Build and test under pinned dependencies.
2. Deploy mock Chog ERC-721, mock USDC and test collateral.
3. Deploy config/registry, account factory/vault, escrow and pool in dependency order.
4. Configure mock collateral and price policy. An admin price may be used only for test mode.
5. Verify addresses, code, chain ID and ownership/roles.
6. Execute full test flow and capture tx hashes.
7. Connect backend/frontend with exact manifest.
8. Run independent end-to-end regression and verify all labels.

### 14.3 Production role separation

Use role-specific multisig and timelock, separate guardian pause, and no single EOA with direct asset transfer authority. Timelock risk increases and monitor collection/escrow/adapter changes. Admin cannot seize collateral or redirect Chog NFTs under emergency functions. Pause matrix must permit safe repay and define safe withdrawal/liquidation behavior.

## 15. Current source mismatches and implementation work

The current source package must not be represented as implementing this spec. Known mismatches:

1. It mints a separate `ChogPositionNFT`; revised product must use the existing configured Chog collection as canonical identity.
2. It lacks `ChogAccountRegistry` keyed by collection address + token ID.
3. It has no robust `ChogCreditEscrow` controlling the original Chog NFT while portfolio assets/positions or secured debt are attached.
4. It has no beneficial-owner semantics for an escrow-held token.
5. Its current collateral pricing is administrator-set and unsuitable for actual funds.
6. It tracks one ERC-20 collateral type, not a verified position NFT or multi-position portfolio.
7. Its interest and liquidity accounting are prototype-level, without production supplier share/loss model.
8. The backend is read-only and the UI is not wired to the contracts.
9. The second-market execution and debt-bearing marketplace are not implemented.
10. Foundry compile/tests and deployment have not been verified in the current environment.

Before deployment, either refactor the source to conform to Sections 3, 4 and 7 or explicitly label the existing source as an old isolated learning prototype. Do not deploy its separate Position NFT and claim it satisfies the Chog Credit product requirements.

## 16. Definition of technical completion

The target MVP is technically complete only when: the chosen real collection is verified; the account is keyed to the original NFT; no second Position NFT is required; account/vault and escrow semantics are enforced; active credit cannot be bypassed through NFT movement; a supported collateral is valued/recovered under tests; USDC borrowing and repayment succeed end to end; the UI/API reflect confirmed chain state; tests and deployment evidence are published; and all mock/live distinctions are clear. Independent audit and risk/economic review remain separate requirements before real funds.

