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
    if (await tx.run(calls)) setSelected(id);
  };

  if (done) {
    return (
      <Shell tabs={false}>
        <div className="stack rise" style={{ marginTop: 24, gap: 18 }}>
          <ArtBox id={id} height={130} />
          <h1>Vault opened.</h1>
          <p className="muted" style={{ margin: 0 }}>Add something to start. Nothing is borrowed yet.</p>
          <Link className="btn big" to="/add">Add assets</Link>
          <Link className="btn secondary" to="/account">Look around first</Link>
        </div>
      </Shell>
    );
  }
  return (
    <Shell tabs={false}>
      <h1>Open a vault</h1>
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
