import { createContext, useCallback, useContext, useEffect, useMemo, useState, type ReactNode } from 'react';
import type { PublicClient } from 'viem';
import { loadChogs, type ChogRow } from './chain/api';
import { isTestDeployment, loadDeployment, type Deployment } from './chain/config';
import { connectDev, connectInjected, devWalletAllowed, publicClientFor, type Wallet } from './chain/wallet';

type Ctx = {
  dep: Deployment; pc: PublicClient; wallet: Wallet | null; chogs: ChogRow[] | null; test: boolean; tick: number;
  connect(): Promise<void>; disconnect(): void; refresh(): void; error: string | null;
};
const C = createContext<Ctx | null>(null);
export const useApp = () => { const v = useContext(C); if (!v) throw new Error('outside provider'); return v; };

export function AppProvider({ children }: { children: ReactNode }) {
  const [dep, setDep] = useState<Deployment | null>(null);
  const [wallet, setWallet] = useState<Wallet | null>(null);
  const [chogs, setChogs] = useState<ChogRow[] | null>(null);
  const [tick, setTick] = useState(0);
  const [error, setError] = useState<string | null>(null);

  useEffect(() => { loadDeployment().then(setDep).catch((e) => setError(String(e.message ?? e))); }, []);
  const pc = useMemo(() => (dep ? publicClientFor(dep.chainId) : null), [dep]);

  const refresh = useCallback(() => setTick((t) => t + 1), []);
  useEffect(() => {
    if (!dep || !pc || !wallet) { setChogs(null); return; }
    let live = true;
    loadChogs(pc, dep, wallet.address).then((r) => live && setChogs(r)).catch((e) => live && setError(String(e.message ?? e)));
    return () => { live = false; };
  }, [dep, pc, wallet, tick]);

  const connect = useCallback(async () => {
    if (!dep) return;
    setError(null);
    try {
      setWallet(devWalletAllowed(dep.chainId) ? connectDev(dep.chainId) : await connectInjected(dep.chainId));
    } catch (e) { setError(String((e as Error).message ?? e)); }
  }, [dep]);

  if (error && !dep) return <div className="shell"><main><h1>Can't start</h1><p className="muted">{error}</p></main></div>;
  if (!dep || !pc) return <div className="shell"><main><p className="muted">Loading…</p></main></div>;
  return (
    <C.Provider value={{ dep, pc, wallet, chogs, test: isTestDeployment(dep), tick, connect, disconnect: () => setWallet(null), refresh, error }}>
      {children}
    </C.Provider>
  );
}
