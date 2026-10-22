# Chog Credit Documentation

This documentation set describes the revised Chogathon product: financial utility built around the **existing Chog NFT**, not a newly minted Position NFT.

## Documents

- [`WHITEPAPER.md`](WHITEPAPER.md): product thesis, portfolio account, collateral and credit model, escrow/transfer architecture, differentiation and roadmap.
- [`PRD.md`](PRD.md): product requirements, user journeys, release scope, acceptance criteria and launch gates.
- [`TECHNICAL_SPECIFICATION.md`](TECHNICAL_SPECIFICATION.md): canonical NFT identity, registry/vault, escrow, credit pool, valuation, contract interfaces, API, UI, events, state machines, testing and deployment.
- [`SECURITY_AND_RISK.md`](SECURITY_AND_RISK.md): collection authenticity, NFT escrow, debt-bearing transfer, valuation, solvency, admin and mainnet risks.
- [`IMPLEMENTATION_STATUS.md`](IMPLEMENTATION_STATUS.md): explicit mismatch between the earlier code source and the revised target architecture, and the evidence required to close it.
- [`MONAD_REFERENCE.md`](MONAD_REFERENCE.md): verified Monad network facts, Chog contract reads, token/infra/DEX/oracle addresses, pool depth, tooling notes and open items. Machine-readable copy in `../config/monad-reference.json`; re-verify with `../scripts/verify_monad_reference.py`.
- [`BUILD_PLAN.md`](BUILD_PLAN.md): what the research changed, scope tiers, workstreams W0 to W9 with tests, a relative day plan against the Chogathon criteria, and decisions needed.
- [`evidence/GATE_A.md`](evidence/GATE_A.md): exact toolchain, commands and results for the Foundry baseline.
- [`evidence/GATE_B.md`](evidence/GATE_B.md): account registry and vault results, mutation check, and the limits to know before relying on them.
- [`evidence/GATE_C.md`](evidence/GATE_C.md): NFT escrow, beneficial-owner control and release rules; invariants, mutation check and the trust assumptions to review.
- [`evidence/GATE_C2.md`](evidence/GATE_C2.md): hardening round: what became of each Gate C limit, the live Chog admin analysis, package sale, rescue, review findings, deployment and static-analysis results.
- [`evidence/GATE_D.md`](evidence/GATE_D.md): credit pool, two-source oracle, liquidation and bad debt; defects found and fixed; real-feed fork tests; limits.
- [`REVISION_NOTES.md`](REVISION_NOTES.md): summary of the architecture corrections in v0.2.
- [`architecture.md`](architecture.md): previous source-slice architecture, retained for historical context only.

## Source of truth

The `WHITEPAPER.md`, `PRD.md` and `TECHNICAL_SPECIFICATION.md` now define the target architecture. The current prototype code still creates a separate `ChogPositionNFT` and has no original-Chog-NFT escrow. It is not aligned with this specification and should not be represented as the revised Chog Credit build.

## Collection verification

Chog Genesis on Monad is the current candidate collection. Public marketplace references show contract `0xc96d31f8626c6d03fae5dcd3d61e3fb9f4a73763`, but deployment is blocked until the exact collection is confirmed from an official Chog source and on-chain behavior is verified. The address must remain configuration rather than an unreviewed hard-coded assumption.

## Critical architecture decision

Because an external ERC-721 collection may permit transfers without consulting Chog Credit, the proposed design escrows the original Chog NFT as soon as its account holds portfolio assets/positions, and whenever secured credit is active. Beneficial ownership is recorded separately. The NFT can be released only after the account is empty and settled, or transferred as a package through an audited, protocol-controlled coordinator. A debt-bearing package transfer additionally requires explicit buyer acceptance of debt and risk. That escrow trade-off must be disclosed in the product and accepted before mainnet deployment.

## Evidence policy

These docs are a target design, not proof of working code. Build, tests, live collection reads, deployment, independent review and mainnet readiness each need their own verifiable evidence. See `IMPLEMENTATION_STATUS.md`.
