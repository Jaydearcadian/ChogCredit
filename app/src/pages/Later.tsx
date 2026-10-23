import { Navigate } from 'react-router-dom';
import { Shell, StatusChip } from '../components/parts';
import { useApp } from '../state';

function Soon({ title, why }: { title: string; why: string }) {
  const { wallet } = useApp();
  if (!wallet) return <Navigate to="/" replace />;
  return (
    <Shell>
      <h1>{title}</h1>
      <div className="card" style={{ borderStyle: 'dashed' }}><b>Not built yet.</b><span className="small muted">{why}</span></div>
    </Shell>
  );
}

export const Activity = () => <Soon title="Activity" why="The record of what happened to this account. Next after the money screens." />;
export const Sell = () => <Soon title="Sell with vault" why="Sell setup, buyer review and signing (wireframe board D). The contracts are done; the screens are next." />;

/** S18 Risk: plain explainer. The numbers are the app's sample thresholds. */
export function Risk() {
  const { wallet } = useApp();
  if (!wallet) return <Navigate to="/" replace />;
  return (
    <Shell>
      <h1>How risk works</h1>
      <div className="card"><b>Your limit</b><span className="small muted">Each asset counts for part of its value. Safer assets count more. $CHOG is held but counts for nothing.</span></div>
      <div className="card">
        <b>The four states</b>
        <div className="row"><StatusChip status="safe" /><span className="small muted">comfortable</span></div>
        <div className="row"><StatusChip status="watch" /><span className="small muted">keep an eye</span></div>
        <div className="row"><StatusChip status="risk" /><span className="small muted">act soon</span></div>
        <div className="row"><StatusChip status="danger" /><span className="small muted">can be liquidated</span></div>
        <span className="small muted">The Watch and At risk lines shown in this app are sample values.</span>
      </div>
      <div className="card" style={{ borderStyle: 'dashed' }}><span className="small muted">Testnet. Mock tokens. Mock oracle. Not audited. Not financial advice.</span></div>
    </Shell>
  );
}
