import { useEffect, useState } from 'react';
import { Link, Navigate } from 'react-router-dom';
import { cue, getPrefs, onPrefs, setPrefs } from '../feedback';
import { Shell } from '../components/parts';
import { useApp } from '../state';

function Toggle({ label, hint, on, set }: { label: string; hint: string; on: boolean; set(v: boolean): void }) {
  return (
    <div className="toggle">
      <div className="stack" style={{ gap: 0 }}><span>{label}</span><span className="small muted">{hint}</span></div>
      <button role="switch" aria-checked={on} aria-label={label} className={`btn ${on ? '' : 'secondary'}`} style={{ minHeight: 44 }} onClick={() => set(!on)}>{on ? 'On' : 'Off'}</button>
    </div>
  );
}

/** S20 Settings: sound off by default, risk sounds a separate switch, haptics on where supported. */
export default function Settings() {
  const { wallet, dep, test, disconnect } = useApp();
  const [p, setP] = useState(getPrefs());
  useEffect(() => onPrefs(() => setP(getPrefs())), []);
  if (!wallet) return <Navigate to="/" replace />;
  return (
    <Shell>
      <h1>Settings</h1>
      <div className="card">
        <Toggle label="Sound" hint="A tiny stamp-like sound for confirmations. Off by default." on={p.sound} set={(v) => { setPrefs({ sound: v, offered: true }); if (v) cue('bubble'); }} />
        <Toggle label="Risk alert sounds" hint="Plays once when a loan gets risky. A separate switch, off by default." on={p.riskSound} set={(v) => setPrefs({ riskSound: v })} />
        <Toggle label="Haptics" hint="A short buzz on confirmations, errors and warnings, where the device supports it. Off when your device asks for reduced motion." on={p.haptics} set={(v) => setPrefs({ haptics: v })} />
      </div>
      <div className="card">
        <div className="row"><span className="muted">Network</span><b>{dep.chainId === 143 ? 'Monad' : dep.chainId === 10143 ? 'Monad testnet' : 'Local chain'}</b></div>
        <div className="row"><span className="muted">Wallet</span><span className="num">{wallet.address.slice(0, 6)}…{wallet.address.slice(-4)}</span></div>
        {test && <span className="small muted">Test deployment: mock assets and a mock oracle.</span>}
      </div>
      <button className="btn secondary" onClick={disconnect}>Disconnect wallet</button>
      <Link to="/account" className="small">Back to account</Link>
    </Shell>
  );
}
