import { useEffect, useState } from 'react';
import { Link } from 'react-router-dom';
import { zeroAddress } from 'viem';
import { loadActivity, type Row } from '../chain/activity';
import { Bubble, PixelKey } from '../components/brand';
import { Shell } from '../components/chrome';
import { Skel } from '../components/moments';
import { useApp } from '../state';
import { useAccount } from './useAccount';

const when = (t: number) => {
  const d = new Date(t * 1000), now = new Date();
  const time = d.toLocaleTimeString([], { hour: '2-digit', minute: '2-digit' });
  return d.toDateString() === now.toDateString() ? time : `${d.toLocaleDateString([], { day: 'numeric', month: 'short' })} ${time}`;
};

/** S17 Activity: a real table (board 5). Time, Action, Amount, Status; Submitted rows live on the screen that sent them. */
export default function Activity() {
  const { wallet, dep, pc, tick, chogs } = useApp();
  const { acct, id } = useAccount();
  const [rows, setRows] = useState<Row[] | null>(null);
  const [err, setErr] = useState<string | null>(null);
  const [limit, setLimit] = useState(25);
  // Public RPCs only serve logs in small block ranges, so history is read from the newest blocks backwards, on request.
  const [span, setSpan] = useState(dep.chainId === 31337 ? 10n ** 12n : 3_000n);
  const [range, setRange] = useState<{ from: bigint; complete: boolean } | null>(null);

  useEffect(() => {
    if (!acct) return;
    let on = true;
    const load = () => loadActivity(pc, dep, acct.key, acct.vault, wallet?.address ?? zeroAddress, span).then((r) => { if (on) { setRows(r.rows); setRange({ from: r.from, complete: r.complete }); setErr(null); } }).catch((e) => on && setErr(String(e.shortMessage ?? e.message ?? e)));
    load();
    const t = setInterval(load, 8000);
    return () => { on = false; clearInterval(t); };
  }, [acct?.key, acct?.vault, wallet, pc, dep, tick, span]); // eslint-disable-line react-hooks/exhaustive-deps

  if (chogs && id === null) return <Shell><h1>Activity</h1><div className="card"><b>No Chog in a vault yet.</b><Link to="/pick" className="btn">Pick a Chog</Link></div></Shell>;

  return (
    <Shell>
      <h1>Activity</h1>
      {id !== null && <span className="small muted">Chog #{id}. Everything this account did, newest first.</span>}
      {err && <div className="banner watch" role="status"><div><b>Couldn't read the history</b><p>{err}</p></div></div>}
      {rows === null && !err && <div className="stack"><Skel h={36} r={8} /><Skel h={36} r={8} /><Skel h={36} r={8} /></div>}
      {rows?.length === 0 && range?.complete && <div className="card" style={{ alignItems: 'flex-start', gap: 12 }}><PixelKey width={72} /><Bubble>Hm, what's in here?</Bubble><span className="small muted">Nothing yet.</span></div>}
      {rows?.length === 0 && range && !range.complete && <span className="small muted">Nothing in the recent blocks.</span>}
      {rows && rows.length > 0 && (
        <section className="card">
          <table className="table">
            <caption className="sr">Account activity</caption>
            <thead><tr><th scope="col">Action</th><th scope="col" className="amt">Amount</th><th scope="col">Status</th></tr></thead>
            <tbody>
              {rows.slice(0, limit).map((r) => (
                <tr key={r.id}>
                  <td>{r.action}<span className="when">{when(r.time)}</span></td>
                  <td className="amt num">{r.amount}</td>
                  <td><span className={`state ${r.final ? 'final' : 'confirmed'}`}><i aria-hidden="true" />{r.final ? 'Final' : 'Confirmed'}</span></td>
                </tr>
              ))}
            </tbody>
          </table>
          {rows.length > limit && <button className="btn link" onClick={() => setLimit((n) => n + 25)}>Show older</button>}
        </section>
      )}
      {range && !range.complete && <button className="btn quiet block" onClick={() => setSpan((n) => n * 4n)}>Look further back</button>}
      <span className="tiny muted">Confirmed means the network saw it. Final comes a moment later.{range && !range.complete && ` Showing roughly the last ${span.toLocaleString()} blocks; the public node serves history in small pieces.`}</span>
    </Shell>
  );
}
