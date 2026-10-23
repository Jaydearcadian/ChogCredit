import { useCallback, useRef, useState } from 'react';
import type { Hex } from 'viem';
import { reason, runTx, type TxCall, type TxStage } from '../chain/api';
import { short } from '../chain/format';
import { cue, type Cue } from '../feedback';
import { useApp } from '../state';
import { Icon } from './brand';

/** Runs one or more calls in order (approve, then the action) and tracks the stage of the last one. */
export function useTx() {
  const { wallet, pc, refresh } = useApp();
  const [stage, setStage] = useState<TxStage | null>(null);
  const [step, setStep] = useState<{ i: number; n: number } | null>(null);
  const [message, setMessage] = useState<string | null>(null);
  const [hash, setHash] = useState<Hex | null>(null);
  const gen = useRef(0);
  const busy = stage === 'signing' || stage === 'submitted';

  /** Resolves true once the last call is confirmed; finality moves the stage on in the background.
   *  `confirmCue` lets a flow use its own moment (the door closing, being debt-free) instead of the plain one. */
  const run = useCallback(async (calls: TxCall[], confirmCue: Cue = 'confirmed'): Promise<boolean> => {
    if (!wallet) return false;
    const mine = ++gen.current;
    setMessage(null); setHash(null);
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
        }, (h) => { if (gen.current === mine && last) setHash(h); }));
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

  const reset = useCallback(() => { gen.current++; setStage(null); setStep(null); setMessage(null); setHash(null); }, []);
  return { run, stage, step, message, hash, busy, reset };
}

const ORDER: TxStage[] = ['submitted', 'confirmed', 'final'];
const WORD = { submitted: 'Submitted', confirmed: 'Confirmed', final: 'Final' } as Record<string, string>;

/** Board 4: three facts, each step fills only when truly reached (the dot pops and its tick draws). */
export function TxSteps({ title, tx }: { title: string; tx: ReturnType<typeof useTx> }) {
  const { stage, step, message, hash } = tx;
  if (!stage) return null;
  if (stage === 'rejected') return <div className="card" role="status"><b>Not sent</b><span className="small muted">You rejected it in the wallet. Nothing changed.</span></div>;
  if (stage === 'failed') return <div className="banner danger" role="alert">{Icon.alert}<div><b>Didn't go through</b><p>{message ?? 'The transaction failed.'} Nothing else changed.</p></div></div>;
  const at = ORDER.indexOf(stage);
  return (
    <div className="card" role="status" aria-live="polite">
      <div className="row"><b className="small">{title}</b>{stage === 'signing' && <span className="tiny muted">Check your wallet{step && step.n > 1 ? ` · step ${step.i} of ${step.n}` : ''}</span>}</div>
      <div className="steps">
        {ORDER.map((s, i) => (
          <FragmentStep key={s} label={WORD[s]} done={i <= at} next={i === at + 1} line={i < ORDER.length - 1 ? i < at : null} />
        ))}
      </div>
      <span className="tiny muted">
        {stage === 'final' ? 'Final on Monad.' : stage === 'confirmed' ? 'Confirmed means the network saw it. It is final a moment later.' : stage === 'submitted' ? 'Sent. Waiting for a block.' : 'Nothing is sent until you sign.'}
        {hash && <> <span className="num">{short(hash)}</span></>}
      </span>
    </div>
  );
}

function FragmentStep({ label, done, next, line }: { label: string; done: boolean; next: boolean; line: boolean | null }) {
  return (
    <>
      <div className={`step ${done ? 'done' : ''} ${next ? 'next' : ''}`}>
        <span className="dot">{done && Icon.check()}</span>{label}
      </div>
      {line !== null && <div className={`line ${line ? 'done' : ''}`}><i /></div>}
    </>
  );
}
