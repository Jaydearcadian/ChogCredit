import { useEffect, useRef } from 'react';
import { installLinks, isMobile, openInWalletLinks, type Found } from '../chain/wallet';
import { Slip } from './brand';

/** Choose a wallet. Lists every wallet the browser has. With none: on a phone, open this page inside a wallet app's
 *  browser; on a computer, install one. A real dialog: focus moves in, Escape closes, focus returns. */
export function WalletPicker({ wallets, onPick, onClose, error }: { wallets: Found[]; onPick(f: Found): void; onClose(): void; error: string | null }) {
  const ref = useRef<HTMLDialogElement>(null);
  useEffect(() => { const d = ref.current; if (d && !d.open) d.showModal(); }, []);
  const mobile = isMobile();
  return (
    <dialog ref={ref} className="picker" aria-labelledby="picker-title" onClose={onClose} onClick={(e) => { if (e.target === ref.current) ref.current?.close(); }}>
      <div className="picker-body">
        <div className="row"><h2 id="picker-title">Connect a wallet</h2><button className="btn link" onClick={() => ref.current?.close()} aria-label="Close">Close</button></div>
        {wallets.length > 0 && (
          <ul className="wallets">
            {wallets.map((w) => (
              <li key={w.id}><button className="wallet" onClick={() => onPick(w)}>
                {w.icon ? <img src={w.icon} alt="" width={32} height={32} /> : <Slip size={32} />}<span>{w.name}</span>
                <svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round" aria-hidden="true"><path d="M9 5l7 7-7 7" /></svg>
              </button></li>
            ))}
          </ul>
        )}
        {wallets.length === 0 && mobile && (
          <>
            <p className="small muted">This browser has no wallet. Open Chog Credit inside your wallet app instead:</p>
            <ul className="wallets">
              {openInWalletLinks().map((l) => <li key={l.name}><a className="wallet" href={l.href}><Slip size={32} /><span>Open in {l.name}</span><svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round" aria-hidden="true"><path d="M7 17L17 7M9 7h8v8" /></svg></a></li>)}
            </ul>
          </>
        )}
        {wallets.length === 0 && !mobile && (
          <>
            <p className="small muted">No wallet found in this browser. Install one, then come back to this page:</p>
            <ul className="wallets">
              {installLinks.map((l) => <li key={l.name}><a className="wallet" href={l.href} target="_blank" rel="noreferrer"><Slip size={32} /><span>Get {l.name}</span><svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round" aria-hidden="true"><path d="M7 17L17 7M9 7h8v8" /></svg></a></li>)}
            </ul>
            <p className="tiny muted">On a phone, open this page and pick your wallet app; it opens Chog Credit in its own browser.</p>
          </>
        )}
        {error && <div className="banner risk" role="alert"><div><b>Couldn't connect</b><p>{error}</p></div></div>}
        <p className="tiny muted">The app asks your wallet to switch to Monad testnet. Nothing is signed by connecting.</p>
      </div>
    </dialog>
  );
}
