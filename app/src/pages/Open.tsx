import { Link, Navigate, useParams } from 'react-router-dom';
import { ABI } from '../chain/api';
import { Bubble, ChogFrame } from '../components/brand';
import { Shell } from '../components/chrome';
import { VaultDoor } from '../components/moments';
import { TxSteps, useTx } from '../components/tx';
import { useApp } from '../state';
import { setSelected } from './useAccount';

/** S2 Open a vault, S3 Vault opened (with the Vault Door). Onboarding, so the cream register. */
export default function Open() {
  const id = Number(useParams().id);
  const { dep, wallet, chogs } = useApp();
  const tx = useTx();
  const row = chogs?.find((c) => c.id === id);
  const done = tx.stage === 'confirmed' || tx.stage === 'final';
  if (!wallet) return <Navigate to="/" replace />;
  if (row?.state === 'escrowed' && !done) return <Navigate to="/account" replace />;

  const open = async () => {
    const calls = [];
    if (row?.state === 'novault') calls.push({ address: dep.registry, abi: ABI.registry, functionName: 'createAccount', args: [dep.mockChogGenesis, BigInt(id)] });
    calls.push({ address: dep.mockChogGenesis, abi: ABI.chog, functionName: 'safeTransferFrom', args: [wallet.address, dep.escrow, BigInt(id)] });
    if (await tx.run(calls, 'door')) setSelected(id);
  };

  if (done) {
    return (
      <Shell tabs={false} register="chog">
        <div style={{ position: 'relative', marginTop: 8 }}>
          <ChogFrame id={id} height={176} morph />
          <div style={{ position: 'absolute', inset: 0, borderRadius: 16, overflow: 'hidden' }}><VaultDoor /></div>
        </div>
        <h1 className="display" style={{ fontSize: 48 }}>Vault opened.</h1>
        <Bubble>Hm, what's in here?</Bubble>
        <p className="lede">Chog #{id} is in its vault. Add something to start. Nothing is borrowed yet.</p>
        <TxSteps title="Opening the vault" tx={tx} />
        <div className="stack" style={{ marginTop: 'auto' }}>
          <Link className="btn cta block" to="/add" viewTransition>Add assets</Link>
          <Link className="btn secondary block" to="/account" viewTransition>Look around first</Link>
        </div>
      </Shell>
    );
  }
  return (
    <Shell tabs={false} register="chog" back="/pick">
      <h1 className="display" style={{ fontSize: 44, marginTop: 8 }}>Open a vault</h1>
      <ChogFrame id={id} height={176} morph />
      <div className="card">
        <b>What happens</b>
        <div className="note"><span className="num">1</span><span>Your Chog moves into its vault for safekeeping.</span></div>
        <div className="note"><span className="num">2</span><span>{row?.state === 'novault' ? 'The vault is created for this Chog.' : 'Its vault is already there.'}</span></div>
        <div className="note"><svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round" aria-hidden="true"><rect x="5" y="11" width="14" height="9" rx="2" /><path d="M8 11V8a4 4 0 018 0v3" /></svg><span>It stays while the vault holds assets or you owe. Empty the vault and repay, and it comes back.</span></div>
      </div>
      <TxSteps title="Opening the vault" tx={tx} />
      <div style={{ marginTop: 'auto' }}>
        <button className="btn cta block" disabled={tx.busy} onClick={open}>{tx.busy ? <><span className="spin" aria-hidden="true" />Check your wallet</> : 'Open vault'}</button>
      </div>
    </Shell>
  );
}
