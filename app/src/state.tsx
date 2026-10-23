import { createContext, lazy, Suspense, useCallback, useContext, useEffect, useMemo, useRef, useState, type ReactNode } from 'react';
import type { PublicClient } from 'viem';
import { loadChogs, loadPublicChogs, type ChogRow } from './chain/api';
import { isTestDeployment, loadDeployment, type Deployment } from './chain/config';
import { connectDev, devWalletAllowed, isMobile, publicClientFor, type Wallet } from './chain/wallet';
import { WalletPicker } from './components/picker';
import { walletConnectEnabled } from './walletconfig';
import type { WalletBridge } from './web3';

const WalletLayer = lazy(() => import('./web3'));

type Ctx = {
  dep: Deployment; pc: PublicClient; wallet: Wallet | null; chogs: ChogRow[] | null; test: boolean; tick: number;
  connect(): void; disconnect(): void; openAccount?: () => void; refresh(): void; error: string | null;
  /** Looking around without a wallet: every Chog with a vault, and the one being viewed. */
  publicChogs: { id: number; escrowed: boolean }[] | null; viewing: number | null; setViewing(id: number): void;
};
const C = createContext<Ctx | null>(null);
export const useApp = () => { const v = useContext(C); if (!v) throw new Error('outside provider'); return v; };

const VIEW = 'chog-credit:viewing';
const readView = () => { try { const v = sessionStorage.getItem(VIEW); return v ? Number(v) : null; } catch { return null; } };

/** Loads the deployment, then wallets (RainbowKit on wagmi), then the app state. */
export function Root({ children }: { children: ReactNode }) {
  const [dep, setDep] = useState<Deployment | null>(null);
  const [error, setError] = useState<string | null>(null);
  useEffect(() => { loadDeployment().then(setDep).catch((e) => setError(String(e.message ?? e))); }, []);
  if (error) return <div className="shell"><main><h1>Can't start</h1><p className="muted">{error}</p></main></div>;
  if (!dep) return <div className="shell"><main><p className="muted">Loading…</p></main></div>;
  return <AppProvider dep={dep}>{children}</AppProvider>;
}

function AppProvider({ dep, children }: { dep: Deployment; children: ReactNode }) {
  const pc = useMemo(() => publicClientFor(dep.chainId), [dep]);
  const [dev, setDev] = useState<Wallet | null>(null);
  const [chogs, setChogs] = useState<ChogRow[] | null>(null);
  const [publicChogs, setPublicChogs] = useState<{ id: number; escrowed: boolean }[] | null>(null);
  const [viewing, setViewingState] = useState<number | null>(readView());
  const [tick, setTick] = useState(0);
  const [error, setError] = useState<string | null>(null);
  const [deepLinks, setDeepLinks] = useState(false);
  const followUp = useRef<ReturnType<typeof setTimeout>>();

  // The wallet layer (RainbowKit on wagmi) loads after first paint and reports in through this bridge.
  const [bridge, setBridge] = useState<WalletBridge | null>(null);
  const wantConnect = useRef(false);
  const wallet = dev ?? bridge?.wallet ?? null;

  /** Re-read now and once more a moment later: a public node can answer from a block before your transaction. */
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
    if (!wallet) { setChogs(null); return; }
    let live = true;
    loadChogs(pc, dep, wallet.address).then((r) => live && setChogs(r)).catch((e) => live && setError(String(e.message ?? e)));
    return () => { live = false; };
  }, [dep, pc, wallet, tick]);
  useEffect(() => {
    let live = true;
    loadPublicChogs(pc, dep).then((r) => live && setPublicChogs(r)).catch(() => live && setPublicChogs([]));
    return () => { live = false; };
  }, [dep, pc, tick]);

  // Testnet prices follow the real market. The hosted keeper writes only when the price has moved, so this is a cheap nudge, at most every ten minutes per browser.
  useEffect(() => {
    if (dep.chainId !== 10143) return;
    try {
      const last = Number(localStorage.getItem('chog-credit:keeper') ?? 0);
      if (Date.now() - last < 10 * 60_000) return;
      localStorage.setItem('chog-credit:keeper', String(Date.now()));
    } catch { /* storage can be blocked; ping anyway */ }
    fetch('/api/price-keeper').catch(() => undefined);
  }, [dep.chainId]);

  const connect = useCallback(() => {
    setError(null);
    if (devWalletAllowed(dep.chainId)) { setDev(connectDev(dep.chainId)); return; }
    const injected = !!(window as unknown as { ethereum?: unknown }).ethereum;
    // A phone browser with no wallet and no WalletConnect: offer to open the app inside a wallet app instead.
    if (isMobile() && !injected && !walletConnectEnabled) { setDeepLinks(true); return; }
    if (bridge?.openConnect) bridge.openConnect(); else wantConnect.current = true; // still loading: open it on arrival
  }, [dep.chainId, bridge]);
  useEffect(() => {
    if (wantConnect.current && bridge?.openConnect) { wantConnect.current = false; bridge.openConnect(); }
  }, [bridge]);

  const setViewing = useCallback((id: number) => { setViewingState(id); try { sessionStorage.setItem(VIEW, String(id)); } catch { /* fine */ } }, []);

  return (
    <C.Provider value={{
      dep, pc, wallet, chogs, test: isTestDeployment(dep), tick, connect, refresh, error, publicChogs, viewing, setViewing,
      disconnect: () => { setDev(null); bridge?.disconnect(); }, openAccount: bridge?.openAccount,
    }}>
      {children}
      <Suspense fallback={null}><WalletLayer dep={dep} onBridge={setBridge} /></Suspense>
      {deepLinks && <WalletPicker wallets={[]} onPick={() => undefined} onClose={() => setDeepLinks(false)} error={null} />}
    </C.Provider>
  );
}
