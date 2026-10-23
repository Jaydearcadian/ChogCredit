import { useEffect, useId, useRef, useState } from 'react';
import { fmtPlain } from '../chain/format';
import { Icon } from './brand';

/**
 * Amount entry from brand board 4: a large mono figure you can type into, a range to drag, the most you can use,
 * and errors that say what happened and how to fix it (border in the risk colour, one shake, message stays).
 */
export function Amount({ label, unit, decimals, max, value, onChange, error, fixLabel, onFix, maxLabel, disabled, step }: {
  label: string; unit: string; decimals: number; max: bigint; value: string; onChange(v: string): void;
  error?: string | null; fixLabel?: string; onFix?(): void; maxLabel: string; disabled?: boolean; step?: number;
}) {
  const id = useId();
  const [shake, setShake] = useState(0);
  const seen = useRef<string | null>(null);
  useEffect(() => { if (error && error !== seen.current) setShake((n) => n + 1); seen.current = error ?? null; }, [error]);

  const maxN = Number(max) / 10 ** decimals;
  const cur = Math.min(Number(value || 0), maxN);
  const pct = maxN > 0 ? (cur / maxN) * 100 : 0;
  const onRange = (n: number) => {
    if (n >= maxN) { onChange(fmtPlain(max, decimals)); return; } // the end of the range is exactly the max, never a rounded figure
    onChange((Math.round(n * 100) / 100).toFixed(2).replace(/\.00$/, ''));
  };

  return (
    <div className={`amount ${error ? 'error' : ''}`}>
      <label htmlFor={id}>{label}</label>
      <div key={shake} className={`figure ${shake ? 'shake' : ''}`}>
        <input id={id} className="big" inputMode="decimal" autoComplete="off" placeholder="0.00" value={value} disabled={disabled}
          aria-invalid={!!error} aria-describedby={error ? `${id}-e` : undefined}
          onChange={(e) => onChange(e.target.value.replace(/[^0-9.]/g, ''))} />
        <span className="unit">{unit}</span>
      </div>
      <input type="range" className="range" min={0} max={maxN || 0} step={step ?? 0.01} value={cur}
        disabled={disabled || maxN === 0} aria-label={`${label} slider`} style={{ ['--p' as string]: `${pct}%` }}
        onChange={(e) => onRange(Number(e.target.value))} />
      <div className="scale"><span>0</span><button type="button" onClick={() => onChange(fmtPlain(max, decimals))} disabled={disabled}>{maxLabel}</button></div>
      {error && (
        <div id={`${id}-e`} role="alert" className="err">{Icon.alert}<span>{error}</span>{fixLabel && onFix && <button type="button" onClick={onFix}>{fixLabel}</button>}</div>
      )}
    </div>
  );
}

/** A big mono figure without a range: for amounts that are your own call, like a sale price. */
export function Figure({ label, unit, value, onChange, error, hint }: { label: string; unit: string; value: string; onChange(v: string): void; error?: string | null; hint?: string }) {
  const id = useId();
  return (
    <div className={`amount ${error ? 'error' : ''}`}>
      <label htmlFor={id}>{label}</label>
      <div className="figure">
        <input id={id} className="big" inputMode="decimal" autoComplete="off" placeholder="0.00" value={value} aria-invalid={!!error} aria-describedby={error ? `${id}-e` : undefined} onChange={(e) => onChange(e.target.value.replace(/[^0-9.]/g, ''))} />
        <span className="unit">{unit}</span>
      </div>
      {hint && !error && <span className="tiny muted">{hint}</span>}
      {error && <div id={`${id}-e`} role="alert" className="err">{Icon.alert}<span>{error}</span></div>}
    </div>
  );
}

/** A plain text field (addresses), label above, error below. */
export function TextField({ label, value, onChange, error, placeholder }: { label: string; value: string; onChange(v: string): void; error?: string | null; placeholder?: string }) {
  const id = useId();
  return (
    <div className={`amount ${error ? 'error' : ''}`}>
      <label htmlFor={id}>{label}</label>
      <input id={id} className="text-input" autoComplete="off" spellCheck={false} placeholder={placeholder} value={value} aria-invalid={!!error} aria-describedby={error ? `${id}-e` : undefined} onChange={(e) => onChange(e.target.value.trim())} />
      {error && <div id={`${id}-e`} role="alert" className="err">{Icon.alert}<span>{error}</span></div>}
    </div>
  );
}
