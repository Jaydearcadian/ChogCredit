import { useEffect, useState } from 'react';
import { loadAccount, type AccountView } from '../chain/api';
import { useApp } from '../state';

const KEY = 'chog-credit:selected';
export const getSelected = (): number | null => { try { const v = sessionStorage.getItem(KEY); return v ? Number(v) : null; } catch { return null; } };
export const setSelected = (id: number) => { try { sessionStorage.setItem(KEY, String(id)); } catch { /* storage can be blocked; the app still works */ } };

/** The selected Chog's account, reloaded whenever a transaction finishes. */
/**
 * The selected Chog's account. Reloads after every transaction and every few seconds while the tab is visible, so a
 * price move shows up in place (the chip swaps, the dot slides, the Pause Drill plays) instead of on the next visit.
 * Only the first load shows a skeleton; later reloads swap numbers quietly.
 */
export function useAccount(): { acct: AccountView | null; id: number | null; loading: boolean } {
  const { dep, pc, wallet, chogs, tick } = useApp();
  const [acct, setAcct] = useState<AccountView | null>(null);
  const [loading, setLoading] = useState(true);
  const [beat, setBeat] = useState(0);
  const selected = getSelected();
  const mine = chogs?.find((c) => c.id === selected && c.state === 'escrowed') ?? chogs?.find((c) => c.state === 'escrowed') ?? null;
  const id = mine?.id ?? null;

  useEffect(() => {
    const t = setInterval(() => { if (document.visibilityState === 'visible') setBeat((n) => n + 1); }, 5000);
    return () => clearInterval(t);
  }, []);

  useEffect(() => {
    if (!wallet || id === null) { setAcct(null); setLoading(chogs === null && !!wallet); return; }
    let live = true;
    loadAccount(pc, dep, wallet.address, id)
      .then((a) => { if (live) { setAcct(a); setLoading(false); } })
      .catch(() => live && setLoading(false)); // a failed poll keeps the last good numbers on screen
    return () => { live = false; };
  }, [dep, pc, wallet, id, tick, chogs, beat]);

  return { acct: acct && acct.id === id ? acct : null, id, loading: loading || (acct !== null && acct.id !== id) };
}
