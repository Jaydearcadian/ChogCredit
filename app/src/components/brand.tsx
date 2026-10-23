import type { CSSProperties, ReactNode } from 'react';

/** A. The Slip: the brand logo (board 6). Logo, favicon and the Account Card's shape. Never in the app's top bar. */
export function Slip({ size = 48, ink = '#836EF9', perf = '#0E0B1A', label = 'Chog Credit', stub = false }: { size?: number; ink?: string; perf?: string; label?: string; stub?: boolean }) {
  return (
    <svg viewBox="0 0 100 100" width={size} height={size} role="img" aria-label={label} style={{ overflow: 'visible' }}>
      <path d="M16 26 H66 V74 H16 a8 8 0 0 1 -8 -8 V57 a7 7 0 0 0 0 -14 V34 a8 8 0 0 1 8 -8 Z" fill={ink} />
      <rect x="19" y="41" width="18" height="18" rx="4" fill="#E845A4" />
      {size > 32 && <><rect x="43" y="42" width="12" height="4.5" rx="2.2" fill="#FAF9FC" /><rect x="43" y="53.5" width="8" height="4.5" rx="2.2" fill="#FAF9FC" /></>}
      <g className={stub ? 'stub' : undefined}>
        <path d="M66 26 H84 a8 8 0 0 1 8 8 V43 a7 7 0 0 0 0 14 V66 a8 8 0 0 1 -8 8 H66 Z" fill={ink} />
        {size > 32 && <rect x="75" y="46" width="8" height="8" rx="2" fill={perf} />}
      </g>
      {size > 16 && <line x1="66" y1="31" x2="66" y2="69" stroke={perf} strokeWidth="2.4" strokeDasharray="3 4" strokeLinecap="round" />}
    </svg>
  );
}

/** D. The Full Stop: the top-bar wordmark. */
export const Wordmark = () => <span className="wordmark">Chog Credit<i aria-hidden="true" /></span>;

/** B. The Pixel Key: a prop for the browsing and empty states. Never a logo or an icon. */
export function PixelKey({ width = 72, style }: { width?: number; style?: CSSProperties }) {
  return (
    <svg viewBox="0 0 96 48" width={width} height={width / 2} shapeRendering="crispEdges" aria-hidden="true" style={style}>
      <g fill="#836EF9"><rect x="0" y="0" width="32" height="8" /><rect x="0" y="8" width="8" height="16" /><rect x="24" y="8" width="8" height="16" /><rect x="0" y="24" width="32" height="8" /><rect x="32" y="8" width="64" height="16" /><rect x="64" y="24" width="8" height="16" /><rect x="88" y="24" width="8" height="24" /></g>
      <rect x="8" y="8" width="16" height="16" fill="#E845A4" />
    </svg>
  );
}

export type Prop = 'coin' | 'star' | 'lock' | 'key' | null;
/** Flat pink and amber props that sit around the frame, never on the Chog. */
export function Sticker({ prop, size = 36 }: { prop: Prop; size?: number }) {
  if (!prop) return null;
  if (prop === 'key') return <span className="sticker hop" style={{ position: 'absolute', right: -14, top: -16 }}><PixelKey width={58} /></span>;
  const body: Record<string, ReactNode> = {
    coin: <><circle cx="18" cy="18" r="14" fill="#FCBB00" stroke="#0E0B1A" strokeWidth="2" /><path d="M18 11v14M14 14.5h6.5a2.5 2.5 0 010 5H14" fill="none" stroke="#0E0B1A" strokeWidth="2.2" strokeLinecap="round" /></>,
    star: <path d="M18 3l3.2 9.8L31 14l-7.5 6.2L26 30l-8-5.6L10 30l2.5-9.8L5 14l9.8-1.2z" fill="#E845A4" stroke="#0E0B1A" strokeWidth="2" strokeLinejoin="round" />,
    lock: <><rect x="7" y="15" width="22" height="16" rx="4" fill="#E845A4" stroke="#0E0B1A" strokeWidth="2" /><path d="M12 15v-4a6 6 0 0112 0v4" fill="none" stroke="#0E0B1A" strokeWidth="2.4" strokeLinecap="round" /><circle cx="18" cy="23" r="2.2" fill="#0E0B1A" /></>,
  };
  return <svg key={prop} className="sticker hop" width={size} height={size} viewBox="0 0 36 36" aria-hidden="true" style={{ position: 'absolute', right: -10, top: -12 }}>{body[prop]}</svg>;
}

/** The Chog frame. Official art only, unaltered; until permission is confirmed, the neutral placeholder. */
export function ChogFrame({ id, height, prop = null, morph = false }: { id: number; height?: number; prop?: Prop; morph?: boolean }) {
  return (
    <div className="frame" style={{ height, viewTransitionName: morph ? 'chog-frame' : undefined } as CSSProperties}>
      <span className="tag">Chog art · placeholder</span>
      <span className="id">#{id}</span>
      <Sticker prop={prop} />
    </div>
  );
}

/** The Chog bubble: one handwritten line that repeats what the chip says. Re-keyed so a new line pops in. */
export function Bubble({ children, outlined, style }: { children: string; outlined?: boolean; style?: CSSProperties }) {
  return <div key={children} className={`bubble say ${outlined ? 'outlined' : ''}`} style={style}>{children}</div>;
}

export const Icon = {
  lock: (closing = false) => (
    <svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round" aria-hidden="true">
      <rect x="5" y="11" width="14" height="9" rx="2" /><path className={closing ? 'shackle' : undefined} d="M8 11V8a4 4 0 018 0v3" />
    </svg>
  ),
  back: <svg width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round" aria-hidden="true"><path d="M15 5l-7 7 7 7" /></svg>,
  check: (stroke = '#0E0B1A', size = 14) => <svg width={size} height={size} viewBox="0 0 24 24" fill="none" stroke={stroke} strokeWidth="3" strokeLinecap="round" strokeLinejoin="round" aria-hidden="true"><path className="tick" d="M5 12.5l4.5 4.5L19 7.5" /></svg>,
  pause: <svg width="24" height="24" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round" aria-hidden="true"><rect x="6" y="5" width="4" height="14" rx="1" /><rect x="14" y="5" width="4" height="14" rx="1" /></svg>,
  alert: <svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round" aria-hidden="true"><path d="M12 3.5l9.5 16.5h-19z" /><path d="M12 10v4.5" /><path d="M12 17.4v.1" /></svg>,
  safeCheck: (color = '#72E4BC') => <svg width="20" height="20" viewBox="0 0 24 24" fill="none" stroke={color} strokeWidth="2" strokeLinecap="round" strokeLinejoin="round" aria-hidden="true"><circle cx="12" cy="12" r="9" /><path d="M8 12.5l2.7 2.7L16 9.5" /></svg>,
  eye: (color = '#F9C230') => <svg width="20" height="20" viewBox="0 0 24 24" fill="none" stroke={color} strokeWidth="2" strokeLinecap="round" strokeLinejoin="round" aria-hidden="true"><path d="M2 12s3.5-6 10-6 10 6 10 6-3.5 6-10 6S2 12 2 12z" /><circle cx="12" cy="12" r="2.6" /></svg>,
};
