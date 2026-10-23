import { useEffect, useLayoutEffect, useRef, useState, type ReactNode } from 'react';
import { STATUS_WORD, type Status } from '../chain/status';
import { Bubble, ChogFrame, type Prop } from './brand';

type Shown = Exclude<Status, 'nodebt'> | 'none';
const ICON: Record<Shown, ReactNode> = {
  safe: <><circle cx="12" cy="12" r="9" /><path d="M8 12.5l2.7 2.7L16 9.5" /></>,
  watch: <><path d="M2 12s3.5-6 10-6 10 6 10 6-3.5 6-10 6S2 12 2 12z" /><circle cx="12" cy="12" r="2.6" /></>,
  risk: <><path d="M12 3.5l9.5 16.5h-19z" /><path d="M12 10v4.5" /><path d="M12 17.4v.1" /></>,
  danger: <><path d="M8.5 2.8h7l5.7 5.7v7l-5.7 5.7h-7L2.8 15.5v-7z" /><path d="M12 7.5v5.5" /><path d="M12 16.6v.1" /></>,
  paused: <><rect x="6" y="5" width="4" height="14" rx="1" /><rect x="14" y="5" width="4" height="14" rx="1" /></>,
  none: <><circle cx="12" cy="12" r="9" /><path d="M8 12h8" /></>,
};
const shown = (s: Status): Shown => (s === 'nodebt' ? 'none' : s);

/** Icon + word + colour. Colour lives in the icon and border; the word is always cream. */
export function Chip({ status, size = 'md' }: { status: Status; size?: 'sm' | 'md' | 'lg' }) {
  const s = shown(status);
  const px = size === 'sm' ? 16 : size === 'lg' ? 20 : 18;
  return (
    <span className={`chip ${s} ${size === 'md' ? '' : size}`}>
      <svg width={px} height={px} viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round" aria-hidden="true">{ICON[s]}</svg>
      <span>{s === 'none' ? 'No loan' : STATUS_WORD[s]}</span>
    </span>
  );
}

/** Keeps the old child for one beat when `k` changes, so the old state can leave while the new one arrives. */
export function Swap({ k, children }: { k: string; children: ReactNode }) {
  const shown = useRef<{ k: string; node: ReactNode }>({ k, node: children });
  const timer = useRef<ReturnType<typeof setTimeout>>();
  const [leaving, setLeaving] = useState<{ k: string; node: ReactNode } | null>(null);
  useLayoutEffect(() => {
    if (shown.current.k !== k) {
      setLeaving(shown.current); // the old state stays on screen for one animation, then goes
      clearTimeout(timer.current);
      timer.current = setTimeout(() => setLeaving(null), 340);
    }
    shown.current = { k, node: children };
  });
  useEffect(() => () => clearTimeout(timer.current), []);
  return (
    <span className="swap">
      {leaving && <span key={`out-${leaving.k}`} className="out" aria-hidden="true">{leaving.node}</span>}
      <span key={`in-${k}`} className={leaving ? 'in' : undefined}>{children}</span>
    </span>
  );
}

/** A number in JetBrains Mono whose changed digits roll: up when it grows, down when it shrinks. First paint is still. */
export function Num({ value, className = 'num' }: { value: string; className?: string }) {
  const prev = useRef(value);
  const [from, setFrom] = useState(value);
  const [gen, setGen] = useState(0);
  useEffect(() => {
    if (prev.current === value) return;
    setFrom(prev.current); setGen((g) => g + 1); prev.current = value;
    const t = setTimeout(() => setFrom(value), 420); // settle back to plain text once the roll is over
    return () => clearTimeout(t);
  }, [value]);
  const changed = gen > 0 && from !== value;
  const dir = Number(value.replace(/[^0-9.-]/g, '')) >= Number(from.replace(/[^0-9.-]/g, '')) ? 'up' : 'down';
  const old = from.padStart(value.length, ' ');
  return (
    <span className={className} aria-label={value} role="text">
      <span aria-hidden="true">
        {[...value].map((ch, i) => {
          const o = old[i];
          if (!changed || o === ch || !/\d/.test(ch)) return <span key={`s${i}`}>{ch}</span>;
          const pair = dir === 'up' ? [o, ch] : [ch, o];
          return <span key={`d${i}-${gen}`} className={`digit ${dir}`}><i>{pair.map((c, j) => <span key={j}>{/\d/.test(c ?? '') ? c : ' '}</span>)}</i></span>;
        })}
      </span>
    </span>
  );
}

/**
 * The Health Ring: 270 degrees opening at the bottom, track ink-700, progress purple-500, one pink dot at the end.
 * The ring never changes colour; the chip does. The dot slides (300 ms) and the number's digits roll in step.
 */
export function HealthRing({ fill, label, paused = false, size = 'md' }: { fill: number | null; label: string; paused?: boolean; size?: 'md' | 'lg' }) {
  const C = 2 * Math.PI * 52, arc = C * 0.75;
  const f = fill === null ? 0 : Math.max(0.03, Math.min(1, fill));
  const word = !/^[\d.\u221e-]+$/.test(label);
  return (
    <div className={`ring ${size === 'lg' ? 'lg' : ''}`} role="img" aria-label={paused ? 'Health unavailable while prices are paused' : `Health ${label}`}>
      <svg viewBox="0 0 120 120" aria-hidden="true">
        <circle cx="60" cy="60" r="52" fill="none" stroke="var(--ink-700)" strokeWidth="10" strokeLinecap="round" strokeDasharray={paused ? '6 10' : `${arc} ${C}`} transform="rotate(135 60 60)" />
        {!paused && fill !== null && <>
          <circle className="arc" cx="60" cy="60" r="52" fill="none" stroke="var(--purple-500)" strokeWidth="10" strokeLinecap="round" strokeDasharray={`${arc} ${C}`} strokeDashoffset={arc * (1 - f)} transform="rotate(135 60 60)" />
          <g className="dot" style={{ transform: `rotate(${270 * f}deg)` }}><circle cx="23.23" cy="96.77" r="7" fill="var(--pink-500)" stroke="var(--ink-900)" strokeWidth="3" /></g>
        </>}
      </svg>
      <div className="center"><Num value={paused ? '--' : label} className={`num ${word ? 'word' : ''}`} /><small>Health</small></div>
    </div>
  );
}

/** Ring fill from health in bps: 1.0 sits at about a fifth, 2.5 and up is full. */
export const ringFill = (status: Status, bps: bigint) =>
  status === 'nodebt' ? 1 : status === 'paused' ? null : Math.min(1, Math.max(0, (Number(bps) / 10_000 - 0.75) / 1.75));

export const PROP: Record<Status, Prop> = { nodebt: 'key', safe: 'coin', watch: 'star', risk: 'lock', danger: 'lock', paused: null };
/** Bubble copy from the brand pass. Interface expressions, never advice beyond these prompts. */
export const BUBBLE: Record<Status, string> = {
  nodebt: "All good. I'm just sitting in my vault.", safe: "All good. I'm just sitting in my vault.", watch: 'Keep an eye on me.',
  risk: "I'd add some collateral.", danger: 'Repay or add assets now.', paused: 'Prices are napping. Repay still works.',
};

/** The Account Card (board 2): Chog frame, chip, ring and bubble, then the tear line and the three numbers. */
export function AccountCard({ id, status, label, fill, assets, owed, borrow, morph = false, bubble = true }: {
  id: number; status: Status; label: string; fill: number | null; assets: string; owed: string; borrow: string; morph?: boolean; bubble?: boolean;
}) {
  const paused = status === 'paused';
  return (
    <section className={`account-card ${paused ? 'paused' : ''}`} aria-label={`Chog ${id}`}>
      <ChogFrame id={id} prop={PROP[status]} morph={morph} />
      <Swap k={status}><Chip status={status} size="lg" /></Swap>
      <div className="row" style={{ justifyContent: 'flex-start', gap: 14 }}>
        <HealthRing fill={fill} label={label} paused={paused} />
        {bubble && <Bubble>{BUBBLE[status]}</Bubble>}
      </div>
      <div className="tear">
        <div className="kv"><span>Assets in vault</span><Num value={paused ? '--' : `$${assets}`} /></div>
        <div className="kv"><span>You owe</span><Num value={`$${owed}`} /></div>
        <div className="kv"><span>You can borrow</span><Num value={paused ? 'Paused' : `$${borrow}`} /></div>
      </div>
    </section>
  );
}
