import { useEffect, useState } from 'react';
import { Link, useNavigate } from 'react-router-dom';
import { zeroAddress } from 'viem';
import { loadAccount, type AccountView } from '../chain/api';
import { fmtUsdc, healthNumber } from '../chain/format';
import { statusOf } from '../chain/status';
import { Bubble, ChogFrame, PixelKey } from '../components/brand';
import { Shell } from '../components/chrome';
import { Skel } from '../components/moments';
import { Chip } from '../components/status';
import { useApp } from '../state';

/** Look around: every Chog that has a vault, read from the chain. No wallet needed. */
export default function Explore() {
  const { dep, pc, publicChogs, setViewing, wallet, connect } = useApp();
  const nav = useNavigate();
  const [cards, setCards] = useState<Record<number, AccountView>>({});
  const open = publicChogs?.filter((c) => c.escrowed) ?? null;

  useEffect(() => {
    if (!open?.length) return;
    let live = true;
    Promise.all(open.slice(0, 24).map((c) => loadAccount(pc, dep, zeroAddress, c.id).catch(() => null)))
      .then((list) => { if (live) setCards(Object.fromEntries(list.filter((x): x is AccountView => !!x).map((a) => [a.id, a]))); });
    return () => { live = false; };
  }, [open?.map((c) => c.id).join(','), pc, dep]); // eslint-disable-line react-hooks/exhaustive-deps

  const view = (id: number) => { setViewing(id); nav('/account', { viewTransition: true }); };
  return (
    <Shell>
      <h1>Chogs with a vault</h1>
      <p className="muted" style={{ margin: 0 }}>Look at any Chog's vault: what it holds, what it owes and how healthy it is. Read-only, straight from the chain.</p>
      {!wallet && <div className="viewing"><span>You're looking around. Nothing here needs a wallet.</span><button className="btn connect-sm" onClick={connect}>Connect</button></div>}
      {open === null && <div className="pick-grid"><Skel h={260} /><Skel h={260} /><Skel h={260} /></div>}
      {open?.length === 0 && (
        <div className="card" style={{ alignItems: 'flex-start', gap: 12 }}>
          <PixelKey width={72} /><Bubble>Hm, what's in here?</Bubble>
          <b>No Chog has a vault yet.</b>
          <span className="small muted">Be the first: connect a wallet, get a test Chog and open its vault.</span>
          <Link to="/pick" className="btn cta">Get started</Link>
        </div>
      )}
      <div className="pick-grid">
        {open?.map((c) => {
          const a = cards[c.id];
          const st = a ? statusOf(a.data) : null;
          return (
            <button key={c.id} className="card pickable" onClick={() => view(c.id)} style={{ textAlign: 'left', cursor: 'pointer', font: 'inherit', color: 'inherit' }}>
              <ChogFrame id={c.id} height={130} />
              <div className="row">{st ? <Chip status={st} size="sm" /> : <span className="tiny muted">Reading…</span>}<span className="num small">{a ? (st === 'nodebt' ? 'No loan' : `Health ${healthNumber(a.data.healthFactorBps) ?? '--'}`) : ''}</span></div>
              {a && <div className="kv"><span>In vault</span><span className="num">${fmtUsdc(a.data.collateralValue)}</span></div>}
              {a && <div className="kv"><span>Owes</span><span className="num">${fmtUsdc(a.data.debt)}</span></div>}
            </button>
          );
        })}
      </div>
    </Shell>
  );
}
