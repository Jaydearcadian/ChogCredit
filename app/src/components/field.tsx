import { useEffect, useId, useRef, useState } from 'react';

/**
 * Label above (never placeholder-only). On error: border in the risk colour and a persistent message that says what
 * happened and what to do, with a one-tap fix. What the user typed is never cleared. One shake (3 x 9 px), message stays.
 */
export function AmountField({ label, value, onChange, error, fix, onFix, max, onMax, disabled }: {
  label: string; value: string; onChange(v: string): void; error?: string | null; fix?: string; onFix?(): void; max?: string; onMax?(): void; disabled?: boolean;
}) {
  const id = useId();
  const [shake, setShake] = useState(0);
  const seen = useRef<string | null>(null);
  useEffect(() => { if (error && error !== seen.current) setShake((n) => n + 1); seen.current = error ?? null; }, [error]);
  return (
    <div className="stack" style={{ gap: 8 }}>
      <label className="small muted" htmlFor={id}>{label}</label>
      <div key={shake} className={`field ${shake ? 'shakeit' : ''}`} style={error ? { borderColor: 'var(--risk)', borderWidth: 2 } : undefined}>
        <input id={id} inputMode="decimal" placeholder="0" value={value} disabled={disabled} aria-invalid={!!error} aria-describedby={error ? `${id}-e` : undefined} onChange={(e) => onChange(e.target.value)} />
        {onMax && <button type="button" className="btn secondary" style={{ minHeight: 40, padding: '0 12px' }} onClick={onMax} disabled={disabled}>{max ?? 'MAX'}</button>}
      </div>
      {error && (
        <div id={`${id}-e`} role="alert" className="row small" style={{ justifyContent: 'flex-start', gap: 8, color: 'var(--risk)' }}>
          <svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round" aria-hidden="true" style={{ flex: 'none' }}><path d="M12 3.5l9.5 16.5h-19z" /><path d="M12 10v4.5" /><path d="M12 17.4v.1" /></svg>
          <span style={{ color: 'var(--text)' }}>{error}</span>
          {fix && onFix && <button type="button" onClick={onFix} style={{ background: 'none', border: 0, color: 'var(--purple-300)', textDecoration: 'underline', cursor: 'pointer', minHeight: 44, padding: '0 6px' }}>{fix}</button>}
        </div>
      )}
    </div>
  );
}
