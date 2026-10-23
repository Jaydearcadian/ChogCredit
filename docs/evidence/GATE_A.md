# Gate A Evidence: Foundry builds the existing prototype

**Date:** 22 October 2026
**Source commit tested:** `6bc452a31475741bda68aeb49b3b1dacf9ec1013` (branch `claude/chog-credit-brand-27ooac`)
**Evidence states reached:** `LOCAL_BUILD_PASS` for the **old prototype** (`ChogPositionNFT` design). Fork tests are a local simulation against Monad mainnet state, not on-chain transactions. No testnet deployment, no audit.

> This proves the baseline compiles and its tests pass. It does **not** show that Chog Credit v0.2 exists. The v0.2 registry, escrow and vault are still unbuilt (Gate B and C).

## Toolchain

| Item | Value |
|---|---|
| Foundry | `forge 1.8.6` (commit `6bad0a66de7c83f7b33695044138f0f5fa4c5990`), linux amd64 release tarball sha256 `58850106984038f3a7200f38a4182c8cb423d3a4f4c7848eacbc2453e6bc35fc` |
| Execution profile | `network = "monad"` in `contracts/foundry.toml` |
| Solidity | `0.8.24`, optimizer on, 200 runs, `via_ir` off |
| OpenZeppelin | v5.1.0, submodule commit `69c8def5f222ff96f2b5beff05dfba996368aa79` |
| forge-std | v1.9.7, submodule commit `77041d2ce690e692d6e03cc812b57d1ddaa4d505` |

### Installing Foundry in this sandbox (what worked)

- `foundryup` and the GitHub API are blocked (HTTP 403), and the `stable` release tag is **1.5.1**, which predates Monad support. The npm package `@foundry-rs/forge` is at 1.7.1, also too old.
- Release assets download fine. The newest tag found by probing was `v1.8.6`:
  `curl -L -o f.tgz https://github.com/foundry-rs/foundry/releases/download/v1.8.6/foundry_v1.8.6_linux_amd64.tar.gz`, extract `forge cast anvil chisel` into `~/.foundry/bin`. Tags `v1.8.7` and above, and `v1.9.x`, returned 404 at the time.
- Monad docs require Foundry 1.8 or later. They also describe a `MonadTen` hardfork default; I did not confirm which Foundry release first included `MonadTen`, so treat the local Monad execution profile as "1.8.6 with `network = monad`", not as a verified match for live mainnet behaviour.
- Submodules clone fine through git (`git ls-remote` works); GitHub tarball archive URLs return 403.

## Commands and results (fresh clone of the pushed branch, commit `ad912d1`, then re-run at `6bc452a`)

```
git clone --recurse-submodules --branch claude/chog-credit-brand-27ooac https://github.com/Jaydearcadian/ChogCredit
cd ChogCredit/contracts
forge --version        -> forge Version: 1.8.6
forge fmt --check      -> OK
forge build --sizes    -> Compiler run successful (Solc 0.8.24)
forge test             -> Ran 11 tests ... 11 passed; 0 failed; 0 skipped
```

Contract sizes (runtime bytes, limit is 128 KB on Monad): `ChogCredit` 6,534, `ChogPositionNFT` 4,885, `MockCollateral` 1,910, `MockUSDC` 1,902.

Unit tests (11): LTV limit, borrow limit error, **pool-cash exhaustion**, healthy account not liquidatable, linear interest, liquidation after price drop, NFT blocked while in debt, repay unlocks transfer, non-owner cannot borrow, zero amounts revert, overpay capped at debt.

Fork tests (3, skipped unless `MONAD_MAINNET_RPC_URL` is set): `MONAD_MAINNET_RPC_URL=https://rpc.monad.xyz forge test --match-path "test/fork/*"`

- Collection identity on chain 143: `Chog Genesis`, `CHOG`, supply 1,969, ERC-721.
- A real Chog (token 1, plain EOA holder) approved and `safeTransferFrom`-ed into a contract receiver and back out.
- The same for token 2 (EIP-7702-delegated EOA holder, code prefix `0xef0100`).
- Read at fork block 115,699,178.

## Changes made to reach this state

- Added pinned submodules (`.gitmodules`), set `network = "monad"`, replaced the Makefile `forge install --no-commit` (flag removed in current Foundry) with `git submodule update --init --recursive`, ran `forge fmt`, added `.github/workflows/contracts.yml` (not yet run on GitHub).
- Fixed the known test gap: the old `testBorrowingRequiresLiquidity` hit the LTV check first. It now uses an account with `$6,000` of capacity against `$5,000` of pool cash and expects `InsufficientLiquidity(100e6, 50e6)`. The old assertion lives on as `testBorrowAboveLtvRevertsWithBorrowLimitError`.

## Findings that affect later gates

1. **Chog holders include EIP-7702-delegated EOAs.** Two of seven sampled holders had code `0xef0100…`. Escrow, registry and UI must not use `extcodesize`/`msg.sender.code.length` to tell "wallet" from "contract". Monad also keeps a 10 MON reserve on delegated EOAs (Monad docs).
2. **Escrow by approve + `safeTransferFrom` works on the live contract in a fork simulation**, for both holder types. Still to prove: transfer through an operator/marketplace flow, behaviour of the admin role, and a real on-chain transaction (Gate C).
3. The prototype contracts still do not meet the v0.2 design; the compiler warnings (`divide-before-multiply`, `block-timestamp`) in `ChogCredit.sol` are lint notes on code that will be replaced.

## Not done

- `INTEGRATION_PASS`, `TESTNET_DEPLOY_PASS`, `AUDIT_REVIEWED`: not claimed.
- GitHub Actions workflow has not executed yet.
- Fuzz and invariant tests: none exist yet.
