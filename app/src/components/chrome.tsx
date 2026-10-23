import { useEffect, useState, type ReactNode } from 'react';
import { NavLink, useNavigate } from 'react-router-dom';
import { short } from '../chain/format';
import { confirmedOnce, getPrefs, onPrefs, setPrefs } from '../feedback';
import { useApp } from '../state';
import { Icon, Wordmark } from './brand';

const I = (d: ReactNode) => <svg width="24" height="24" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round" aria-hidden="true">{d}</svg>;
/** Tab icons drawn as on brand board 4. */
const TABS: [string, string, ReactNode][] = [
  ['/account', 'Account', I(<><rect x="3" y="6" width="18" height="13" rx="3" /><path d="M3 10h18" /></>)],
  ['/borrow', 'Borrow', I(<><path d="M12 4v12M7 11l5 5 5-5" /><path d="M5 20h14" /></>)],
  ['/activity', 'Activity', I(<path d="M5 5h14M5 12h14M5 19h9" />)],
  ['/sell', 'Sell', I(<path d="M7 7h11l-3-3M17 17H6l3 3" />)],
  ['/risk', 'Risk', I(<><circle cx="12" cy="12" r="9" /><path d="M12 11v5M12 8v.1" /></>)],
];

export function TabBar() {
  return (
    <nav className="tabbar" aria-label="Main">
      <div>
        {TABS.map(([to, label, icon]) => (
          <NavLink key={to} to={to} viewTransition className={({ isActive }) => `tab ${isActive ? 'active' : ''}`}>{icon}{label}</NavLink>
        ))}
      </div>
    </nav>
  );
}

/** App header: the Full Stop wordmark and the TESTNET pill; in a focused flow, Back and the screen's name. */
export function Header({ title, back }: { title?: string; back?: string }) {
  const { wallet, test } = useApp();
  const nav = useNavigate();
  return (
    <header className="header">
      {back ? (
        <button className="back" onClick={() => (history.length > 1 ? nav(-1) : nav(back, { viewTransition: true }))}>{Icon.back}Back</button>
      ) : <Wordmark />}
      {title && <span className="title">{title}</span>}
      <span className="meta">
        {test && <span className="pill">TESTNET</span>}
        {!title && wallet && <span className="addr">{short(wallet.address)}</span>}
      </span>
    </header>
  );
}

export function Shell({ children, tabs = true, register = 'ledger', title, back, enter = true, wide = false }: {
  children: ReactNode; tabs?: boolean; register?: 'ledger' | 'chog'; title?: string; back?: string; enter?: boolean; wide?: boolean;
}) {
  return (
    <div className={`shell ${register === 'chog' ? 'cream' : ''} ${tabs ? '' : 'no-tabs'} ${wide ? 'wide' : ''}`}>
      <Header title={title} back={back} />
      <SoundOffer />
      <main className={enter ? 'enter' : undefined}>{children}</main>
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
    <div className="card" role="region" aria-label="Sounds" style={{ margin: '12px 18px 0', flexDirection: 'row', alignItems: 'center', animation: 'rise var(--dur-standard) var(--ease) both' }}>
      <span className="grow">Want tiny sounds?</span>
      <button className="btn" style={{ height: 44 }} onClick={() => setPrefs({ sound: true, offered: true })}>Yes</button>
      <button className="btn secondary" style={{ height: 44 }} onClick={() => setPrefs({ offered: true })}>No thanks</button>
    </div>
  );
}
