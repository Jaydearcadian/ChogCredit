import type { ReactNode } from 'react';
import { STATUS_WORD, type Status } from '../chain/status';

/** A. The Slip: the brand logo. Drawn on the 100-unit grid from brand board 6. Never inside the app's top bar. */
export function Slip({ size = 48, ink = '#836EF9', perf = '#0E0B1A', bars = true, label = 'Chog Credit' }: { size?: number; ink?: string; perf?: string; bars?: boolean; label?: string }) {
  return (
    <svg viewBox="0 0 100 100" width={size} height={size} role="img" aria-label={label}>
      <path d="M16 26 H84 a8 8 0 0 1 8 8 V43 a7 7 0 0 0 0 14 V66 a8 8 0 0 1 -8 8 H16 a8 8 0 0 1 -8 -8 V57 a7 7 0 0 0 0 -14 V34 a8 8 0 0 1 8 -8 Z" fill={ink} />
      <rect x="19" y="41" width="18" height="18" rx="4" fill="#E845A4" />
      {bars && size > 32 && <><rect x="43" y="42" width="12" height="4.5" rx="2.2" fill="#FAF9FC" /><rect x="43" y="53.5" width="8" height="4.5" rx="2.2" fill="#FAF9FC" /></>}
      {size > 16 && <line x1="66" y1="31" x2="66" y2="69" stroke={perf} strokeWidth="2.4" strokeDasharray="3 4" strokeLinecap="round" />}
    </svg>
  );
}

/** D. The Full Stop: the top-bar wordmark. "Chog Credit" with one pink square full stop. */
export function Wordmark({ size = 22 }: { size?: number }) {
  return (
    <span style={{ fontFamily: 'var(--font-display)', fontWeight: 800, fontSize: size, display: 'inline-flex', alignItems: 'flex-end', lineHeight: 1 }}>
      Chog Credit<span aria-hidden="true" style={{ width: size * 0.32, height: size * 0.32, background: 'var(--pink-500)', marginLeft: 3, marginBottom: size * 0.04 }} />
    </span>
  );
}

/** The Chog bubble: one handwritten line that repeats what the chip says. Never advice, never a label. */
export function Bubble({ children }: { children: ReactNode }) {
  return (
    <div className="bubble" style={{ background: '#faf9fc', color: '#141026', borderRadius: '18px 18px 18px 4px', padding: '8px 12px', fontFamily: 'var(--font-hand)', fontWeight: 700, fontSize: 20, lineHeight: 1.1 }}>
      {children}
    </div>
  );
}

export type Prop = 'coin' | 'star' | 'lock' | 'key' | null;
export function Sticker({ prop }: { prop: Prop }) {
  if (!prop) return null;
  const common = { width: 36, height: 36, viewBox: '0 0 36 36', 'aria-hidden': true, style: { position: 'absolute' as const, right: -10, top: -12 } };
  if (prop === 'coin') return <svg {...common}><circle cx="18" cy="18" r="14" fill="#FCBB00" stroke="#0E0B1A" strokeWidth="2" /><path d="M18 11v14M14 14.5h6.5a2.5 2.5 0 010 5H14" fill="none" stroke="#0E0B1A" strokeWidth="2.2" strokeLinecap="round" /></svg>;
  if (prop === 'star') return <svg {...common}><path d="M18 3l3.2 9.8L31 14l-7.5 6.2L26 30l-8-5.6L10 30l2.5-9.8L5 14l9.8-1.2z" fill="#E845A4" stroke="#0E0B1A" strokeWidth="2" strokeLinejoin="round" /></svg>;
  if (prop === 'lock') return <svg {...common}><rect x="7" y="15" width="22" height="16" rx="4" fill="#E845A4" stroke="#0E0B1A" strokeWidth="2" /><path d="M12 15v-4a6 6 0 0112 0v4" fill="none" stroke="#0E0B1A" strokeWidth="2.4" strokeLinecap="round" /><circle cx="18" cy="23" r="2.2" fill="#0E0B1A" /></svg>;
  // B. The Pixel Key: a prop, never a logo or icon (12 by 6 grid, 2 by 2 pink gem)
  return <svg {...common} viewBox="0 0 96 48" width={54} height={27} style={{ position: 'absolute', right: -12, top: -14 }}><g fill="#FCBB00" stroke="#0E0B1A" strokeWidth="1.5"><rect x="0" y="16" width="32" height="16" /><rect x="32" y="20" width="48" height="8" /><rect x="64" y="28" width="8" height="12" /><rect x="80" y="28" width="8" height="8" /></g><rect x="8" y="20" width="16" height="8" fill="#E845A4" /></svg>;
}

const PROP: Record<string, Prop> = { nodebt: 'key', safe: 'coin', watch: 'star', risk: 'lock', danger: 'lock', paused: null };
const BUBBLE: Record<string, string> = {
  nodebt: "Hm, what's in here?", safe: "Hm, what's in here?", watch: 'Keep an eye on me.', risk: "I'd add some collateral.",
  danger: 'Repay or add assets now.', paused: 'Prices are napping. Repay still works.',
};

/** 270 degree ring. The ring never changes colour: the chip beside it does. One pink dot marks the end of the progress. */
export function HealthRing({ fill, label, paused = false }: { fill: number | null; label: string; paused?: boolean }) {
  const C = 2 * Math.PI * 52, arc = C * 0.75;
  const f = fill === null ? 0 : Math.max(0.02, Math.min(1, fill));
  return (
    <svg width="116" height="116" viewBox="0 0 120 120" role="img" aria-label={`Health ${label}`} style={{ flex: 'none' }}>
      <circle cx="60" cy="60" r="52" fill="none" stroke="var(--ink-700)" strokeWidth="10" strokeLinecap="round" strokeDasharray={paused ? '6 10' : `${arc} ${C - arc}`} transform="rotate(135 60 60)" />
      {fill !== null && <circle cx="60" cy="60" r="52" fill="none" stroke="var(--purple-500)" strokeWidth="10" strokeLinecap="round" strokeDasharray={`${arc * f} ${C}`} transform="rotate(135 60 60)" style={{ transition: 'stroke-dasharray var(--t-base) var(--ease)' }} />}
      {fill !== null && <g className="dot-g" style={{ transform: `rotate(${270 * f}deg)` }}><circle cx="23.2" cy="96.8" r="7" fill="var(--pink-500)" stroke="var(--ink-900)" strokeWidth="3" /></g>}
      <text x="60" y="64" textAnchor="middle" fontFamily="var(--font-num)" fontWeight="600" fontSize={label.length > 5 ? 17 : 24} fill="var(--text)">{label}</text>
      <text x="60" y="82" textAnchor="middle" fontFamily="var(--font-body)" fontSize="11" fill="var(--text-muted)">Health</text>
    </svg>
  );
}

export type CardData = { id: number; status: Status; ringFill: number | null; ringLabel: string; assets: string; owed: string; borrow: string; chip: ReactNode; art: ReactNode };

/** The Account Card: the seam between the two registers. Chog on top (playful), the tear-off numbers underneath (exact). */
export function AccountCard({ s, children }: { s: CardData; children?: ReactNode }) {
  const paused = s.status === 'paused';
  const row = (k: string, v: string) => (
    <div className="row small" style={{ color: 'var(--text-muted)' }}><span>{k}</span><span className="num" style={{ color: 'var(--text)' }}>{paused ? '--' : v}</span></div>
  );
  return (
    <section aria-label={`Account for Chog ${s.id}`} className="rise" style={{ background: 'var(--ink-900)', border: `1px ${paused ? 'dashed' : 'solid'} var(--ink-700)`, borderRadius: 'var(--r-account)', padding: 14, display: 'flex', flexDirection: 'column', gap: 14 }}>
      <div style={{ position: 'relative' }}>{s.art}<Sticker prop={PROP[s.status]} /></div>
      <div>{s.chip}</div>
      <div className="row" style={{ gap: 14, justifyContent: 'flex-start', alignItems: 'center' }}>
        <HealthRing fill={s.ringFill} label={s.ringLabel} paused={paused} />
        <Bubble key={s.status}>{BUBBLE[s.status]}</Bubble>
      </div>
      <div style={{ display: 'flex', flexDirection: 'column', gap: 8, borderTop: '2px dashed var(--ink-700)', paddingTop: 12, position: 'relative' }}>
        <span aria-hidden="true" style={{ position: 'absolute', left: -27, top: -13, width: 24, height: 24, borderRadius: '50%', background: 'var(--ink-950)' }} />
        <span aria-hidden="true" style={{ position: 'absolute', right: -27, top: -13, width: 24, height: 24, borderRadius: '50%', background: 'var(--ink-950)' }} />
        {row('Assets in vault', `$${s.assets}`)}
        {row('You owe', `$${s.owed}`)}
        {row('You can borrow', `$${s.borrow}`)}
      </div>
      {children}
    </section>
  );
}
export { STATUS_WORD };
