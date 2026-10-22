# Revision Notes: Chog Credit v0.2

## Why the prior specification changed

Version 0.1 centered a separately minted `ChogPositionNFT` and treated the existing Chog collectible as a separate optional identity. That conflicted with the Chogathon product premise: the existing Chog NFT is the recognizable product asset and should be the account's canonical identity.

## Material changes

1. **Product identity:** product name is now **Chog Credit**. No second Position NFT is required by the target design.
2. **Account key:** the account is keyed by `(chainId, collectionAddress, tokenId)` and maps to a dedicated vault.
3. **Collection verification:** Chog Genesis on Monad is recorded as a candidate collection, not a deployment-approved hard-coded address. Official-source verification is a gate.
4. **Portfolio custody:** assets and supported positions live in a vault associated with the original Chog NFT; the NFT metadata does not itself custody them.
5. **Escrow scope:** the original NFT must be escrowed before the account accepts portfolio assets/positions or active secured credit. Escrow is not limited to the period when debt is positive. That prevents an ordinary NFT sale from silently transferring control of a non-empty portfolio.
6. **Package transfer:** debt-free portfolio transfers require a buyer-accepted, protocol-controlled package transfer. Debt-bearing transfers additionally require signed acceptance of debt, health constraints and terms.
7. **NFT collectible value:** the Chog NFT may be included as an independent collateral component only with an executable recovery/auction path and conservative market valuation. Marketplace floor alone is insufficient; without that module, its numeric collateral contribution remains zero.
8. **USDC semantics:** the facility borrows funded USDC; it does not mint Circle-issued USDC.
9. **Implementation status:** the current source still uses `ChogPositionNFT` and does not implement the revised registry/escrow model. That mismatch is now explicit and is a refactor blocker.

## Collection address research lead

Public OpenSea records identify Chog Genesis items on Monad as ERC-721 tokens under `0xc96d31f8626c6d03fae5dcd3d61e3fb9f4a73763`: https://opensea.io/item/monad/0xc96d31f8626c6d03fae5dcd3d61e3fb9f4a73763/532

This marketplace observation is not final official confirmation. The team must verify the exact collection against an official Chog-controlled source or explicit project confirmation before code integration/deployment.

## Important deployment consequence

A testnet mock collection can validate the account, escrow and credit plumbing, but it cannot prove integration with the existing live Chog NFT if that token exists only on Monad mainnet. Use a local fork for live-collection transfer tests where practical, and clearly distinguish that evidence from testnet deployment evidence.
