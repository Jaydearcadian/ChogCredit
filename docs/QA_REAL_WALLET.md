# Real wallet pass (10 minutes)

Everything so far was tested with a scripted wallet and a dev wallet. A real wallet behaves differently (network prompts, gas estimation, signing screens). Run this once on a desktop browser wallet and once on a phone.

**Setup.** Add Monad testnet (chain ID 10143, RPC https://testnet-rpc.monad.xyz) and get test MON from the Monad faucet. Keep at least 0.5 MON: Monad charges for the gas limit, so each transaction costs more than its usage, and position transactions cost the most.

| # | Do this | Expect |
| --- | --- | --- |
| 1 | Open https://chog-credit.vercel.app, tap "Look around first" | Chogs, Lend, Receive and Risk load with no wallet |
| 2 | Connect with your wallet | Prompt to switch network, address shown in the header |
| 3 | Get a test Chog, open its vault | Two wallet prompts at most, then "Vault opened." |
| 4 | Add assets, Get test tokens, add WMON | Approve then deposit, "Final on Monad." |
| 5 | Borrow 50 USDC | Chip says Safe, numbers match the form |
| 6 | Reject one prompt on purpose | "You rejected it in the wallet. Nothing changed." and no stuck spinner |
| 7 | Receive: copy the link, open it in a private window | Pay page with QR and the vault address |
| 8 | Sell: set a price, paste a second wallet, send the link | Second wallet signs, first wallet completes |
| 9 | Pool position: get a test position, add it, borrow, try to withdraw | Position locked while it backs the loan |
| 10 | Repay all, release the Chog | Chog returns to your wallet |

**Phone only.** Open the app in the wallet's built-in browser (MetaMask or Coinbase Wallet). Phone wallets that connect by QR code need `VITE_WALLETCONNECT_PROJECT_ID` set in Vercel; without it the app offers the in-wallet browser instead.

Log anything odd with the screen name and what you tapped. Known limits: public RPC rate limits (a refresh fixes it), mock assets, mock oracle.
