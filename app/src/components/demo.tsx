import { useEffect, useRef, useSyncExternalStore } from 'react';
import { Link, useLocation, useNavigate } from 'react-router-dom';
import { useApp } from '../state';
import { PixelKey } from './brand';

/**
 * The 60-second demo: a guided look at one real vault on the testnet, with nothing to sign and no wallet. It asks first
 * ("Want a quick demo?"), then walks Account, Activity, Lend and Risk, and ends by offering to try it for real.
 * The step lives in sessionStorage so it survives a refresh and ends with the tab.
 */
const KEY = 'chog-credit:tour';
const read = (): number | null => { try { const v = sessionStorage.getItem(KEY); return v === null ? null : Number(v); } catch { return null; } };
let step: number | null = read();
const subs = new Set<() => void>();
const setStep = (n: number | null) => {
  step = n;
  try { n === null ? sessionStorage.removeItem(KEY) : sessionStorage.setItem(KEY, String(n)); } catch { /* storage can be blocked */ }
  subs.forEach((f) => f());
};
const useStep = () => useSyncExternalStore((f) => { subs.add(f); return () => { subs.delete(f); }; }, () => step, () => null);

const STOPS = [
  { path: '/account', title: 'A real vault', text: "This is a demo vault we opened on Monad testnet, with test WMON inside and a real USDC loan against it. Everything on the card comes straight from the chain: what's inside, what it owes, how safe it is, and what it can still borrow." },
  { path: '/activity', title: 'Every move is public', text: 'Deposits, borrows and repayments are on-chain history. Anyone can read it, no wallet needed.' },
  { path: '/lend', title: 'Where lender yield comes from', text: 'Lenders earn what borrowers pay. The demo vault borrowed, so part of the pool is in use and the yield shown is real interest on a test network. With nothing borrowed, lenders earn nothing.' },
  { path: '/risk', title: 'Every limit, read from the contract', text: 'How much you can borrow, when a vault can be sold off, the pool limits and who gets priority when the pool is busy. Nothing is hidden or set by the app.' },
  { path: null, title: 'Try it for real', text: 'Connect a wallet, get a free test Chog and do it yourself in about three minutes. You need a little test MON for gas.' },
] as const;

/** The "Want a quick demo?" question, shown before looking around. */
export function DemoPrompt({ onClose }: { onClose(): void }) {
  const ref = useRef<HTMLDialogElement>(null);
  const nav = useNavigate();
  const { dep, publicChogs, setViewing } = useApp();
  const demoId = dep.demoChog ?? publicChogs?.find((c) => c.escrowed)?.id ?? null;
  useEffect(() => { const d = ref.current; if (d && !d.open) d.showModal(); }, []);
  const yes = () => { if (demoId === null) return; setViewing(demoId); setStep(0); ref.current?.close(); nav(STOPS[0].path, { viewTransition: true }); };
  const no = () => { ref.current?.close(); nav('/explore', { viewTransition: true }); };
  return (
    <dialog ref={ref} className="picker" aria-labelledby="demo-title" onClose={onClose} onClick={(e) => { if (e.target === ref.current) ref.current?.close(); }}>
      <div className="picker-body">
        <div className="row"><PixelKey width={64} /><button className="btn link" onClick={() => ref.current?.close()} aria-label="Close">Close</button></div>
        <h2 id="demo-title" style={{ fontSize: 24 }}>Want a 60-second demo?</h2>
        <p className="small muted">A guided look at a demo vault we opened on Monad testnet: what it holds, what it owes, what lenders earn and what the limits are. No wallet, nothing to sign.</p>
        <div className="stack" style={{ gap: 10 }}>
          <button className="btn cta block" autoFocus onClick={yes} disabled={demoId === null}>Yes, show me</button>
          <button className="btn secondary block" onClick={no}>No, I'll look around</button>
        </div>
        {demoId === null && <p className="tiny muted">No vault exists on this network yet, so there is nothing to show. You can still look around.</p>}
      </div>
    </dialog>
  );
}

/** A small offer to start the demo, for the Look around screen. */
export function DemoOffer() {
  const { dep, publicChogs, setViewing } = useApp();
  const nav = useNavigate();
  const demoId = dep.demoChog ?? publicChogs?.find((c) => c.escrowed)?.id ?? null;
  if (demoId === null) return null;
  return <button className="btn connect-sm secondary" onClick={() => { setViewing(demoId); setStep(0); nav(STOPS[0].path, { viewTransition: true }); }}>60-second demo</button>;
}

/** The guide: a card above the tab bar that moves between screens. Rendered once, inside the router. */
export function Tour() {
  const s = useStep();
  const nav = useNavigate();
  const loc = useLocation();
  const { connect, dep, publicChogs, setViewing, wallet } = useApp();
  const demoId = dep.demoChog ?? publicChogs?.find((c) => c.escrowed)?.id ?? null;
  const stop = s === null ? null : STOPS[Math.min(s, STOPS.length - 1)];

  // Follow the step: show the right screen and the demo vault.
  useEffect(() => {
    if (s === null || !stop) return;
    if (demoId !== null) setViewing(demoId);
    if (stop.path && loc.pathname !== stop.path) nav(stop.path, { viewTransition: true });
  }, [s]); // eslint-disable-line react-hooks/exhaustive-deps
  // Leave room under the page so the card never covers its last line.
  useEffect(() => { document.body.dataset.tour = s === null ? '' : 'on'; return () => { document.body.dataset.tour = ''; }; }, [s]);
  // A wallet connecting ends the demo: you are doing it for real now.
  useEffect(() => { if (wallet && s !== null) setStep(null); }, [wallet, s]);

  if (s === null || !stop) return null;
  const last = s >= STOPS.length - 1;
  return (
    <aside className="tour" role="region" aria-label="Demo">
      <div className="row"><span className="eyebrow">Demo · {s + 1} of {STOPS.length}</span><button className="btn link" onClick={() => setStep(null)}>Close</button></div>
      <b className="tour-title">{stop.title}</b>
      <p className="small" style={{ color: 'var(--text-muted)' }}>{stop.text}</p>
      <div className="pair">
        {s > 0 ? <button className="btn secondary" onClick={() => setStep(s - 1)}>Back</button> : <span />}
        {last
          ? <button className="btn cta" onClick={() => { setStep(null); connect(); }}>Connect wallet</button>
          : <button className="btn cta" onClick={() => setStep(s + 1)}>Next</button>}
      </div>
      {last && <span className="tiny muted">Need test MON? <a href="https://faucet.monad.xyz" target="_blank" rel="noreferrer">The Monad testnet faucet</a> has it. <Link to="/explore" onClick={() => setStep(null)}>Keep looking around</Link></span>}
    </aside>
  );
}
