import { useEffect, useState } from 'react';
import { Bubble, Icon, PixelKey } from '../components/brand';
import { loadRisk, type RiskView } from '../chain/api';
import { fmtUsdc, span } from '../chain/format';
import { useApp } from '../state';
import { LIQUIDATABLE_BELOW_BPS, RISK_BELOW_BPS, WATCH_BELOW_BPS } from '../chain/status';
import { Shell } from '../components/chrome';
import { Chip } from '../components/status';

export function Soon({ title, why }: { title: string; why: string }) {
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
/** S18 Risk: the plain explainer. */
export function Risk() {
  const { dep, pc } = useApp();
  const [r, setR] = useState<RiskView | null>(null);
  useEffect(() => { let live = true; loadRisk(pc, dep).then((v) => live && setR(v)).catch(() => undefined); return () => { live = false; }; }, [pc, dep]);
  const pct = (bps: bigint | number) => `${(Number(bps) / 100).toFixed(0)}%`;
  const x = (bps: bigint) => (Number(bps) / 10_000).toFixed(2);
  return (
    <Shell>
      <h1>How risk works</h1>
      <div className="card">
        <b>Your Chog is the key, not the collateral</b>
        <span className="small muted">Only the assets in your vault back the loan. The Chog is never priced and never taken. $CHOG can sit in the vault but counts for nothing.</span>
      </div>
      <div className="card">
        <b>Four states</b>
        <div className="kv"><Chip status="safe" /><span>Health {x(WATCH_BELOW_BPS)} or more. Comfortably within your limit.</span></div>
        <div className="kv"><Chip status="watch" /><span>Health {x(RISK_BELOW_BPS)} to {x(WATCH_BELOW_BPS)}. Getting close. Nothing to do yet.</span></div>
        <div className="kv"><Chip status="risk" /><span>Health {x(LIQUIDATABLE_BELOW_BPS)} to {x(RISK_BELOW_BPS)}. Add assets or repay soon.</span></div>
        <div className="kv"><Chip status="danger" /><span>Health below {x(LIQUIDATABLE_BELOW_BPS)}. Others may repay your debt and take assets.</span></div>
        <span className="tiny muted">Health is what your assets would fetch in a sale, divided by what you owe.</span>
      </div>
      {r && (
        <div className="card">
          <b>The numbers</b>
          {r.collaterals.map((c) => (
            <div key={c.token} className="stack" style={{ gap: 4 }}>
              <div className="kv"><span>{c.symbol}: borrow up to</span><span className="num">{pct(c.ltvBps)} of its value</span></div>
              <div className="kv"><span>{c.symbol}: sold off below</span><span className="num">{pct(c.thresholdBps)} of its value</span></div>
              <div className="kv"><span>{c.symbol}: bonus to whoever repays</span><span className="num">{pct(c.bonusBps)}</span></div>
            </div>
          ))}
          <div className="kv"><span>One repayment covers up to</span><span className="num">{pct(r.closeFactorBps)} of the debt</span></div>
          <div className="kv"><span>Most one account can owe</span><span className="num">${fmtUsdc(r.accountDebtCap)}</span></div>
          <div className="kv"><span>Most the pool will lend</span><span className="num">${fmtUsdc(r.borrowCap)}</span></div>
          {r.priorityUtilBps > 0 && <div className="kv"><span>Busy pool: vaults open {span(r.priorityMinAge)} borrow first above</span><span className="num">{pct(r.priorityUtilBps)} in use</span></div>}
          <span className="tiny muted">Pool limits are sized to how much can be sold on Monad without moving the price much (about $50,000 of WMON at 2%), so a bad day can be absorbed. They rise as that depth does.</span>
        </div>
      )}
      <div className="banner paused">{Icon.pause}<div><b>When prices pause</b><p>Borrowing and withdrawing stop until prices are back. Repaying and adding assets always work.</p></div></div>
      <div className="card dashed"><span className="small muted">Testnet. Mock tokens and a mock oracle. Not audited. Not financial advice.</span></div>
    </Shell>
  );
}
