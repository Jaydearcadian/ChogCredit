import { useCallback, useRef, useState } from 'react';
import { reason, runTx, type TxCall, type TxStage } from '../chain/api';
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

  /** Resolves true once the last call is confirmed. Finality is tracked in the background and moves the stage on. */
  const run = useCallback(async (calls: TxCall[]): Promise<boolean> => {
    if (!wallet) return false;
    const mine = ++gen.current;
    setMessage(null);
    try {
      let finality: Promise<void> = Promise.resolve();
      for (let i = 0; i < calls.length; i++) {
        setStep({ i: i + 1, n: calls.length });
        ({ finality } = await runTx(wallet, pc, calls[i], (s, detail) => { if (gen.current === mine) { setStage(s); if (detail) setMessage(detail); } }));
        if (i < calls.length - 1) await finality; // the next step may depend on this one
      }
      refresh();
      finality.then(() => { if (gen.current === mine) setStage('final'); });
      return true;
    } catch (e) {
      if (gen.current === mine) { setStage((s) => (s === 'rejected' ? s : 'failed')); setMessage((m) => m ?? reason(e)); }
      return false;
    }
  }, [wallet, pc, refresh]);

  const reset = useCallback(() => { gen.current++; setStage(null); setStep(null); setMessage(null); }, []);
  return { run, stage, step, message, busy, reset };
}

export function TxStrip({ stage, step, message }: { stage: TxStage | null; step: { i: number; n: number } | null; message: string | null }) {
  if (!stage) return null;
  if (stage === 'rejected') return <div className="card" role="status"><b>Not sent</b><span className="small muted">You rejected it in the wallet. Nothing changed. You can try again.</span></div>;
  if (stage === 'failed') return <div className="banner danger" role="alert"><b>Failed</b><span className="small">{message ?? 'The transaction did not go through.'} Nothing else changed.</span></div>;
  const at = ORDER.indexOf(stage);
  return (
    <div className="card" role="status" aria-live="polite">
      {stage === 'signing' ? <b>Check your wallet{step && step.n > 1 ? ` (step ${step.i} of ${step.n})` : ''}</b> : (
        <div className="row small" style={{ justifyContent: 'flex-start', gap: 8, flexWrap: 'wrap' }}>
          {ORDER.map((s, i) => (
            <span key={s} style={{ padding: '2px 10px', borderRadius: 8, border: `1px ${i <= at ? 'solid' : 'dashed'} ${i <= at ? 'var(--purple-300)' : 'var(--ink-700)'}`, color: i <= at ? 'var(--text)' : 'var(--text-muted)' }}>{WORD[s]}</span>
          ))}
        </div>
      )}
      {stage === 'final' && <span className="small muted">Done and final on Monad.</span>}
      {stage === 'confirmed' && <span className="small muted">Not final yet. We will update when it is.</span>}
    </div>
  );
}
