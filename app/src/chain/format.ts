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

/** "3 hours", "2 days", "25 minutes": the biggest sensible unit, rounded up so a wait is never understated. */
export function span(sec: number): string {
  const n = (v: number, u: string) => `${v} ${u}${v === 1 ? '' : 's'}`;
  if (sec >= 172_800) return n(Math.ceil(sec / 86_400), 'day');
  if (sec >= 3_600) return n(Math.ceil(sec / 3_600), 'hour');
  return n(Math.max(1, Math.ceil(sec / 60)), 'minute');
}

/** "23 Oct 2026" in the viewer's locale. */
export const shortDate = (sec: number) => new Date(sec * 1000).toLocaleDateString(undefined, { day: 'numeric', month: 'short', year: 'numeric' });
