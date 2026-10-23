// The price keeper's one pass, shared by the command line (scripts/price-keeper.mjs) and the hosted function (api/price-keeper.mjs).
// Source: Chainlink MON/USD on Monad mainnet. Target: a TEST deployment's mock oracle and mock Uniswap pool.
import { createPublicClient, createWalletClient, defineChain, http, parseAbi } from 'viem';
import { privateKeyToAccount } from 'viem/accounts';

export const FEED = '0xBcD78f76005B7515837af6b50c7C52BCf73822fb'; // Chainlink MON / USD on Monad (docs/evidence/FEED_ANALYSIS.md)
const feedAbi = parseAbi(['function decimals() view returns (uint8)', 'function latestRoundData() view returns (uint80,int256,uint256,uint256,uint80)']);
const oracleAbi = parseAbi(['function owner() view returns (address)', 'function keeper() view returns (address)', 'function down() view returns (bool)', 'function pricePerWholeToken(address) view returns (uint256)', 'function setPrice(address,uint256)']);
const poolAbi = parseAbi(['function token0() view returns (address)', 'function token1() view returns (address)', 'function setSqrtPrice(uint160)']);
const erc20 = parseAbi(['function decimals() view returns (uint8)']);

const isqrt = (n) => { if (n < 2n) return n; let x = n, y = (x + 1n) / 2n; while (y < x) { x = y; y = (x + n / x) / 2n; } return x; };
/** sqrtPriceX96 for equal-value amounts of two tokens, given each token's price in loan-token raw units per whole token (as the deploy script does). */
export function sqrtPriceFor(p0, d0, p1, d1) { // ratio = token1 raw per token0 raw = (p0 / 10^d0) / (p1 / 10^d1)
  const num = p0 * 10n ** BigInt(d1), den = p1 * 10n ** BigInt(d0);
  return isqrt((num << 192n) / den);
}

/**
 * One pass. Returns { action: 'set' | 'hold' | 'skip' | 'dry', message, priceRaw? }; throws on setup errors.
 * opts: { dep, key, sourceRpc, targetRpc, minMoveBps = 50n, staleS = 3600, gasPriceGwei, dry, forceWrite }
 */
export async function keeperPass(opts) {
  const { dep, key, sourceRpc = 'https://rpc.monad.xyz', minMoveBps = 50n, staleS = 3600, gasPriceGwei, dry = false, forceWrite = false } = opts;
  if (dep.chainId === 143) throw new Error('Refusing to run against mainnet.');
  const targetRpc = opts.targetRpc ?? (dep.chainId === 10143 ? 'https://testnet-rpc.monad.xyz' : 'http://127.0.0.1:8545');
  const account = privateKeyToAccount(key);
  const chain = defineChain({ id: dep.chainId, name: 'target', nativeCurrency: { name: 'MON', symbol: 'MON', decimals: 18 }, rpcUrls: { default: { http: [targetRpc] } } });
  const src = createPublicClient({ transport: http(sourceRpc) }), pub = createPublicClient({ chain, transport: http() }), wal = createWalletClient({ chain, account, transport: http() });
  const gasOpts = gasPriceGwei ? { gasPrice: BigInt(gasPriceGwei) * 10n ** 9n } : {};

  const [dec, round] = await Promise.all([src.readContract({ address: FEED, abi: feedAbi, functionName: 'decimals' }), src.readContract({ address: FEED, abi: feedAbi, functionName: 'latestRoundData' })]);
  const answer = round[1], age = Math.floor(Date.now() / 1000) - Number(round[3]);
  if (answer <= 0n) return { action: 'skip', message: 'feed answer is not positive' };
  if (age > staleS) return { action: 'skip', message: `feed is ${age}s old` };
  const priceRaw = (answer * 10n ** 6n) / 10n ** BigInt(dec); // USDC raw (6 decimals) per 1 WMON
  if (priceRaw === 0n) return { action: 'skip', message: 'price rounds to zero' };
  if (await pub.readContract({ address: dep.mockOracle, abi: oracleAbi, functionName: 'down' })) return { action: 'skip', message: 'prices are paused (a Pause Drill is on)' };

  const [owner, keeper] = await Promise.all([pub.readContract({ address: dep.mockOracle, abi: oracleAbi, functionName: 'owner' }), pub.readContract({ address: dep.mockOracle, abi: oracleAbi, functionName: 'keeper' }).catch(() => '0x')]);
  if (![owner, keeper].some((a) => a.toLowerCase() === account.address.toLowerCase())) throw new Error(`The key is ${account.address} but the oracle's owner is ${owner} and its keeper is ${keeper}.`);

  const cur = await pub.readContract({ address: dep.mockOracle, abi: oracleAbi, functionName: 'pricePerWholeToken', args: [dep.mockWmon] });
  const moved = cur === 0n ? 10_000n : ((priceRaw > cur ? priceRaw - cur : cur - priceRaw) * 10_000n) / cur;
  const usd = (v) => `$${Number(v) / 1e6}`;
  if (moved < minMoveBps && !forceWrite) return { action: 'hold', priceRaw, message: `${usd(priceRaw)} (moved ${moved} bps)` };
  if (dry) return { action: 'dry', priceRaw, message: `would set WMON to ${usd(priceRaw)} (now ${usd(cur)}, moved ${moved} bps)` };

  await pub.waitForTransactionReceipt({ hash: await wal.writeContract({ address: dep.mockOracle, abi: oracleAbi, functionName: 'setPrice', args: [dep.mockWmon, priceRaw], ...gasOpts }) });
  let poolNote = '';
  if (dep.lpEnabled && dep.mockUniswapPool) { // keep the mock pool at the oracle's own price, or positions stop being priceable (deviation guard)
    const [t0, t1] = await Promise.all([pub.readContract({ address: dep.mockUniswapPool, abi: poolAbi, functionName: 'token0' }), pub.readContract({ address: dep.mockUniswapPool, abi: poolAbi, functionName: 'token1' })]);
    const [d0, d1] = await Promise.all([pub.readContract({ address: t0, abi: erc20, functionName: 'decimals' }), pub.readContract({ address: t1, abi: erc20, functionName: 'decimals' })]);
    const price = (t) => (t.toLowerCase() === dep.mockUsdc.toLowerCase() ? 1_000_000n : priceRaw);
    await pub.waitForTransactionReceipt({ hash: await wal.writeContract({ address: dep.mockUniswapPool, abi: poolAbi, functionName: 'setSqrtPrice', args: [sqrtPriceFor(price(t0), d0, price(t1), d1)], ...gasOpts }) });
    poolNote = ' + mock pool';
  }
  return { action: 'set', priceRaw, message: `set WMON to ${usd(priceRaw)}${poolNote} (was ${usd(cur)}, feed ${age}s old)` };
}
