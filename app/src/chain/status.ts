/**
 * The states people see. Health is liquidation value over debt. WMON borrows at 40% and liquidates at 65%, so a full
 * borrow starts at 1.625. Watch (below 1.50) is a price fall of about 8% from a full borrow, At risk (below 1.25) about
 * 23%, and Liquidatable (below 1.00, the contract's own line) about 38%. Decided in docs/SECURITY_AND_RISK.md.
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
