import { Link, Navigate } from 'react-router-dom';
import { fmtUsdc, healthNumber } from '../chain/format';
import { statusOf } from '../chain/status';
import { Bubble, ChogFrame, Icon } from '../components/brand';
import { Shell } from '../components/chrome';
import { AccountSkeleton } from '../components/moments';
import { BUBBLE, Chip, HealthRing, Num, PROP, ringFill, Swap } from '../components/status';
import { useApp } from '../state';
import { useAccount } from './useAccount';

/** S4 Account overview, as drawn on brand board 4 (phones 1 and 3). */
export default function Account() {
  const { wallet, chogs } = useApp();
  const { acct, id, loading } = useAccount();
  if (!wallet) return <Navigate to="/" replace />;
  if (chogs && id === null) return <Navigate to="/pick" replace />;
  if (loading || !acct || id === null) return <Shell enter={false}><AccountSkeleton /></Shell>;

  const d = acct.data;
  const status = statusOf(d);
  const paused = status === 'paused';
  const owes = d.debt > 0n;
  const label = status === 'nodebt' ? '\u221e' : paused ? '--' : (healthNumber(d.healthFactorBps) ?? '--');
  const canBorrow = d.priceOk && d.availableToBorrow > 0n;
  const borrowWhy = !d.priceOk ? 'Borrow paused' : acct.poolLiquidity === 0n ? 'Pool is empty' : 'Limit reached';
  const empty = acct.tokens.every((t) => t.accounted === 0n);

  return (
    <Shell>
      <ChogFrame id={id} morph prop={PROP[status]} />
      <div className="note small">{Icon.lock()}<span>Chog #{id} is in its vault. It stays while {owes ? 'you owe' : 'the vault holds assets'}.</span></div>

      <section className={`card health-card ${paused ? 'paused' : ''}`} aria-label="Health">
        <HealthRing fill={ringFill(status, d.healthFactorBps)} label={label} paused={paused} />
        <div className="stats">
          <Swap k={status}><Chip status={status} /></Swap>
          <div className="kv"><span>In vault</span><Num value={paused ? '--' : `$${fmtUsdc(d.collateralValue)}`} /></div>
          <div className="kv"><span>You owe</span><Num value={`$${fmtUsdc(d.debt)}`} /></div>
          <div className="kv"><span>Can borrow</span><Num value={!d.priceOk ? 'Paused' : `$${fmtUsdc(d.availableToBorrow)}`} /></div>
        </div>
      </section>

      {/* The Pause Drill: Borrow locks in place; Repay does not move. */}
      <div className="pair">
        {canBorrow
          ? <Link key="b" to="/borrow" viewTransition className="btn">Borrow</Link>
          : <span key="l" className={`btn locked ${!d.priceOk ? 'locking' : ''}`} role="link" aria-disabled="true">{Icon.lock(!d.priceOk)}{borrowWhy}</span>}
        {owes
          ? <Link to="/repay" viewTransition className="btn secondary">Repay</Link>
          : <Link to="/add" viewTransition className="btn secondary">Add assets</Link>}
      </div>
      {/* Banners arrive below the money actions, so nothing above them moves when prices pause. */}
      {paused && (
        <div className="banner paused" role="status">{Icon.pause}<div><b>Prices are paused</b><p>Borrowing and withdrawing are off until prices are back. Repaying and adding assets still work.</p></div></div>
      )}
      {status === 'danger' && (
        <div className="banner danger" role="alert">{Icon.alert}<div><b>Anyone can now liquidate this vault</b><p>Others may repay your debt and take assets. Repay or add assets to bring health above 1.00.</p></div></div>
      )}

      <div className="pair">
        {owes ? <Link to="/add" viewTransition className="btn quiet">Add assets</Link> : <Link to="/release" viewTransition className="btn quiet">Release Chog</Link>}
        {paused && owes
          ? <span className="btn quiet locked" aria-disabled="true">{Icon.lock()}Withdraw paused</span>
          : empty ? <span className="btn quiet locked" aria-disabled="true">Nothing to withdraw</span> : <Link to="/withdraw" viewTransition className="btn quiet">Withdraw</Link>}
      </div>

      <Bubble>{empty && !owes ? "Hm, what's in here?" : BUBBLE[status]}</Bubble>

      <div className="row small" style={{ marginTop: 8 }}>
        {owes ? <Link to="/release" viewTransition>Release the Chog</Link> : <span />}
        <Link to="/settings" viewTransition>Settings</Link>
      </div>
    </Shell>
  );
}
