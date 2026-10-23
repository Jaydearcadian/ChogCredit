# Gate E1: debt-bearing package sales

Scope: `AccountTransferCoordinator.executeDebtSale`, per `docs/DEBT_BEARING_SALES_SPEC.md`. Source only; not deployed anywhere.

## What was built

- `DebtAcceptance` (EIP-712, separate type hash; the debt-free `Acceptance` and `executeSale` are unchanged and still refuse debt).
- Buyer-signed bounds: pool address, maximum debt, minimum counted collateral value, minimum health, and an optional payoff (`debtRepay`) taken from the price and repaid to the pool atomically before the transfer.
- Checks, in order: seller, parties, deadline, signature (key then ERC-1271), vault nonce, ownership epoch, `HasDebt` (and nothing else), pool equals the bound credit module, no pending operation, price available, not liquidatable, payoff rules, then the signed bounds re-read after payoff.
- `cancelDebt` lets the buyer void an acceptance.
- `IDebtSalePool` is the read slice of the pool the coordinator uses. The pool itself did not change.

## Evidence (commit on this branch; run locally, GitHub CI has not run)

| Check | Result |
|---|---|
| New unit tests (`test/credit/DebtSale.t.sol`) | 24 pass, including a 1000-run fuzz that the sale succeeds exactly when every bound holds |
| Mock-pool tests (`test/core/DebtSaleMockPool.t.sol`) | 5 pass: pending operation, pool that pulls less than approved, state that breaks during repay |
| Mainnet-fork test | Real Chog 1 (plain EOA holder) and 2 (EIP-7702 holder), real USDC and WMON, payoff of 400 USDC, buyer then repays and releases the Chog |
| Mutation checks (`scratchpad/mut_debtsale.py`) | 21 of 21 gate mutants caught. First run left 5 survivors: 2 were missing assertions, 1 needed a mock pool, 2 were equivalent against the real pool and are now covered by the mock |
| Full suite (CI settings, invariants 128 x 200) | 224 passed, 0 failed, including fork tests |
| Size | Coordinator 11.3 KB runtime; factory initcode 44.5 KB, under the 49,152 byte limit with about 4.6 KB left |
| Slither | New `arbitrary-send-erc20` reports on buyer payments: same pattern as the existing sale, where `from` is the signature-verified buyer |

## Test-writing defects found on the way (not contract defects)

Three tests failed first for test reasons: a cheatcode consumed by a helper call inside the call's arguments (twice), and a deadline that expired after a 30-day warp. The epoch test also showed the epoch starts at 1 because the escrow deposit counts as a change.

## Limits

- The price field is not tied to equity on chain. The buyer's signature is the consent. The UI must show equity and the signed bounds in plain language.
- A buyer who signs loose bounds accepts the worse outcome.
- Legal review of assumed-debt transfers has not happened (R-30).
- Not independently audited.
