import { useCallback, useRef, useState } from 'react';
import { reason, runTx, type TxCall, type TxStage } from '../chain/api';
import { cue, type Cue } from '../feedback';
import { useApp } from '../state';

const ORDER: TxStage[] = ['submitted', 'confirmed', 'final'];
const WORD: Record<string, string> = { submitted: 'Submitted', confirmed: 'Confirmed', final: 'Final' };

/** Runs one or more calls in order (for example approve, then deposit) and tracks the stage of the current one. */
export function useTx() {
  const { wallet, pc, refresh } = useApp();
  const [stage, setStage] = useState<TxStage | null>(null);
  const [step, setStep] = useState<{ i: number; n: number } | null>(null);
  const [message, setMessage] = useState<string | null>(null);
  const gen = useRef(0);
  const busy = stage === 'signing' || stage === 'submitted';

  /** Resolves true once the last call is confirmed. Finality is tracked in the background and moves the stage on.
   *  `confirmCue` lets a flow use its own moment (the door closing, being debt-free) instead of the plain confirmation. */
  const run = useCallback(async (calls: TxCall[], confirmCue: Cue = 'confirmed'): Promise<boolean> => {
    if (!wallet) return false;
    const mine = ++gen.current;
    setMessage(null);
    try {
      let finality: Promise<void> = Promise.resolve();
      for (let i = 0; i < calls.length; i++) {
        setStep({ i: i + 1, n: calls.length });
        const last = i === calls.length - 1;
        ({ finality } = await runTx(wallet, pc, calls[i], (s, detail) => {
          if (gen.current !== mine) return;
          setStage(s); if (detail) setMessage(detail);
          if (s === 'submitted') cue('submitted');
          if (s === 'confirmed' && last) cue(confirmCue);
          if (s === 'failed') cue('error');
        }));
        if (!last) await finality; // the next step may depend on this one
      }
      refresh();
      finality.then(() => { if (gen.current === mine) { setStage('final'); cue('final'); } });
      return true;
    } catch (e) {
      if (gen.current === mine) { setStage((s) => (s === 'rejected' ? s : 'failed')); setMessage((m) => m ?? reason(e)); }
      return false;
    }
  }, [wallet, pc, refresh]);

  const reset = useCallback(() => { gen.current++; setStage(null); setStep(null); setMessage(null); }, []);
  return { run, stage, step, message, busy, reset };
}

/** Steps fill only when truly reached. Confirmed gets one pop and the tick draws itself (brand board 7). */
export function TxStrip({ stage, step, message }: { stage: TxStage | null; step: { i: number; n: number } | null; message: string | null }) {
  if (!stage) return null;
  if (stage === 'rejected') return <div className="card" role="status"><b>Not sent</b><span className="small muted">You rejected it in the wallet. Nothing changed. You can try again.</span></div>;
  if (stage === 'failed') return <div className="banner danger" role="alert"><b>Failed</b><span className="small">{message ?? 'The transaction did not go through.'} Nothing else changed.</span></div>;
  if (stage === 'signing') return <div className="card" role="status"><b>Check your wallet{step && step.n > 1 ? ` (step ${step.i} of ${step.n})` : ''}</b></div>;
  const at = ORDER.indexOf(stage);
  return (
    <div className="card" role="status" aria-live="polite" style={{ gap: 14 }}>
      <div style={{ display: 'flex', alignItems: 'flex-start' }}>
        {ORDER.map((s, i) => (
          <div key={s} style={{ display: 'contents' }}>
            <div className="stack" style={{ alignItems: 'center', gap: 6, width: 76 }}>
              <span style={{ width: 22, height: 22, borderRadius: '50%', boxSizing: 'border-box', border: `2px solid ${i <= at ? 'var(--safe)' : 'var(--ink-700)'}`, background: i <= at ? 'var(--safe)' : 'var(--ink-700)', transition: 'background var(--t-base) var(--ease), border-color var(--t-base) var(--ease)' }} />
              <span className="small" style={{ color: i <= at ? 'var(--text)' : 'var(--text-muted)' }}>{WORD[s]}</span>
            </div>
            {i < ORDER.length - 1 && (
              <div style={{ flex: 1, height: 2, background: 'var(--ink-700)', marginTop: 10 }}>
                {i < at && <div className="step-line" style={{ height: 2, background: 'var(--safe)' }} />}
              </div>
            )}
          </div>
        ))}
      </div>
      {stage === 'confirmed' && (
        <div className="row" style={{ justifyContent: 'flex-start', gap: 12 }}>
          <div className="popit" style={{ width: 44, height: 44, borderRadius: '50%', background: 'var(--safe)', display: 'grid', placeItems: 'center', flex: 'none' }}>
            <svg width="26" height="26" viewBox="0 0 24 24" fill="none" stroke="#0E0B1A" strokeWidth="3" strokeLinecap="round" strokeLinejoin="round" aria-hidden="true"><path className="tickdraw" d="M5 12.5l4.5 4.5L19 7.5" /></svg>
          </div>
          <span className="small muted">In a block. Not final yet. We will update when it is.</span>
        </div>
      )}
      {stage === 'final' && <span className="small muted">Done and final on Monad.</span>}
    </div>
  );
}
