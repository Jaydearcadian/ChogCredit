import { useState } from 'react';
import { parseAbi } from 'viem';
import { TxSteps, useTx } from '../components/tx';
import { Navigate, useNavigate } from 'react-router-dom';
import { Bubble, ChogFrame, Icon, PixelKey, Slip } from '../components/brand';
import { Shell } from '../components/chrome';
import { AccountCard } from '../components/status';
import { useApp } from '../state';
import { setSelected } from './useAccount';

/** S0 Connect: the landing hero from brand board 3, on a phone. Cream, Baloo, the Account Card as the seam. */
export function Connect() {
  const { wallet, connect, error, test } = useApp();
  const [still, setStill] = useState(false);
  if (wallet) return <Navigate to="/pick" replace />;
  return (
    <Shell tabs={false} register="chog">
      <div className="eyebrow" style={{ marginTop: 8 }}>A Chogathon build · Monad {test ? 'testnet' : ''}</div>
      <h1 className="display" style={{ fontSize: 'clamp(48px, 14vw, 72px)' }}>Put your Chog to work.</h1>
      <p className="lede">A vault and a credit line for your Chog Genesis NFT. Add assets, borrow USDC from the pool, and your Chog stays safe in its vault while you owe.</p>
      <div className="stack" style={{ gap: 10 }}>
        <button className="btn cta block" onClick={connect}>Connect wallet</button>
        {error && <div className="banner risk" role="alert">{Icon.alert}<div><b style={{ color: 'var(--text-on-cream)' }}>Couldn't connect</b><p>{error}</p></div></div>}
        <div className="row tiny muted" style={{ justifyContent: 'flex-start', gap: 16 }}><span>Testnet only</span><span>Mock assets</span><span>Not audited</span></div>
      </div>

      <div style={{ position: 'relative', margin: '18px 6px 34px' }}>
        <div className={`float ${still ? 'paused' : ''}`}>
          <AccountCard id={1234} status="safe" label="2.40" fill={0.94} assets="2,000.00" owed="600.00" borrow="340.00" bubble={false} />
        </div>
        <Bubble outlined style={{ position: 'absolute', left: -6, bottom: -26, fontSize: 21 }}>Your Chog has a vault now.</Bubble>
        <button className="btn link tiny" onClick={() => setStill((v) => !v)} aria-pressed={still} style={{ position: 'absolute', right: 0, bottom: -44, height: 32 }}>{still ? 'Play animation' : 'Pause animation'}</button>
      </div>
      <p className="tiny muted" style={{ textAlign: 'center' }}>Sample data</p>

      <ul className="trust">
        <li>{Icon.safeCheck('#2b9a74')}<span>Your Chog is the key, not the collateral. It is never priced and never taken.</span></li>
        <li>{Icon.safeCheck('#2b9a74')}<span>Prices down? Borrowing pauses, repaying never does.</span></li>
        <li>{Icon.safeCheck('#2b9a74')}<span>Sell the whole vault, loan included.</span></li>
        <li>{Icon.eye('#a07400')}<span>If prices fall far enough, others can repay your debt and take assets from the vault. That is the real risk.</span></li>
      </ul>
      <div className="row tiny muted" style={{ justifyContent: 'flex-start', gap: 10, marginTop: 8 }}><Slip size={28} ink="#46188d" perf="#f4f1e6" />Chog artwork and wordmark belong to their owners. Not financial advice.</div>
    </Shell>
  );
}

/** S1 Pick your Chog (onboarding, cream). Each Chog is a card you can pick; the frame morphs into the next screen. */
export function Pick() {
  const { wallet, chogs, dep, test } = useApp();
  const nav = useNavigate();
  const faucet = useTx();
  const claim = () => faucet.run([{ address: dep.chogFaucet!, abi: parseAbi(['function claim() returns (uint256)']), functionName: 'claim', args: [] }]);
  if (!wallet) return <Navigate to="/" replace />;
  const go = (id: number, escrowed: boolean) => { setSelected(id); nav(escrowed ? '/account' : `/open/${id}`, { viewTransition: true }); };
  return (
    <Shell tabs={false} register="chog">
      <h1 className="display" style={{ fontSize: 44, marginTop: 8 }}>Pick your Chog</h1>
      <p className="lede">It gets its own vault, and the Chog moves into it for safekeeping.</p>
      {chogs === null && <div className="skel" style={{ height: 230 }} role="status" aria-label="Looking in your wallet" />}
      {chogs?.length === 0 && (
        <div className="card" style={{ alignItems: 'flex-start', gap: 14 }}>
          <PixelKey width={84} />
          <Bubble>Hm, what's in here?</Bubble>
          <b>No Chog in this wallet.</b>
          <span className="small muted">Switch wallet, or check that the Chog sits in this one.</span>
          {test && dep.chogFaucet && <>
            <button className="btn cta block" disabled={faucet.busy} onClick={claim}>{faucet.busy ? 'Check your wallet' : 'Get a test Chog'}</button>
            <span className="tiny muted">Test network only: a mock Chog Genesis, one per wallet. It is not the real collection.</span>
          </>}
          <TxSteps title="Test Chog" tx={faucet} />
        </div>
      )}
      {chogs?.map((c) => (
        <button key={c.id} onClick={() => go(c.id, c.state === 'escrowed')} className="card pickable" style={{ textAlign: 'left', cursor: 'pointer', font: 'inherit', color: 'inherit' }}>
          <ChogFrame id={c.id} height={120} prop={c.state === 'escrowed' ? 'lock' : null} />
          <div className="row">
            <span className="small">{c.state === 'escrowed' ? 'In its vault' : c.state === 'wallet' ? 'Vault ready. Chog in your wallet' : 'No vault yet'}</span>
            <span className="row small" style={{ gap: 6, color: 'var(--link-light)', fontWeight: 600 }}>{c.state === 'escrowed' ? 'Open' : 'Select'}<svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round" aria-hidden="true"><path d="M9 5l7 7-7 7" /></svg></span>
          </div>
        </button>
      ))}
    </Shell>
  );
}
