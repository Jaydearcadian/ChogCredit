# Gate C hardening round: closing the Gate C limits

**Date:** 22 October 2026
**Status:** results of a hardening pass over `GATE_C.md`. Same evidence ceiling: `LOCAL_BUILD_PASS`, local-chain deployment, mainnet-fork simulations. Nothing is on testnet or mainnet, nothing is independently audited.
**Toolchain:** as in `GATE_A.md` (Foundry 1.8.6, `network = "monad"`, solc 0.8.24, OpenZeppelin 5.1.0).

## 1. What each Gate C limit became

| Gate C limit | Outcome | How |
|---|---|---|
| Live Chog admin powers unknown | **Mostly resolved by analysis, not by code.** See section 2. | Dispatch-table analysis of the live bytecode |
| Plain `transferFrom` strands a Chog | **Partly fixed, with a new trust assumption.** | Optional immutable `rescuer`, 3-day public delay, can never touch a recorded token (section 3) |
| No transfer of a funded Chog | **Fixed for debt-free sales.** Debt-bearing transfer still needs the credit pool. | `AccountTransferCoordinator`: buyer-signed, atomic, 7702-safe (section 3) |
| Credit-module trust (binder) | **Narrowed, not removed.** | Binder is now a constructor parameter, so a deployment contract can bind in the deployment transaction; the bind is probed and module reads cannot revert or be griefed (section 3). The atomic bind itself needs the pool (Gate D). |
| No deploy script / CI never ran / stale invariant run | **Fixed except CI, which cannot run here.** | `DeployCore`/`SmokeCore`, workflow rewritten and YAML-validated, invariant run redone (section 5) |
| No static analysis | **Done.** | Slither 0.11.6 on `src/core` (section 5) |
| Only ERC-20 custody | **Deliberately not changed.** Positions (ERC-721 LP receipts) need a position adapter and valuation (Tier 2). Native MON can be wrapped to WMON. | n/a |
| No solvency math | **Not changed.** That is Gate D by definition. | n/a |
| Independent review | **Cannot be produced here.** An automated code review was run (section 4); it is not an audit. | n/a |

## 2. The live Chog Genesis contract: what its admin can and cannot do

Method (all read-only against Monad mainnet, 2026-10-22): resolved the 123 four-byte selectors in the runtime code through a public signature database; separated real dispatched functions (`DUP1 PUSH4 sel EQ` pattern, 67 of them) from custom errors, constants and interface ids; checked the executable bytes for `DELEGATECALL`/`SELFDESTRUCT`; read roles and state with `cast`.

- **Dispatched functions (67):** ERC-721 + metadata, ERC-2981 (`royaltyInfo`), AccessControl (`grantRole`, `revokeRole`, `renounceRole`, `hasRole`, `ADMIN_ROLE`), mint-stage machinery (`mint`, `adminMint`, `openStage`, `setStageWindow`, `setStageConfig`, `setStageRoot`, `setSchedule`, `setPrice`, team allotments), metadata (`setBaseURI`, `setPlaceholderURI`, `reveal`, `setProvenanceHash`), money (`setTreasury`, `setRoyalty`, `withdraw`).
- **None of the 67 is a burn, pause, blocklist, operator filter, transfer validator or forced transfer.** There is no function by which any role can move or destroy a holder's token.
- **No executable `DELEGATECALL`, `CALLCODE` or `SELFDESTRUCT`:** the two `DELEGATECALL` hits are data bytes (the `ADMIN_ROLE` constant and the compiler metadata). It is not an EIP-1967 proxy. Compiled with solc 0.8.28.
- **State:** `revealed = true`, `currentStage = 255` (no stage open), `maxSupply = totalSupply = 1,969`, so `adminMint` has no headroom.
- **Roles:** `ADMIN_ROLE` (`0xa498…1775`) is held by `0x84113421a8a564b594ee9ae78c875310332d7023`, which is also the treasury and royalty receiver. That address is a **single EIP-7702-delegated EOA** (code `0xef0100…` delegating to `0x63c0c19a…`), i.e. one key, not a multisig. The holder of `DEFAULT_ADMIN_ROLE` could not be identified (the RPC rejects wide `eth_getLogs` ranges; it is not the treasury).
- **What this means for Chog Credit:** the admin can change token metadata and royalty settings and withdraw contract proceeds, but cannot take tokens out of the escrow or stop transfers into it. The trust assumption "the collection answers `ownerOf` honestly and lets transfers through" is therefore supported by the code surface, with the caveats below.
- **Caveats:** this is bytecode analysis, not a source review, and the contract is still not verified on Sourcify. Selector databases can be incomplete (one dispatched selector was unresolved and turned out to be `royaltyInfo`). A key compromise of the admin does not endanger escrowed tokens but would let an attacker alter metadata. Written confirmation and the verified source from the Chog team are still needed.

## 3. What was built

- **`ChogCreditEscrow` rescue (opt-in).** `rescuer` is an immutable constructor argument (address(0) disables it). It can `requestRescue` a token that the collection says the escrow holds but that has **no beneficial-owner record**, wait `RESCUE_DELAY` (3 days, public via event), then `executeRescue` to a chosen address. A recorded token fails `NotStranded`; a repeated request fails `RescueAlreadyPending`; a burned or missing token fails `NotStranded`. **This is a real privilege and it changes the earlier "no admin, no rescue" claim.** A stranded Chog's sender has no on-chain proof of ownership, so the rescuer must decide off-chain, and a compromised rescuer key can take future stranded tokens. It cannot be rotated: use a multisig/timelock contract, or leave it disabled and accept that mistakes are unrecoverable.
- **`AccountTransferCoordinator` (created by the escrow).** Seller calls `executeSale(acceptance, buyerSignature)`; the buyer's EIP-712 acceptance binds: account key, seller, buyer, payment token, price, the vault's `stateNonce`, the escrow ownership `epoch`, a deadline and a salt, under a domain containing the chain ID and the coordinator address. Checks: caller is the named seller and the beneficial owner; buyer is not zero, the seller, or a protocol contract; not expired; digest unused; signature valid (the buyer's **key** first, then ERC-1271, so 7702-delegated EOAs work); vault nonce and epoch unchanged; no debt, pending operation or module failure. Then it records the new beneficial owner and pulls payment from the buyer to the seller, rejecting fee-on-transfer shortfalls; any failure reverts everything. The Chog never leaves escrow and the vault contents are untouched. `cancel` lets the buyer void an acceptance.
- **Registry.** `bindCreditModule` is probed (the module must answer `debtOf` and `hasPendingOperation` with exactly one word, the second a valid bool) and module reads use a bounded static call that cannot revert the caller, cannot be return-bombed, and fails closed (`debtOf = max`, `ModuleUnavailable`). `binder` and `rescuer` are constructor parameters.
- **Escrow `epochOf(key)`** increments on every set, move and clear of the beneficial owner.
- **Vault.** `sweepUnaccounted` now bumps `stateNonce`.
- **Scripts.** `script/DeployCore.s.sol` (modes `local` and `testnet-mock`; mainnet 143 refused; wrong chain for mode refused; post-deploy wiring reads; manifest to `deployments/`), `script/SmokeCore.s.sol` (open, escrow, deposit, withdraw, release as real transactions; refuses a manifest whose addresses have no code and refuses non-mock deployments), legacy script moved to `script/legacy/`.

## 4. Automated code review and its dispositions

A review of `src/core` was run with the `code-review` skill at high effort (an automated reviewer, **not** independent, not an audit). It returned nine findings; all were examined:

| Finding | Disposition |
|---|---|
| Irreversible `bindCreditModule` accepts any address; a bad module would make every release, withdrawal and sale revert | **Valid, fixed** (probe + non-reverting reads). Regression tests with six bad-module behaviours. |
| `sweepUnaccounted` does not bump the nonce, so a seller can front-run a sale | **Valid, fixed.** |
| Stale acceptance revives after the account changes hands and returns | **Valid, fixed** (ownership `epoch`). Two regression tests isolate the epoch. |
| Rescuer contradicts the "no admin" claims; no rotation | **Valid on the claims, which are corrected here and in `GATE_C.md`.** Rotation deliberately not added; documented as a multisig requirement. |
| `requestRescue` can silently restart or retarget; burned token gives a raw revert; wasted call in `cancelRescue` | **Valid, fixed.** |
| Buyer could be a protocol contract | **Valid, fixed.** Buyers that are unrelated contracts unable to act as owner remain the buyer's own risk. |
| Ad hoc `IVaultNonce` | **Fixed** (imports `AccountVault`). |
| Duplicated lookups in `releaseBlocker` / `liabilityBlocker` | **Fixed** (internal helper). |
| No-op initialiser and event reordering | **Reverted.** |
| Initcode growth / constructor wiring | **Checked, no change:** registry initcode is 21,614 bytes against EIP-3860's 49,152 and Monad's 262,144-byte limit; the coordinator's constructor never calls the registry. |

## 5. Verification results

```
forge test                       -> 113 passed; 0 failed; 6 skipped (fork tests, no RPC)
                                    112 unit/fuzz/regression tests + the 7-invariant campaign
MONAD_MAINNET_RPC_URL=https://rpc.monad.xyz forge test --match-path "test/fork/*"
                                 -> 6 passed
forge fmt --check                -> OK
FOUNDRY_INVARIANT_RUNS=256 FOUNDRY_INVARIANT_DEPTH=500 forge test --match-contract EscrowInvariantTest
                                 -> 7 invariants passed (85 s); about 12.8k calls per handler action,
                                    about 128k calls in total, 0 reverts surfaced
```

- **Seven stateful invariants** (3 actors, 3 Chogs, signed sales, rescue attempts, plain-`transferFrom` mistakes, donations): funded accounts keep their Chog in escrow; escrow records match real custody; accounted never exceeds balance; accounted equals deposits minus withdrawals; the beneficial owner always controls; one vault per key at the predicted address. A scripted non-vacuity test proves the handler's sale and rescue paths really execute.
- **Live fork (simulation):** open, escrow, blocked transfers, release; and a package sale of a real Chog **funded and paid in the real Circle USDC contract**, after which the buyer withdraws the funds and takes the Chog.
- **Local chain with real transactions:** `DeployCore` then `SmokeCore` on Anvil (`--network monad`): 7 transactions, 0 failed receipts, final state read back with `cast`. This is a local chain with mock assets, not Monad.
- **Testnet dry run (no broadcast):** `DeployCore` simulated against the live testnet: about 7.94M gas, estimated 1.6 MON at the quoted fee (registry deployment 5.47M gas, well under the 30M per-transaction cap). The manifest that run wrote was deleted because it does not describe a real deployment.
- **Gas (Foundry test numbers under the Monad profile, not live receipts):** `createAccount` up to 221k, `depositERC20` up to 236k, `withdrawERC20` up to 152k, `release` up to about 207k, `executeSale` up to 282k, `requestRescue` up to 99k, `executeRescue` up to 147k. Monad charges the gas **limit**, so wallets and scripts should set limits close to measured use plus headroom; re-measure on testnet receipts.
- **Slither 0.11.6 on `src/core`:** no high or medium findings of substance. Every reported item is intentional: arbitrary `from` in `safeTransferFrom` is the signed buyer payment; `readyAt == 0` is a sentinel; the ignored `tryRecover` third value is unused; zero-checks on `binder_` and `rescuer_` are absent on purpose (zero means disabled); timestamp comparisons are the sale deadline and address-zero checks; the reentrancy-events note is the event after the vault clone's `initialize`.

### Manual mutation checks

| Round | Mutants | Result |
|---|---|---|
| Gate C (escrow, registry, vault) | 11 | all caught (recorded in `GATE_C.md`) |
| Coordinator and rescue | 12 | all caught |
| Review fixes | 11 | 10 caught; 1 survived as an **equivalent mutant** (the explicit `code.length == 0` check in `bindCreditModule` duplicated the probe's rejection), so the redundant line was removed |

Hand-run, not a mutation-testing tool.

## 6. Corrections to earlier statements

- `GATE_C.md` named `--invariant-runs 256`; **that flag does not exist** in Foundry 1.8.6 (the earlier "long run" had in fact failed immediately). The working form is `FOUNDRY_INVARIANT_RUNS` / `FOUNDRY_INVARIANT_DEPTH` environment variables. The only completed long run before this round was an earlier 256-run, depth-500 campaign (about 325 s) that predated several changes.
- While debugging the deploy script I first blamed `msg.sender`; the real cause was a mistyped Anvil dev key. `readCallers()` was kept because it is more robust with keystores and hardware wallets, and its comment was corrected.
- A first dust-grief mutant used the wrong token address and was caught for the wrong reason; it was redone against the mock's real address.
- Several test failures during this round were test bugs: calls evaluated in `vm.prank`/`vm.expectRevert` argument lists consumed the cheatcodes, and Solidity memory structs alias on assignment, which made one "tampered variant" test weaker than intended until `_clone` was introduced.

## 7. Remaining limits

1. **Plain `transferFrom` into the escrow still strands a Chog until a rescuer acts**, and a rescuer is a trusted party. Without one, it is unrecoverable.
2. **The credit module and its binder are still trusted** until Gate D can bind the pool in the deployment transaction. Until then: no real funds.
3. **Collection trust:** the allowlisted collection must answer `ownerOf` honestly. The code-surface analysis in section 2 supports this for the live contract but is not a source review, and the admin is a single key.
4. **Debt-bearing transfer is not implemented.** A funded Chog with debt cannot be sold at all (sales revert on any liability); the owner must repay first.
5. **ERC-20 custody only.**
6. **No solvency math** (Gate D).
7. **CI has never executed on GitHub**; the workflow is YAML-valid and each step was run locally, but the `foundry-toolchain` version pin was not confirmed against the action.
8. **No independent review or audit**, and the invariant campaigns are bounded random testing, not proofs.
9. **No testnet deployment yet.** A funded testnet key is needed to broadcast; the dry run says about 1.6 MON.
