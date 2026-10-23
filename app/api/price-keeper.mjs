// Hosted price keeper for the TEST deployment: one pass of scripts/keeper-core.mjs. Called by a daily Vercel cron and, at most every ten
// minutes per browser, by the app itself while it is open (so prices are fresh whenever someone is looking, with no always-on server).
// Safe to expose: it only writes when the live price moved by MIN_MOVE_BPS or more, so repeat calls cost nothing. The key (KEEPER_KEY) is
// the oracle's keeper: a testnet-only key that can set prices and nothing else. It never runs against mainnet.
import { readFileSync } from 'node:fs';
import { keeperPass } from '../scripts/keeper-core.mjs';

const dep = JSON.parse(readFileSync(new URL('../public/deployments/monad-testnet.json', import.meta.url), 'utf8'));

export default async function handler(req, res) {
  res.setHeader('Cache-Control', 'no-store');
  const key = process.env.KEEPER_KEY;
  if (!key) return res.status(200).json({ action: 'off', message: 'no keeper key configured' });
  try {
    const r = await keeperPass({ dep, key, minMoveBps: BigInt(process.env.MIN_MOVE_BPS ?? 50), gasPriceGwei: process.env.GAS_PRICE_GWEI ?? '100' });
    return res.status(200).json({ action: r.action, message: r.message });
  } catch (e) {
    return res.status(200).json({ action: 'error', message: String(e.shortMessage ?? e.message).slice(0, 200) });
  }
}
