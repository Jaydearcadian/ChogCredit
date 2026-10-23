import { useEffect, useState, type ReactNode } from 'react';
import { confirmedOnce, getPrefs, onPrefs, setPrefs } from '../feedback';
import { NavLink } from 'react-router-dom';
import { short } from '../chain/format';
import { STATUS_WORD, type Status } from '../chain/status';
import { useApp } from '../state';
import { Wordmark } from './brand';

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

/** Neutral placeholder: Chog art is not cleared for use (docs/brand/DESIGN.md). */
export function ArtBox({ id, height = 150 }: { id: number; height?: number }) {
  return (
    <div style={{ position: 'relative', height, borderRadius: 16, border: '2px solid var(--purple-500)', background: 'repeating-linear-gradient(135deg,#181330 0 12px,#211a40 12px 24px)', display: 'flex', alignItems: 'flex-end', justifyContent: 'space-between', padding: 10 }}>
      <span className="num small" style={{ background: '#0e0b1a', borderRadius: 8, padding: '4px 8px', color: '#d2cceA' }}>Chog art · placeholder</span>
      <span className="num small" style={{ background: '#faf9fc', color: '#0e0b1a', borderRadius: 8, padding: '4px 8px' }}>#{id}</span>
    </div>
  );
}

export function TopBar() {
  const { wallet, test } = useApp();
  return (
    <header style={{ height: 60, display: 'flex', alignItems: 'center', justifyContent: 'space-between', padding: '0 16px', borderBottom: '1px solid var(--ink-700)', position: 'sticky', top: 0, background: 'var(--ink-950)', zIndex: 5 }}>
      <Wordmark />
      <span className="row" style={{ gap: 8 }}>
        {test && <span className="pill-testnet">TESTNET · MOCK</span>}
        {wallet && <span className="num small muted">{short(wallet.address)}</span>}
      </span>
    </header>
  );
}

const I = (d: ReactNode) => <svg width="24" height="24" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round" aria-hidden="true">{d}</svg>;
const TABS: [string, string, ReactNode][] = [
  ['/account', 'Account', I(<><rect x="3" y="6" width="18" height="13" rx="3" /><path d="M3 10h18" /><path d="M16 15h2" /></>)],
  ['/borrow', 'Borrow', I(<><circle cx="12" cy="12" r="9" /><path d="M12 7v10M9.5 9.5h4a2 2 0 010 4h-3.5" /></>)],
  ['/activity', 'Activity', I(<><path d="M4 7h16M4 12h16M4 17h10" /></>)],
  ['/sell', 'Sell', I(<><path d="M4 12l8-8h7v7l-8 8z" /><circle cx="15.5" cy="8.5" r="1" /></>)],
  ['/risk', 'Risk', I(<><path d="M12 3l8 3v6c0 4.5-3.2 7.8-8 9-4.8-1.2-8-4.5-8-9V6z" /></>)],
];
export function TabBar() {
  return (
    <nav aria-label="Main" style={{ position: 'fixed', bottom: 0, left: 0, right: 0, paddingBottom: 'env(safe-area-inset-bottom)', background: 'var(--ink-900)', borderTop: '1px solid var(--ink-700)', display: 'flex', justifyContent: 'center', zIndex: 5 }}>
      <div style={{ display: 'flex', width: '100%', maxWidth: 480 }}>
        {TABS.map(([to, label, icon]) => (
          <NavLink key={to} to={to} style={({ isActive }) => ({ flex: 1, minHeight: 68, display: 'flex', flexDirection: 'column', gap: 2, alignItems: 'center', justifyContent: 'center', color: isActive ? 'var(--purple-300)' : 'var(--text-muted)', fontWeight: isActive ? 700 : 400, fontSize: 12, textDecoration: 'none' })}>
            {icon}{label}
          </NavLink>
        ))}
      </div>
    </nav>
  );
}

export function Shell({ children, tabs = true, register = 'ledger' }: { children: ReactNode; tabs?: boolean; register?: 'ledger' | 'chog' }) {
  return (
    <div className={`shell ${register === 'chog' ? 'cream' : ''}`} style={register === 'chog' ? { background: '#f4f1e6' } : undefined}>
      <TopBar />
      <SoundOffer />
      <main>{children}</main>
      {tabs && <TabBar />}
    </div>
  );
}

/** Offered once, in one sentence, after the first confirmed transaction. Never on load, never a modal. */
function SoundOffer() {
  const [, force] = useState(0);
  useEffect(() => onPrefs(() => force((n) => n + 1)), []);
  if (!confirmedOnce() || getPrefs().offered) return null;
  return (
    <div className="card offer rise" role="region" aria-label="Sounds" style={{ flexDirection: 'row', alignItems: 'center' }}>
      <span style={{ flex: 1 }}>Want tiny sounds?</span>
      <button className="btn" style={{ minHeight: 44 }} onClick={() => setPrefs({ sound: true, offered: true })}>Yes</button>
      <button className="btn secondary" style={{ minHeight: 44 }} onClick={() => setPrefs({ offered: true })}>No thanks</button>
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
