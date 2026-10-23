/**
 * The five states people see. Thresholds below are APP SAMPLE VALUES: the real Watch and At-risk lines are a product
 * decision (docs/brand/DESIGN.md "Open items"). Liquidatable is the contract's line (health < 1.0).
 */
export type Status = 'safe' | 'watch' | 'risk' | 'danger' | 'paused' | 'nodebt';

export const WATCH_BELOW_BPS = 15_000n;
export const RISK_BELOW_BPS = 12_500n;
export const LIQUIDATABLE_BELOW_BPS = 10_000n;

export function statusOf(d: { priceOk: boolean; debt: bigint; healthFactorBps: bigint }): Status {
  if (d.debt === 0n) return 'nodebt'; // a debt-free account has no health to show (docs/ux/OPEN_QUESTIONS_DECIDED.md)
  if (!d.priceOk) return 'paused';
  if (d.healthFactorBps < LIQUIDATABLE_BELOW_BPS) return 'danger';
  if (d.healthFactorBps < RISK_BELOW_BPS) return 'risk';
  if (d.healthFactorBps < WATCH_BELOW_BPS) return 'watch';
  return 'safe';
}

export const STATUS_WORD: Record<Exclude<Status, 'nodebt'>, string> = {
  safe: 'Safe', watch: 'Watch', risk: 'At risk', danger: 'Liquidatable', paused: 'Prices paused',
};
