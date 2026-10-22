# Architecture Note: Revised Chog Credit Target

**Status:** target design; not implemented in the existing source slice.

## Identity

The account identity is `(chainId, officialChogCollectionAddress, tokenId)`. Chog Credit does not mint a separate Position NFT. The registry maps this identity to a vault/account record. Chog Genesis at `0xc96d31f8626c6d03fae5dcd3d61e3fb9f4a73763` is the current candidate, pending official verification.

## Custody and control

- While the NFT stays in a wallet and secured credit is inactive, control follows the collection's real `ownerOf(tokenId)`.
- Before the first portfolio asset/position is deposited, or before secured credit becomes active, the original Chog NFT must be deposited into Chog Credit escrow unless a separately verified collection-level integration can enforce equivalent transfer rules.
- While portfolio assets/positions or secured operations remain, the NFT stays in escrow. The registry records a beneficial owner. Ordinary direct transfer/release is unavailable.
- The NFT may be released only when the portfolio is empty and obligations/pending operations are cleared. A package transfer requires a coordinator with buyer acceptance and atomic checks; if debt exists, the buyer must explicitly accept debt and health constraints.

## Financial state

The account vault holds only supported assets/positions. The credit pool lends funded USDC. Eligible collateral value comes from the conservative recoverable value of approved assets/positions. The Chog NFT's own resale value is zero in the credit calculation until a distinct valuation and liquidation module is approved and tested.

## Existing code warning

The existing `ChogPositionNFT.sol` is an earlier prototype that conflicts with the target identity design. It must be refactored before the package can be described as implementing this architecture.
