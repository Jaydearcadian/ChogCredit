import { Navigate } from 'react-router-dom';
import { Bubble, Icon, PixelKey } from '../components/brand';
import { Shell } from '../components/chrome';
import { Chip } from '../components/status';
import { useApp } from '../state';

function Soon({ title, why }: { title: string; why: string }) {
  const { wallet } = useApp();
  if (!wallet) return <Navigate to="/" replace />;
  return (
    <Shell>
      <h1>{title}</h1>
      <div className="card dashed" style={{ alignItems: 'flex-start', gap: 14 }}>
        <PixelKey width={72} />
        <Bubble>Hm, what's in here?</Bubble>
        <b>Not built yet.</b>
        <span className="small muted">{why}</span>
      </div>
    </Shell>
  );
}
export const Activity = () => <Soon title="Activity" why="The record of everything this account did: time, action, amount, and Submitted, Confirmed or Final." />;
export const Sell = () => <Soon title="Sell with Vault" why="Sell the Chog with everything in its vault, loan included. The contracts are done; these screens come next." />;

/** S18 Risk: the plain explainer. */
export function Risk() {
  const { wallet } = useApp();
  if (!wallet) return <Navigate to="/" replace />;
  return (
    <Shell>
      <h1>How risk works</h1>
      <div className="card">
        <b>Your Chog is the key, not the collateral</b>
        <span className="small muted">Only the assets in your vault back the loan. The Chog is never priced and never taken. $CHOG can sit in the vault but counts for nothing.</span>
      </div>
      <div className="card">
        <b>Four states</b>
        <div className="kv"><Chip status="safe" /><span>Comfortably within your limit.</span></div>
        <div className="kv"><Chip status="watch" /><span>Getting close. Nothing to do yet.</span></div>
        <div className="kv"><Chip status="risk" /><span>Add assets or repay soon.</span></div>
        <div className="kv"><Chip status="danger" /><span>Others may repay your debt and take assets.</span></div>
        <span className="tiny muted">The Watch and At risk lines in this test build are sample values.</span>
      </div>
      <div className="banner paused">{Icon.pause}<div><b>When prices pause</b><p>Borrowing and withdrawing stop until prices are back. Repaying and adding assets always work.</p></div></div>
      <div className="card dashed"><span className="small muted">Testnet. Mock tokens and a mock oracle. Not audited. Not financial advice.</span></div>
    </Shell>
  );
}
