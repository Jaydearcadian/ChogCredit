import { createContext, useCallback, useContext, useEffect, useMemo, useRef, useState, type ReactNode } from 'react';
import type { PublicClient } from 'viem';
import { loadChogs, type ChogRow } from './chain/api';
import { isTestDeployment, loadDeployment, type Deployment } from './chain/config';
import { connectDev, connectProvider, devWalletAllowed, discoverWallets, publicClientFor, type Found, type Wallet } from './chain/wallet';
import { WalletPicker } from './components/picker';

type Ctx = {
  dep: Deployment; pc: PublicClient; wallet: Wallet | null; chogs: ChogRow[] | null; test: boolean; tick: number;
  connect(): Promise<void>; disconnect(): void; refresh(): void; error: string | null;
};
const C = createContext<Ctx | null>(null);
export const useApp = () => { const v = useContext(C); if (!v) throw new Error('outside provider'); return v; };

const LAST = 'chog-credit:wallet';
const remember = (id: string | null) => { try { if (id) localStorage.setItem(LAST, id); else localStorage.removeItem(LAST); } catch { /* storage blocked */ } };
const lastWallet = () => { try { return localStorage.getItem(LAST); } catch { return null; } };

export function AppProvider({ children }: { children: ReactNode }) {
  const [dep, setDep] = useState<Deployment | null>(null);
  const [wallet, setWallet] = useState<Wallet | null>(null);
  const [chogs, setChogs] = useState<ChogRow[] | null>(null);
  const [tick, setTick] = useState(0);
  const [error, setError] = useState<string | null>(null);
  const [picking, setPicking] = useState<Found[] | null>(null);
  const followUp = useRef<ReturnType<typeof setTimeout>>();

  useEffect(() => { loadDeployment().then(setDep).catch((e) => setError(String(e.message ?? e))); }, []);
  const pc = useMemo(() => (dep ? publicClientFor(dep.chainId) : null), [dep]);

  /** Re-read now, and once more a moment later: a public node can answer from a block just before the one that
   *  holds your transaction, and a stale read would leave a screen waiting for state that has already changed. */
  const refresh = useCallback(() => {
    setTick((t) => t + 1);
    clearTimeout(followUp.current);
    followUp.current = setTimeout(() => setTick((t) => t + 1), 2500);
  }, []);
  useEffect(() => {
    const t = setInterval(() => { if (document.visibilityState === 'visible') setTick((n) => n + 1); }, 15000);
    return () => clearInterval(t);
  }, []);
  useEffect(() => {
    if (!dep || !pc || !wallet) { setChogs(null); return; }
    let live = true;
    loadChogs(pc, dep, wallet.address).then((r) => live && setChogs(r)).catch((e) => live && setError(String(e.message ?? e)));
    return () => { live = false; };
  }, [dep, pc, wallet, tick]);

  const use = useCallback(async (f: Found, silent = false) => {
    if (!dep) return;
    setError(null);
    try {
      const w = await connectProvider(f.provider, dep.chainId, silent);
      setWallet(w); setPicking(null); remember(f.id);
    } catch (e) { if (!silent) setError(String((e as { shortMessage?: string; message?: string }).shortMessage ?? (e as Error).message ?? e)); }
  }, [dep]);

  // Reconnect quietly to the wallet used last time, if it still shares an account.
  useEffect(() => {
    if (!dep || wallet || devWalletAllowed(dep.chainId)) return;
    const id = lastWallet();
    if (!id) return;
    discoverWallets().then((list) => { const f = list.find((x) => x.id === id); if (f) use(f, true); });
  }, [dep]); // eslint-disable-line react-hooks/exhaustive-deps

  // Follow the wallet: a new account or network in the wallet updates the app; no account disconnects.
  useEffect(() => {
    const p = wallet?.provider;
    if (!p?.on || !dep) return;
    const onAccounts = (a: unknown) => {
      const list = a as string[];
      if (!list?.length) { setWallet(null); remember(null); return; }
      connectProvider(p, dep.chainId, true).then(setWallet).catch(() => setWallet(null));
    };
    const onChain = () => connectProvider(p, dep.chainId, true).then(setWallet).catch(() => setWallet(null));
    p.on('accountsChanged', onAccounts); p.on('chainChanged', onChain);
    return () => { p.removeListener?.('accountsChanged', onAccounts); p.removeListener?.('chainChanged', onChain); };
  }, [wallet?.provider, dep]); // eslint-disable-line react-hooks/exhaustive-deps

  const connect = useCallback(async () => {
    if (!dep) return;
    setError(null);
    if (devWalletAllowed(dep.chainId)) { setWallet(connectDev(dep.chainId)); return; }
    const list = await discoverWallets();
    if (list.length === 1 && list[0].id === 'injected') { await use(list[0]); return; } // a wallet's own in-app browser
    setPicking(list);
  }, [dep, use]);

  if (error && !dep) return <div className="shell"><main><h1>Can't start</h1><p className="muted">{error}</p></main></div>;
  if (!dep || !pc) return <div className="shell"><main><p className="muted">Loading…</p></main></div>;
  return (
    <C.Provider value={{ dep, pc, wallet, chogs, test: isTestDeployment(dep), tick, connect, disconnect: () => { setWallet(null); remember(null); }, refresh, error }}>
      {children}
      {picking && <WalletPicker wallets={picking} onPick={(f) => use(f)} onClose={() => setPicking(null)} error={error} />}
    </C.Provider>
  );
}
