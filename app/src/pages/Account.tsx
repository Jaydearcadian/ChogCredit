import { Link, Navigate } from 'react-router-dom';
import { fmt, fmtUsdc, healthNumber } from '../chain/format';
import { statusOf } from '../chain/status';
import { AccountCard } from '../components/brand';
import { LockNote, Shell, StatusChip, ArtBox } from '../components/parts';
import { useApp } from '../state';
import { useAccount } from './useAccount';

/** S4 Account overview */
export default function Account() {
  const { wallet, chogs } = useApp();
  const { acct, id, loading } = useAccount();
  if (!wallet) return <Navigate to="/" replace />;
  if (chogs && id === null) return <Navigate to="/pick" replace />;
  if (loading || !acct) return <Shell><p className="muted">Loading your account…</p></Shell>;

  const d = acct.data;
  const status = statusOf(d);
  const holdings = acct.tokens.filter((t) => t.accounted > 0n);
  const fill = status === 'nodebt' ? 1 : status === 'paused' ? null : Math.min(1, Number(d.healthFactorBps) / 25_000);
  const label = status === 'nodebt' ? 'No loan' : status === 'paused' ? '--' : (healthNumber(d.healthFactorBps) ?? '--');
  const bannerStatus = status === 'nodebt' ? null : status;

  const chip = bannerStatus ? <StatusChip status={bannerStatus} /> : (
    <span style={{ display: 'inline-flex', alignItems: 'center', gap: 8, padding: '6px 12px', borderRadius: 12, border: '2px solid var(--purple-500)', background: 'var(--ink-850)' }}>
      <svg width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="var(--purple-300)" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round" aria-hidden="true"><rect x="5" y="11" width="14" height="9" rx="2" /><path d="M8 11V8a4 4 0 018 0v3" /></svg>
      <span style={{ fontWeight: 600, fontSize: 15 }}>No loan</span>
    </span>
  );

  return (
    <Shell>
      <h1 className="rise">Chog #{id}</h1>
      <AccountCard s={{ id: id!, status, ringFill: fill, ringLabel: label, assets: fmtUsdc(d.collateralValue), owed: fmtUsdc(d.debt), borrow: fmtUsdc(d.priceOk ? d.availableToBorrow : 0n), chip, art: <ArtBox id={id!} height={150} /> }} />

      {status === 'paused' && (
        <div className="banner paused" role="status"><b>Prices paused</b><span className="small">We can't trust the latest price right now, so borrowing and withdrawing are paused. Your funds are not moving. Repaying and adding assets still work.</span></div>
      )}
      {status === 'danger' && (
        <div className="banner danger" role="alert"><b>Anyone can now liquidate this vault.</b><span className="small">Repay or add assets to bring health above the line.</span></div>
      )}
      {(status === 'risk' || status === 'watch') && (
        <div className="banner" style={{ background: status === 'risk' ? 'var(--risk-tint)' : 'var(--watch-tint)', borderColor: status === 'risk' ? 'var(--risk)' : 'var(--watch)' }} role="status">
          <b>{status === 'risk' ? 'Your loan is close to the limit.' : 'Keep an eye on this loan.'}</b>
          <span className="small">Repaying or adding assets raises health.</span>
        </div>
      )}
      {d.priceOk && d.borrowPower > d.debt && d.availableToBorrow === 0n && (
        <LockNote>{acct.poolLiquidity === 0n ? 'The pool has no USDC to lend right now, so borrowing is paused until lenders add some.' : 'Nothing is available to borrow right now: a pool or account limit is reached.'}</LockNote>
      )}
      {status === 'nodebt' && !d.priceOk && <LockNote>Borrowing is paused while prices are unavailable.</LockNote>}

      <div className="row rise" style={{ gap: 12 }}>
        <Link to="/borrow" className={`btn ${d.priceOk && d.availableToBorrow > 0n ? '' : 'disabled'}`} style={{ flex: 1 }} aria-disabled={!(d.priceOk && d.availableToBorrow > 0n)}>Borrow</Link>
        <Link to="/add" className="btn secondary" style={{ flex: 1 }}>Add assets</Link>
      </div>

      <div className="card rise">
        <div className="row"><b>In the vault</b><Link to="/withdraw" className="small">Withdraw</Link></div>
        {holdings.length === 0 && <span className="small muted">Nothing yet. Add assets to start.</span>}
        {holdings.map((t) => (
          <div className="row" key={t.symbol}>
            <span>{t.symbol}{!t.counts && <span className="small muted"> · held, no credit</span>}</span>
            <span className="num">{fmt(t.accounted, t.decimals, t.decimals === 6 ? 2 : 2)}</span>
          </div>
        ))}
      </div>
      <p className="small muted" style={{ margin: 0 }}>Prices from the pool's oracle. Sample numbers on a test network.</p>
      <div className="row"><Link to="/release" className="small">Release the Chog</Link><Link to="/settings" className="small">Settings</Link></div>
    </Shell>
  );
}
