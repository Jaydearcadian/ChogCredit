import { useEffect, useState } from 'react';
import { loadAccount, type AccountView } from '../chain/api';
import { useApp } from '../state';

const KEY = 'chog-credit:selected';
export const getSelected = (): number | null => { try { const v = sessionStorage.getItem(KEY); return v ? Number(v) : null; } catch { return null; } };
export const setSelected = (id: number) => { try { sessionStorage.setItem(KEY, String(id)); } catch { /* storage can be blocked; the app still works */ } };

/** The selected Chog's account, reloaded whenever a transaction finishes. */
export function useAccount(): { acct: AccountView | null; id: number | null; loading: boolean } {
  const { dep, pc, wallet, chogs, tick } = useApp();
  const [acct, setAcct] = useState<AccountView | null>(null);
  const [loading, setLoading] = useState(true);
  const selected = getSelected();
  const mine = chogs?.find((c) => c.id === selected && c.state === 'escrowed') ?? chogs?.find((c) => c.state === 'escrowed') ?? null;
  const id = mine?.id ?? null;

  useEffect(() => {
    if (!wallet || id === null) { setAcct(null); setLoading(chogs === null && !!wallet); return; }
    let live = true;
    setLoading(true);
    loadAccount(pc, dep, wallet.address, id).then((a) => { if (live) { setAcct(a); setLoading(false); } }).catch(() => live && setLoading(false));
    return () => { live = false; };
  }, [dep, pc, wallet, id, tick, chogs]);

  return { acct, id, loading };
}
