import { useParams, Link, Navigate } from 'react-router-dom';
import { ABI } from '../chain/api';
import { ArtBox, Shell } from '../components/parts';
import { TxStrip, useTx } from '../components/tx';
import { useApp } from '../state';
import { setSelected } from './useAccount';

/** S2 Open a vault, S3 Vault opened */
export default function Open() {
  const { id: idParam } = useParams();
  const id = Number(idParam);
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
        <div className="stack" style={{ marginTop: 16, gap: 18 }}>
          <div className="rise" style={{ position: 'relative', height: 150, borderRadius: 16, overflow: 'hidden', border: '2px solid var(--purple-500)', background: 'repeating-linear-gradient(135deg,#e7e2d0 0 12px,#f4f1e6 12px 24px)' }}>
            <div className="door-l" style={{ position: 'absolute', left: 0, top: 0, width: '50%', height: '100%', background: '#46188d', borderRight: '2px solid #2d2556' }} />
            <div className="door-r" style={{ position: 'absolute', right: 0, top: 0, width: '50%', height: '100%', background: '#46188d', borderLeft: '2px solid #2d2556' }} />
            <div className="stamp" aria-hidden="true" style={{ position: 'absolute', left: '50%', top: '50%', margin: '-14px 0 0 -14px', width: 28, height: 28, borderRadius: 6, background: '#e845a4', border: '3px solid #141026', animationDelay: 'var(--t-slow)' }} />
          </div>
          <h1 className="display rise" style={{ fontSize: 44 }}>Vault opened.</h1>
          <p className="rise" style={{ margin: 0 }}>Chog #{id} is locked in. Add something to start. Nothing is borrowed yet.</p>
          <Link className="btn big rise" to="/add">Add assets</Link>
          <Link className="btn secondary rise" to="/account">Look around first</Link>
        </div>
      </Shell>
    );
  }
  return (
    <Shell tabs={false} register="chog">
      <h1 className="display" style={{ fontSize: 40 }}>Open a vault</h1>
      <ArtBox id={id} height={120} />
      <div className="card">
        <b>What happens</b>
        <span>1. Your Chog moves into escrow.</span>
        <span>2. {row?.state === 'novault' ? 'A vault opens for it.' : 'Its vault is already there.'}</span>
        <span className="small muted">Your Chog stays locked while the vault holds money or debt. Empty it, and the Chog is yours again.</span>
      </div>
      <button className="btn big" disabled={tx.busy} onClick={open}>{tx.busy ? 'Working…' : 'Open vault'}</button>
      <TxStrip stage={tx.stage} step={tx.step} message={tx.message} />
    </Shell>
  );
}
