# Chog Credit: Chog NFT financial utility prototype

**Important:** this archive contains an earlier isolated prototype plus the revised product specifications. The current Solidity/UI source is **not yet aligned** to the Chog Credit design. It mints a separate `ChogPositionNFT`; the target architecture uses the existing Chog NFT as the canonical identity, adds a registry keyed by collection + token ID, and escrows the original NFT while secured credit is active.

## Product docs

- `docs/WHITEPAPER.md` - Chog Credit whitepaper and product thesis.
- `docs/PRD.md` - product requirements and acceptance criteria.
- `docs/TECHNICAL_SPECIFICATION.md` - detailed contract, escrow, accounting, API, UI, testing and deployment requirements.
- `docs/SECURITY_AND_RISK.md` - threat model and release blockers.
- `docs/IMPLEMENTATION_STATUS.md` - as-built/source status and the refactor path.
- `docs/README.md` - documentation index.

## Existing source slice (historical prototype)

- `index.html` is a demo-mode UI and is not wired to contracts.
- `contracts/` contains a separate account NFT and a simple one-token credit experiment.
- `backend/` contains a read-only Express/viem API for those earlier contracts.
- The source has not been compile/test-verified in this environment and has not been deployed or audited.

Do not treat the previous source as the revised Chog Credit implementation. The next engineering work is to refactor the account identity to the existing Chog NFT, implement the registry + escrow state machine, and then build/test the credit loop.

## Monad environments

- Testnet chain ID: `10143`, RPC `https://testnet-rpc.monad.xyz`.
- Mainnet chain ID: `143`, RPC `https://rpc.monad.xyz`.

Before any live integration, verify the official Chog collection address and behavior. Chog Genesis contract `0xc96d31f8626c6d03fae5dcd3d61e3fb9f4a73763` is a public marketplace research lead, not an approved hard-coded address. A testnet mock collection is useful for plumbing tests but is not proof of integration with the live collection.

## Hard rules

- Do not use real funds with the current prototype.
- Do not represent mock tokens or simulated market actions as live USDC or live positions.
- Do not claim Chog NFT floor price is collateral value without an approved and executable liquidation policy.
- Do not claim debt-bearing transfers are supported until the NFT escrow/coordinator path is implemented and tested.
