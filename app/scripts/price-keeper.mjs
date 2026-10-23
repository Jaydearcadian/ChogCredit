// Mirrors the live MON price onto a TEST deployment's mock oracle (and its mock Uniswap pool), so testnet numbers look like mainnet.
//
//   KEEPER_KEY=0x... node scripts/price-keeper.mjs [--deployment public/deployments/monad-testnet.json] [--once]   (run from app/)
//
// Source: Chainlink MON/USD on Monad mainnet (docs/evidence/FEED_ANALYSIS.md). Target: the deployment's mock oracle, which only its
// owner (the deployer) can write, so KEEPER_KEY must be the deployer's TESTNET key. Never a key that holds real funds.
// Rules: skip while prices are paused (a Pause Drill is on), skip a feed that is stale or non-positive, and only write when the price
// moved by at least MIN_MOVE_BPS or MAX_AGE_S has passed. Monad charges gas by limit, so fewer writes is cheaper.
import { readFileSync } from 'node:fs';
import { createPublicClient, createWalletClient, defineChain, http, parseAbi } from 'viem';
import { privateKeyToAccount } from 'viem/accounts';

const arg = (n, d) => { const i = process.argv.indexOf(n); return i > 0 ? process.argv[i + 1] : d; };
const dep = JSON.parse(readFileSync(arg('--deployment', 'public/deployments/monad-testnet.json'), 'utf8'));
const ONCE = process.argv.includes('--once');
const SOURCE_RPC = process.env.SOURCE_RPC ?? 'https://rpc.monad.xyz';
const TARGET_RPC = process.env.TARGET_RPC ?? (dep.chainId === 10143 ? 'https://testnet-rpc.monad.xyz' : 'http://127.0.0.1:8545');
const FEED = '0xBcD78f76005B7515837af6b50c7C52BCf73822fb'; // Chainlink MON / USD on Monad
const MIN_MOVE_BPS = BigInt(process.env.MIN_MOVE_BPS ?? 50), MAX_AGE_S = Number(process.env.MAX_AGE_S ?? 1800), EVERY_S = Number(process.env.EVERY_S ?? 300);
const STALE_S = Number(process.env.FEED_STALE_S ?? 3600);

if (dep.chainId === 143) throw new Error('Refusing to run against mainnet.');
const key = process.env.KEEPER_KEY; if (!key) throw new Error('Set KEEPER_KEY to the deployer testnet key.');
const account = privateKeyToAccount(key);
const chain = defineChain({ id: dep.chainId, name: 'target', nativeCurrency: { name: 'MON', symbol: 'MON', decimals: 18 }, rpcUrls: { default: { http: [TARGET_RPC] } } });
const src = createPublicClient({ transport: http(SOURCE_RPC) });
const pub = createPublicClient({ chain, transport: http() }); const wal = createWalletClient({ chain, account, transport: http() });
const gasPrice = process.env.GAS_PRICE_GWEI ? BigInt(process.env.GAS_PRICE_GWEI) * 10n ** 9n : undefined;

const feedAbi = parseAbi(['function decimals() view returns (uint8)', 'function latestRoundData() view returns (uint80,int256,uint256,uint256,uint80)']);
const oracleAbi = parseAbi(['function owner() view returns (address)', 'function down() view returns (bool)', 'function pricePerWholeToken(address) view returns (uint256)', 'function setPrice(address,uint256)']);
const poolAbi = parseAbi(['function token0() view returns (address)', 'function token1() view returns (address)', 'function setSqrtPrice(uint160)', 'function slot0() view returns (uint160,int24,uint16,uint16,uint16,uint8,bool)']);
const erc20 = parseAbi(['function decimals() view returns (uint8)']);

const isqrt = (n) => { if (n < 2n) return n; let x = n, y = (x + 1n) / 2n; while (y < x) { x = y; y = (x + n / x) / 2n; } return x; };
/** sqrtPriceX96 for equal-value amounts of two tokens, given each token's price in loan-token raw units per whole token (as the deploy script does). */
function sqrtPriceFor(p0, d0, p1, d1) { // ratio = token1 raw per token0 raw = (p0 / 10^d0) / (p1 / 10^d1)
  const num = p0 * 10n ** BigInt(d1), den = p1 * 10n ** BigInt(d0);
  return isqrt((num << 192n) / den);
}

let last = { price: 0n, at: Date.now() / 1000 }; // a fresh process writes only if the price moved
async function tick() {
  const [dec, round] = await Promise.all([src.readContract({ address: FEED, abi: feedAbi, functionName: 'decimals' }), src.readContract({ address: FEED, abi: feedAbi, functionName: 'latestRoundData' })]);
  const answer = round[1], updatedAt = Number(round[3]); const age = Math.floor(Date.now() / 1000) - updatedAt;
  if (answer <= 0n) return console.log('skip: feed answer is not positive');
  if (age > STALE_S) return console.log(`skip: feed is ${age}s old`);
  const priceRaw = (answer * 10n ** 6n) / 10n ** BigInt(dec); // USDC raw (6 decimals) per 1 WMON
  if (priceRaw === 0n) return console.log('skip: price rounds to zero');
  if (await pub.readContract({ address: dep.mockOracle, abi: oracleAbi, functionName: 'down' })) return console.log('skip: prices are paused (a Pause Drill is on)');
  const cur = await pub.readContract({ address: dep.mockOracle, abi: oracleAbi, functionName: 'pricePerWholeToken', args: [dep.mockWmon] });
  const moved = cur === 0n ? 10_000n : ((priceRaw > cur ? priceRaw - cur : cur - priceRaw) * 10_000n) / cur;
  const old = Date.now() / 1000 - last.at > MAX_AGE_S;
  if (moved < MIN_MOVE_BPS && !old) return console.log(`hold: $${Number(priceRaw) / 1e6} (moved ${moved} bps)`);
  const opts = gasPrice ? { gasPrice } : {};
  const h1 = await wal.writeContract({ address: dep.mockOracle, abi: oracleAbi, functionName: 'setPrice', args: [dep.mockWmon, priceRaw], ...opts });
  await pub.waitForTransactionReceipt({ hash: h1 });
  let poolNote = '';
  if (dep.lpEnabled && dep.mockUniswapPool) { // keep the mock pool at the oracle's own price, or positions stop being priceable (deviation guard)
    const [t0, t1] = await Promise.all([pub.readContract({ address: dep.mockUniswapPool, abi: poolAbi, functionName: 'token0' }), pub.readContract({ address: dep.mockUniswapPool, abi: poolAbi, functionName: 'token1' })]);
    const price = async (t) => (t.toLowerCase() === dep.mockUsdc.toLowerCase() ? 1_000_000n : priceRaw);
    const [d0, d1] = await Promise.all([pub.readContract({ address: t0, abi: erc20, functionName: 'decimals' }), pub.readContract({ address: t1, abi: erc20, functionName: 'decimals' })]);
    const h2 = await wal.writeContract({ address: dep.mockUniswapPool, abi: poolAbi, functionName: 'setSqrtPrice', args: [sqrtPriceFor(await price(t0), d0, await price(t1), d1)], ...opts });
    await pub.waitForTransactionReceipt({ hash: h2 }); poolNote = ' + mock pool';
  }
  last = { price: priceRaw, at: Date.now() / 1000 };
  console.log(`set WMON to $${Number(priceRaw) / 1e6}${poolNote} (was $${Number(cur) / 1e6}, feed ${age}s old)`);
}

const owner = await pub.readContract({ address: dep.mockOracle, abi: oracleAbi, functionName: 'owner' });
if (owner.toLowerCase() !== account.address.toLowerCase()) throw new Error(`KEEPER_KEY is ${account.address} but the oracle owner is ${owner}.`);
console.log(`keeper for ${dep.environment} (chain ${dep.chainId}), oracle ${dep.mockOracle}, every ${EVERY_S}s`);
for (;;) {
  try { await tick(); } catch (e) { console.log('error:', String(e.shortMessage ?? e.message).slice(0, 200)); }
  if (ONCE) break; await new Promise((r) => setTimeout(r, EVERY_S * 1000));
}
