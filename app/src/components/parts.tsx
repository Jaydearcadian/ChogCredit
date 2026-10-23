import type { ReactNode } from 'react';
import { NavLink } from 'react-router-dom';
import { short } from '../chain/format';
import { STATUS_WORD, type Status } from '../chain/status';
import { useApp } from '../state';

const ICON: Record<string, ReactNode> = {
  safe: <><circle cx="12" cy="12" r="9" /><path d="M8 12.5l2.7 2.7L16 9.5" /></>,
  watch: <><path d="M2 12s3.5-6 10-6 10 6 10 6-3.5 6-10 6S2 12 2 12z" /><circle cx="12" cy="12" r="2.6" /></>,
  risk: <><path d="M12 3.5l9.5 16.5h-19z" /><path d="M12 10v4.5" /><path d="M12 17.4v.1" /></>,
  danger: <><path d="M8.5 2.8h7l5.7 5.7v7l-5.7 5.7h-7L2.8 15.5v-7z" /><path d="M12 7.5v5.5" /><path d="M12 16.6v.1" /></>,
  paused: <><rect x="6" y="5" width="4" height="14" rx="1" /><rect x="14" y="5" width="4" height="14" rx="1" /></>,
};
const COLOR: Record<string, string> = { safe: 'var(--safe)', watch: 'var(--watch)', risk: 'var(--risk)', danger: 'var(--danger)', paused: 'var(--paused)' };
const TINT: Record<string, string> = { safe: 'var(--safe-tint)', watch: 'var(--watch-tint)', risk: 'var(--risk-tint)', danger: 'var(--danger-tint)', paused: 'var(--paused-tint)' };

/** Icon + word + colour. Never colour alone. */
export function StatusChip({ status }: { status: Exclude<Status, 'nodebt'> }) {
  return (
    <span style={{ display: 'inline-flex', alignItems: 'center', gap: 8, padding: '6px 12px', borderRadius: 12, border: `2px ${status === 'paused' ? 'dashed' : 'solid'} ${COLOR[status]}`, background: TINT[status], color: COLOR[status] }}>
      <svg width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round" aria-hidden="true">{ICON[status]}</svg>
      <span style={{ color: 'var(--text)', fontWeight: 600, fontSize: 15 }}>{STATUS_WORD[status]}</span>
    </span>
  );
}

/** 270 degree gauge. `fill` 0..1, null = unavailable. The marker shape and the number repeat what the colour says. */
export function Ring({ status, fill, label }: { status: Exclude<Status, 'nodebt'> | 'nodebt'; fill: number | null; label: string }) {
  const color = status === 'nodebt' ? 'var(--purple-500)' : COLOR[status];
  const C = 2 * Math.PI * 52, arc = C * 0.75;
  const f = fill === null ? 0 : Math.max(0.02, Math.min(1, fill));
  const ang = ((135 + 270 * f) * Math.PI) / 180;
  return (
    <svg width="132" height="132" viewBox="0 0 120 120" role="img" aria-label={`Health ${label}`}>
      <circle cx="60" cy="60" r="52" fill="none" stroke="var(--ink-700)" strokeWidth="10" strokeLinecap="round" strokeDasharray={status === 'paused' ? '6 10' : `${arc} ${C}`} transform="rotate(135 60 60)" />
      {fill !== null && <circle cx="60" cy="60" r="52" fill="none" stroke={color} strokeWidth="10" strokeLinecap="round" strokeDasharray={`${arc * f} ${C}`} transform="rotate(135 60 60)" style={{ transition: 'stroke-dasharray var(--t-slow) var(--ease)' }} />}
      {fill !== null && <circle cx={60 + 52 * Math.cos(ang)} cy={60 + 52 * Math.sin(ang)} r="7" fill={color} stroke="var(--ink-900)" strokeWidth="3" />}
      <text x="60" y="64" textAnchor="middle" fontSize="24" fontWeight="600" fill="var(--text)" fontFamily="var(--font-num)">{label}</text>
      <text x="60" y="84" textAnchor="middle" fontSize="12" fill="var(--text-muted)" fontFamily="var(--font-body)">Health</text>
    </svg>
  );
}

/** Neutral placeholder: Chog art is not cleared for use (docs/brand/DESIGN.md). */
export function ArtBox({ id, height = 150 }: { id: number; height?: number }) {
  return (
    <div style={{ position: 'relative', height, borderRadius: 16, border: '2px solid var(--purple-500)', background: 'repeating-linear-gradient(135deg,#181330 0 12px,#211a40 12px 24px)', display: 'flex', alignItems: 'flex-end', justifyContent: 'space-between', padding: 10 }}>
      <span className="num small" style={{ background: 'var(--ink-950)', borderRadius: 8, padding: '4px 8px', color: 'var(--text-muted)' }}>Chog art · placeholder</span>
      <span className="num small" style={{ background: 'var(--cream-50)', color: 'var(--ink-950)', borderRadius: 8, padding: '4px 8px' }}>#{id}</span>
    </div>
  );
}

export function TopBar() {
  const { wallet, test } = useApp();
  return (
    <header style={{ height: 56, display: 'flex', alignItems: 'center', justifyContent: 'space-between', padding: '0 16px', borderBottom: '1px solid var(--ink-700)', position: 'sticky', top: 0, background: 'var(--ink-950)', zIndex: 5 }}>
      <span style={{ fontFamily: 'var(--font-display)', fontWeight: 800, fontSize: 22, display: 'flex', alignItems: 'flex-end' }}>
        Chog Credit<span aria-hidden="true" style={{ width: 7, height: 7, background: 'var(--purple-500)', marginLeft: 3, marginBottom: 6 }} />
      </span>
      <span className="row" style={{ gap: 8 }}>
        {test && <span className="pill-testnet">TESTNET · MOCK</span>}
        {wallet && <span className="num small muted">{short(wallet.address)}</span>}
      </span>
    </header>
  );
}

const TABS: [string, string][] = [['/account', 'Account'], ['/borrow', 'Borrow'], ['/activity', 'Activity'], ['/sell', 'Sell'], ['/risk', 'Risk']];
export function TabBar() {
  return (
    <nav aria-label="Main" style={{ position: 'fixed', bottom: 0, left: 0, right: 0, background: 'var(--ink-900)', borderTop: '1px solid var(--ink-700)', display: 'flex', justifyContent: 'center', zIndex: 5 }}>
      <div style={{ display: 'flex', width: '100%', maxWidth: 480 }}>
        {TABS.map(([to, label]) => (
          <NavLink key={to} to={to} style={({ isActive }) => ({ flex: 1, minHeight: 64, display: 'flex', alignItems: 'center', justifyContent: 'center', color: isActive ? 'var(--text)' : 'var(--text-muted)', fontWeight: isActive ? 600 : 400, fontSize: 14, textDecoration: 'none', borderTop: `3px solid ${isActive ? 'var(--purple-500)' : 'transparent'}` })}>
            {label}
          </NavLink>
        ))}
      </div>
    </nav>
  );
}

export function Shell({ children, tabs = true }: { children: ReactNode; tabs?: boolean }) {
  return (
    <div className="shell">
      <TopBar />
      <main>{children}</main>
      {tabs && <TabBar />}
    </div>
  );
}

export function LockNote({ children }: { children: ReactNode }) {
  return (
    <div className="card" style={{ borderStyle: 'dashed', flexDirection: 'row', alignItems: 'center', gap: 10 }}>
      <svg width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round" aria-hidden="true" style={{ flex: 'none' }}><rect x="5" y="11" width="14" height="9" rx="2" /><path d="M8 11V8a4 4 0 018 0v3" /></svg>
      <span className="small muted">{children}</span>
    </div>
  );
}
