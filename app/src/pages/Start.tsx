import { Link, Navigate, useNavigate } from 'react-router-dom';
import { ArtBox, Shell } from '../components/parts';
import { useApp } from '../state';
import { setSelected } from './useAccount';

/** S0 Connect */
export function Connect() {
  const { wallet, connect, error, test } = useApp();
  if (wallet) return <Navigate to="/pick" replace />;
  return (
    <Shell tabs={false}>
      <div className="stack rise" style={{ marginTop: 24, gap: 20 }}>
        <ArtBox id={1234} height={170} />
        <h1>Your Chog can borrow.</h1>
        <p className="muted" style={{ margin: 0 }}>Lock a Chog in a vault, add assets, borrow USDC against them. Repay and it is yours again.</p>
        <button className="btn big" onClick={connect}>Connect wallet</button>
        {error && <div className="banner risk" role="alert">{error}</div>}
        {test && <p className="small muted" style={{ margin: 0 }}>Testnet. Sample numbers. Mock assets.</p>}
      </div>
    </Shell>
  );
}

/** S1 Pick your Chog */
export function Pick() {
  const { wallet, chogs } = useApp();
  const nav = useNavigate();
  if (!wallet) return <Navigate to="/" replace />;
  return (
    <Shell tabs={false}>
      <h1>Pick your Chog</h1>
      {chogs === null && <p className="muted">Looking in your wallet…</p>}
      {chogs?.length === 0 && (
        <div className="card" style={{ borderStyle: 'dashed' }}>
          <b>No Chog in this wallet.</b>
          <span className="small muted">Switch wallet, or check the Chog sits in this one.</span>
        </div>
      )}
      <div className="stack">
        {chogs?.map((c) => (
          <div key={c.id} className="card rise">
            <ArtBox id={c.id} height={96} />
            <div className="row">
              <span className="muted">{c.state === 'escrowed' ? 'Vault open' : c.state === 'wallet' ? 'Vault ready, Chog in wallet' : 'No vault yet'}</span>
              <button className="btn secondary" style={{ minHeight: 44 }} onClick={() => { setSelected(c.id); nav(c.state === 'escrowed' ? '/account' : `/open/${c.id}`); }}>
                {c.state === 'escrowed' ? 'Open' : 'Select'}
              </button>
            </div>
          </div>
        ))}
      </div>
      {chogs?.length ? <Link to="/" className="small">Use a different wallet</Link> : null}
    </Shell>
  );
}
