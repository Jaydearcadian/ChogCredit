import "dotenv/config";
import express from "express";
import cors from "cors";
import { createPublicClient, defineChain, getAddress, http, type Address } from "viem";
import { creditAbi, positionNftAbi } from "./abi.js";

const chainId = Number(process.env.MONAD_CHAIN_ID ?? 10143);
const rpcUrl = process.env.MONAD_RPC_URL ?? "https://testnet-rpc.monad.xyz";
const app = express();
app.disable("x-powered-by");
app.use(cors({ origin: true }));
app.use(express.json({ limit: "32kb" }));

const monad = defineChain({
  id: chainId,
  name: chainId === 143 ? "Monad Mainnet" : "Monad Testnet",
  nativeCurrency: { name: "MON", symbol: "MON", decimals: 18 },
  rpcUrls: { default: { http: [rpcUrl] } },
});
const client = createPublicClient({ chain: monad, transport: http(rpcUrl) });

function envAddress(key: string): Address {
  const value = process.env[key];
  if (!value || !/^0x[0-9a-fA-F]{40}$/.test(value)) throw new Error(`${key} is not configured with a valid address`);
  return getAddress(value);
}
function accountIdParam(value: string): bigint | null {
  if (!/^[1-9][0-9]{0,77}$/.test(value)) return null;
  try { return BigInt(value); } catch { return null; }
}
function asString(value: bigint | number): string { return value.toString(); }

app.get("/health", async (_req, res) => {
  try {
    const currentChain = await client.getChainId();
    const block = await client.getBlockNumber();
    res.json({ ok: currentChain === chainId, configuredChainId: chainId, rpcChainId: currentChain, latestBlock: block.toString(), timestamp: new Date().toISOString() });
  } catch (error) {
    res.status(503).json({ ok: false, error: error instanceof Error ? error.message : "RPC unavailable" });
  }
});

app.get("/api/config", (_req, res) => {
  res.json({
    app: "Chog Credit API",
    chainId,
    chainName: monad.name,
    rpcUrl,
    explorer: chainId === 143 ? "https://monadvision.com" : "https://testnet.monadvision.com",
    creditAddress: process.env.CHOG_CREDIT_ADDRESS ?? null,
    positionNftAddress: process.env.CHOG_POSITION_NFT_ADDRESS ?? null,
    transactionSigning: "client-wallet-only",
    backendStoresPrivateKeys: false,
    safetyStatus: "TESTNET MVP. Admin-managed collateral pricing. Not audited.",
  });
});

app.get("/api/pool", async (_req, res) => {
  try {
    const address = envAddress("CHOG_CREDIT_ADDRESS");
    const [availableLiquidity, totalOutstandingPrincipal, maxLtvBps, liquidationThresholdBps, annualInterestRateBps] = await Promise.all([
      client.readContract({ address, abi: creditAbi, functionName: "availableLiquidity" }),
      client.readContract({ address, abi: creditAbi, functionName: "totalOutstandingPrincipal" }),
      client.readContract({ address, abi: creditAbi, functionName: "maxLtvBps" }),
      client.readContract({ address, abi: creditAbi, functionName: "liquidationThresholdBps" }),
      client.readContract({ address, abi: creditAbi, functionName: "annualInterestRateBps" }),
    ]);
    res.json({
      chainId,
      availableLiquidityUsdcRaw: asString(availableLiquidity),
      trackedPrincipalAndCapitalizedInterestUsdcRaw: asString(totalOutstandingPrincipal),
      maxLtvBps: asString(maxLtvBps),
      liquidationThresholdBps: asString(liquidationThresholdBps),
      annualInterestRateBps: asString(annualInterestRateBps),
      liquidityWithdrawalRule: "paused while any principal is outstanding",
      note: "Amounts are raw token units. USDC normally uses 6 decimals. Aggregate debt reflects interest capitalized by account interactions; per-account debtOf includes currently accrued interest. Testnet only.",
    });
  } catch (error) {
    res.status(503).json({ error: error instanceof Error ? error.message : "Could not read pool state" });
  }
});

app.get("/api/accounts/:tokenId", async (req, res) => {
  const id = accountIdParam(req.params.tokenId);
  if (id === null) return res.status(400).json({ error: "tokenId must be a positive integer" });
  try {
    const creditAddress = envAddress("CHOG_CREDIT_ADDRESS");
    const nftAddress = envAddress("CHOG_POSITION_NFT_ADDRESS");
    const [owner, collateralAmount, debt, collateralValueUsdc, maxBorrowUsdc, availableBorrowUsdc, healthFactorBps] = await Promise.all([
      client.readContract({ address: nftAddress, abi: positionNftAbi, functionName: "ownerOf", args: [id] }),
      client.readContract({ address: creditAddress, abi: creditAbi, functionName: "collateralOf", args: [id] }),
      client.readContract({ address: creditAddress, abi: creditAbi, functionName: "debtOf", args: [id] }),
      client.readContract({ address: creditAddress, abi: creditAbi, functionName: "collateralValueUsdc", args: [id] }),
      client.readContract({ address: creditAddress, abi: creditAbi, functionName: "maxBorrowUsdc", args: [id] }),
      client.readContract({ address: creditAddress, abi: creditAbi, functionName: "availableBorrowUsdc", args: [id] }),
      client.readContract({ address: creditAddress, abi: creditAbi, functionName: "healthFactorBps", args: [id] }),
    ]);
    const currentBlock = await client.getBlockNumber();
    res.json({
      accountId: id.toString(), owner, chainId, blockNumber: currentBlock.toString(),
      collateralAmountRaw: asString(collateralAmount), collateralValueUsdcRaw: asString(collateralValueUsdc),
      debtUsdcRaw: asString(debt), maxDebtUsdcRaw: asString(maxBorrowUsdc),
      availableBorrowUsdcRaw: asString(availableBorrowUsdc), healthFactorBps: asString(healthFactorBps),
      withdrawalsLocked: debt > 0n, nftTransferLocked: debt > 0n,
      note: "Raw token units only. Collateral value uses the owner-configured testnet price, not an oracle.",
    });
  } catch (error) {
    const message = error instanceof Error ? error.message : "Could not read account";
    const notFound = /revert|ownerOf|nonexistent|invalid token/i.test(message);
    res.status(notFound ? 404 : 503).json({ error: notFound ? "Account NFT does not exist" : message });
  }
});

app.use((error: unknown, _req: express.Request, res: express.Response, _next: express.NextFunction) => {
  res.status(500).json({ error: error instanceof Error ? error.message : "Internal server error" });
});

const port = Number(process.env.PORT ?? 8787);
app.listen(port, "0.0.0.0", () => console.log(`Chog Credit read-only API listening on :${port}; chainId=${chainId}`));
