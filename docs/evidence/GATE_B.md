# Gate B Evidence: account identity refactor

**Date:** 22 October 2026
**Source commit tested:** `69b6d6c1534c66842dfb92418e48586b56fa1020` (branch `claude/chog-credit-brand-27ooac`)
**Evidence states reached:** `LOCAL_BUILD_PASS` for the new core contracts. Fork tests are local simulations against Monad mainnet state. Nothing is deployed, nothing is audited.
**Toolchain:** as in `GATE_A.md` (Foundry 1.8.6, `network = "monad"`, solc 0.8.24, OpenZeppelin 5.1.0, fuzz runs 1,000).

## What Gate B was meant to deliver (from `IMPLEMENTATION_STATUS.md`)

| Gate B item | Result |
|---|---|
| Stop minting `ChogPositionNFT` as primary identity | Done. The old contracts moved to `contracts/src/legacy/` and `test/legacy/` and are labelled legacy. The new core never mints an NFT; `test_noSecondIdentityNftIsMinted` asserts it. The legacy code is still compiled so its 11 tests keep running, and `script/Deploy.s.sol` still deploys the legacy prototype. |
| Configurable collection allowlist and registry keyed by chain, collection, token ID | Done. `ChogAccountRegistry`, key = `keccak256(abi.encode(chainid, collection, tokenId))`. Allowlists are set in the constructor and have **no setter**. |
| One account vault per key | Done. Deterministic EIP-1167 clone per key; duplicates revert; address is predictable before creation. |
| Test ownership-derived control when wallet-held and debt-free | Done for wallet-held. "Debt-free" cannot be enforced yet because no debt module exists (Gate D). |

## New files

- `src/core/ChogAccountRegistry.sol`, `src/core/AccountVault.sol`, `src/core/interfaces/IChogAccountRegistry.sol`
- `src/mocks/MockChogGenesis.sol` (ids 1..1969, ERC-2981, role-based admin, not enumerable, like the live contract), `src/mocks/HostileMocks.sol` (lying/reverting collection, fee-on-transfer token, re-entrant token)
- `test/core/ChogAccountRegistry.t.sol` (16), `test/core/AccountVault.t.sol` (13), `test/core/CoreBase.sol`
- `test/fork/ChogGenesisFork.t.sol` extended to 4 tests

## Results

```
forge test                         -> legacy 11 passed; core 29 passed (registry 16, vault 13); 0 failed; fork 4 skipped without RPC
MONAD_MAINNET_RPC_URL=https://rpc.monad.xyz forge test --match-path "test/fork/*"
                                   -> 4 passed
forge fmt --check                  -> OK
```

Runtime sizes (bytes): `ChogAccountRegistry` 2,340 (it embeds the vault implementation in its initcode), `AccountVault` 2,748.

Behaviours covered: create for the real holder only; non-owner, non-existent token, unlisted collection, zero address and EOA-as-collection all revert; duplicate account reverts; the key changes with chain ID, collection and token; control follows the live `ownerOf` and fails closed if the collection reverts; accounts open for EIP-7702-delegated EOAs; constructor validation (empty, zero, duplicate); vault deposit/withdraw with nonce; non-controller blocked; unsupported token blocked; zero amount / zero recipient blocked; fee-on-transfer token rejected by balance delta; re-entry into the vault from a token callback is stopped by `ReentrancyGuardReentrantCall`; clone cannot be re-initialised, the implementation is locked, and only the registry can initialise a fresh clone; a fuzz test conserves tokens across deposit and withdraw.

On the mainnet fork, with the registry pointed at the **real** Chog Genesis contract: accounts open for the actual holders of tokens 1 (plain EOA) and 2 (7702-delegated EOA), `isController` is true for them and false for a stranger, and a stranger cannot open an account for token 3.

### Do the tests have teeth? (manual mutation check)

Five deliberate breakages were applied one at a time and the suite run each time. All five were caught and the files were restored byte for byte:

| Mutation | Caught by |
|---|---|
| remove `onlyController` from `withdrawERC20` | `test_nonControllerCannotDepositOrWithdraw`, `test_walletHeldControlFollowsNftSale_whyEscrowIsRequired` |
| remove the balance-delta check | `test_feeOnTransferTokenRejectedByBalanceDelta` |
| `isController` always true | `test_isController_followsLiveOwner` and two vault tests |
| remove the collection allowlist check | `test_unlistedCollectionRejected_evenIfItLooksLikeChog`, `test_zeroAndEoaCollectionRejected` |
| remove the `canAcceptAssets` gate | `test_depositRefusedWhenAssetsNotAccepted_defaultMode` |

This is a hand-run check of five mutants, not a mutation-testing tool run.

> **Superseded in part by Gate C (`GATE_C.md`):** the test-only `walletHeldDeposits` flag described below was removed, assets are now accepted only while the Chog is escrowed, and `ChogAccountRegistry`'s constructor takes two arguments.

## Known limits and trust assumptions (read before relying on this)

1. **Wallet-held control is unsafe once the vault holds anything.** Control follows `ownerOf`, so selling the NFT hands over the vault; `test_walletHeldControlFollowsNftSale_whyEscrowIsRequired` demonstrates it. For that reason the registry refuses deposits by default (`canAcceptAssets` is false). The constructor flag `walletHeldDeposits = true` exists only for tests and must never be set outside local runs. Gate C replaces it with NFT escrow.
2. **An allowlisted collection is trusted to answer `ownerOf` honestly.** A hostile or compromised allowlisted collection could grant control to anyone (`test_isController_failsClosedWhenCollectionReverts` shows a lying answer is accepted). The real Chog Genesis contract has an admin role whose powers are still unknown (no verified source).
3. **No solvency check on withdrawal.** No debt module exists, so `withdrawERC20` is limited only by control. Gate D adds it.
4. **No pause, no upgrade path, no events for allowlist changes** (there are no changes). If the allowlist is wrong the registry must be redeployed.
5. **Not covered yet:** invariant tests, ERC-721 tokens in the vault, native MON, a gas-limit review for Monad, a static-analysis run, an independent review.
6. `script/Deploy.s.sol` still deploys the legacy prototype, so there is no deployment script for the new core.
7. The GitHub Actions workflow has still not been executed.

## Next: Gate C (escrow)

`ChogCreditEscrow` with a beneficial-owner record, entry via `onERC721Received` from the allowlisted collection only, release blocked while the account holds assets or debt, `canAcceptAssets` true only when escrowed, and hostile-receiver / reentrancy / wrong-collection tests. After that, remove the `walletHeldDeposits` flag.
