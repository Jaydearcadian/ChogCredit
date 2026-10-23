import { formatUnits, parseUnits } from 'viem';

/** Human amount with fixed decimals and thousands separators (display only). */
export function fmt(raw: bigint, decimals: number, places = 2): string {
  const s = Number(formatUnits(raw, decimals));
  return s.toLocaleString('en-US', { minimumFractionDigits: places, maximumFractionDigits: places });
}
export const fmtUsdc = (raw: bigint) => fmt(raw, 6, 2);
export const short = (a: string) => `${a.slice(0, 6)}…${a.slice(-4)}`;

export function parseAmount(text: string, decimals: number): bigint | null {
  const t = text.trim().replace(/,/g, '');
  if (!/^\d*\.?\d*$/.test(t) || t === '' || t === '.') return null;
  try { return parseUnits(t, decimals); } catch { return null; }
}

/** Health factor as shown to people: bps 15000 -> "1.50". Infinite (no debt) -> null. */
export function healthNumber(bps: bigint): string | null {
  if (bps >= 2n ** 200n) return null;
  return (Number(bps) / 10_000).toFixed(2);
}

/** Exact decimal string for an input box (no separators, no rounding). */
export function fmtPlain(raw: bigint, decimals: number): string {
  const s = raw.toString().padStart(decimals + 1, '0');
  const whole = s.slice(0, -decimals), frac = s.slice(-decimals).replace(/0+$/, '');
  return frac ? `${whole}.${frac}` : whole;
}
