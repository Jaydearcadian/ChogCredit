// Mirrors the live MON price onto a TEST deployment's mock oracle (and its mock Uniswap pool), so testnet numbers look like mainnet.
//
//   KEEPER_KEY=0x... node scripts/price-keeper.mjs [--deployment public/deployments/monad-testnet.json] [--once | --dry]   (run from app/)
//
// KEEPER_KEY is the oracle's keeper (set at deploy with KEEPER=<address>) or its owner: a testnet-only key. The same pass runs hosted as
// api/price-keeper.mjs. Rules, in keeper-core.mjs: skip while prices are paused, skip a stale feed, write only when the price moved by
// MIN_MOVE_BPS (default 50) or MAX_AGE_S (default 1800) passed. Monad charges gas by limit, so fewer writes is cheaper. --dry writes nothing.
import { readFileSync } from 'node:fs';
import { keeperPass } from './keeper-core.mjs';

const arg = (n, d) => { const i = process.argv.indexOf(n); return i > 0 ? process.argv[i + 1] : d; };
const dep = JSON.parse(readFileSync(arg('--deployment', 'public/deployments/monad-testnet.json'), 'utf8'));
const DRY = process.argv.includes('--dry'), ONCE = DRY || process.argv.includes('--once');
const EVERY_S = Number(process.env.EVERY_S ?? 300), MAX_AGE_S = Number(process.env.MAX_AGE_S ?? 1800);
const key = process.env.KEEPER_KEY; if (!key) throw new Error('Set KEEPER_KEY to the keeper testnet key.');
const base = { dep, key, sourceRpc: process.env.SOURCE_RPC, targetRpc: process.env.TARGET_RPC, minMoveBps: BigInt(process.env.MIN_MOVE_BPS ?? 50), staleS: Number(process.env.FEED_STALE_S ?? 3600), gasPriceGwei: process.env.GAS_PRICE_GWEI, dry: DRY };

console.log(`keeper for ${dep.environment} (chain ${dep.chainId}), oracle ${dep.mockOracle}${ONCE ? '' : `, every ${EVERY_S}s`}`);
let lastWrite = Date.now() / 1000; // a fresh process writes only if the price moved
for (;;) {
  try {
    const r = await keeperPass({ ...base, forceWrite: !DRY && Date.now() / 1000 - lastWrite > MAX_AGE_S });
    if (r.action === 'set') lastWrite = Date.now() / 1000;
    console.log(`${r.action}: ${r.message}`);
  } catch (e) { console.log('error:', String(e.shortMessage ?? e.message).slice(0, 240)); }
  if (ONCE) break; await new Promise((r) => setTimeout(r, EVERY_S * 1000));
}
