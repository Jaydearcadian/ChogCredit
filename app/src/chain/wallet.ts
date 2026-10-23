import { createPublicClient, createWalletClient, custom, http, type Account, type Address, type PublicClient, type WalletClient } from 'viem';
import { privateKeyToAccount } from 'viem/accounts';
import { chainFor } from './config';

export type Wallet = { address: Address; client: WalletClient; account: Account | Address; kind: 'injected' | 'dev'; provider?: Eip1193 };

export type Eip1193 = {
  request(a: { method: string; params?: unknown[] }): Promise<unknown>;
  on?(event: string, fn: (...a: unknown[]) => void): void;
  removeListener?(event: string, fn: (...a: unknown[]) => void): void;
};
/** A wallet the browser offers, found through EIP-6963 (every installed wallet announces itself) or the legacy
 *  window.ethereum slot. */
export type Found = { id: string; name: string; icon: string | null; provider: Eip1193 };

const legacy = () => (window as unknown as { ethereum?: Eip1193 }).ethereum;

export function discoverWallets(waitMs = 350): Promise<Found[]> {
  return new Promise((resolve) => {
    const found = new Map<string, Found>();
    const onAnnounce = (e: Event) => {
      const d = (e as CustomEvent<{ info: { uuid: string; name: string; icon: string; rdns: string }; provider: Eip1193 }>).detail;
      if (d?.provider && !found.has(d.info.rdns)) found.set(d.info.rdns, { id: d.info.rdns, name: d.info.name, icon: d.info.icon, provider: d.provider });
    };
    window.addEventListener('eip6963:announceProvider', onAnnounce);
    window.dispatchEvent(new Event('eip6963:requestProvider'));
    setTimeout(() => {
      window.removeEventListener('eip6963:announceProvider', onAnnounce);
      const list = [...found.values()];
      const l = legacy();
      if (list.length === 0 && l) list.push({ id: 'injected', name: 'Browser wallet', icon: null, provider: l });
      resolve(list);
    }, waitMs);
  });
}

export const isMobile = () => /Android|iPhone|iPad|iPod/i.test(navigator.userAgent);

/** Links that open this page inside a wallet app's own browser, where the wallet is injected. */
export function openInWalletLinks(url = location.href) {
  const noProto = url.replace(/^https?:\/\//, '');
  return [
    { name: 'MetaMask', href: `https://metamask.app.link/dapp/${noProto}` },
    { name: 'Phantom', href: `https://phantom.app/ul/browse/${encodeURIComponent(url)}?ref=${encodeURIComponent(location.origin)}` },
    { name: 'Coinbase Wallet', href: `https://go.cb-w.com/dapp?cb_url=${encodeURIComponent(url)}` },
    { name: 'Trust Wallet', href: `https://link.trustwallet.com/open_url?coin_id=60&url=${encodeURIComponent(url)}` },
  ];
}
export const installLinks = [
  { name: 'MetaMask', href: 'https://metamask.io/download/' },
  { name: 'Rabby', href: 'https://rabby.io/' },
  { name: 'Phantom', href: 'https://phantom.com/download' },
];

/** Anvil's well-known test keys. Dev builds only, local chain only, and only when the URL asks (?dev=1 is the first
 *  account, ?dev=2 the second, so a seller and a buyer can be played in two tabs). Never on a live network. */
const ANVIL_KEYS = [
  '0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80',
  '0x59c6995e998f97a5a0044966f0945389dc9e86dae88c7a8412f4603b6b78690d',
] as const;
export const devWalletAllowed = (chainId: number) => {
  if (!import.meta.env.DEV || chainId !== 31337) return false;
  try {
    const q = new URLSearchParams(location.search).get('dev');
    if (q !== null) sessionStorage.setItem('chog-credit:dev', q === '2' ? '2' : '1'); // sticky for this tab: links drop the query
    return sessionStorage.getItem('chog-credit:dev') !== null;
  } catch { return new URLSearchParams(location.search).has('dev'); }
};

/**
 * A transport for public RPCs that limit requests per second (Monad's allow about 15, and count every call in a
 * JSON-RPC batch). Requests go out at most ten a second and a rate-limited request waits and tries again, so a screen
 * never hangs on an answer the node refused.
 */
function throttled(url: string) {
  const perSecond = 10;
  let sent: number[] = [];
  let id = 0;
  const slot = async () => {
    for (;;) {
      const now = Date.now();
      sent = sent.filter((t) => now - t < 1000);
      if (sent.length < perSecond) { sent.push(now); return; }
      await new Promise((r) => setTimeout(r, 1000 - (now - sent[0]) + 5));
    }
  };
  return custom({
    async request({ method, params }: { method: string; params?: unknown }) {
      for (let attempt = 0; ; attempt++) {
        await slot();
        const res = await fetch(url, { method: 'POST', headers: { 'content-type': 'application/json' }, body: JSON.stringify({ jsonrpc: '2.0', id: ++id, method, params }) });
        const limited = res.status === 429;
        const body = limited ? null : ((await res.json()) as { result?: unknown; error?: { code: number; message: string; data?: unknown } });
        if (limited || /limited to \d+\/sec|rate limit/i.test(body?.error?.message ?? '')) {
          if (attempt < 6) { await new Promise((r) => setTimeout(r, 400 * (attempt + 1))); continue; }
        }
        if (!body) throw new Error('The network is busy. Try again in a moment.');
        if (body.error) throw Object.assign(new Error(body.error.message), body.error);
        return body.result;
      }
    },
  });
}

/**
 * Reads. On Monad, contract reads made together are folded into one Multicall3 call and every request goes through
 * the throttle above. A local chain has neither limit nor Multicall3, so there it batches JSON-RPC instead.
 */
export function publicClientFor(chainId: number): PublicClient {
  const chain = chainFor(chainId);
  if (chainId === 31337) return createPublicClient({ chain, transport: http(undefined, { batch: true }) });
  return createPublicClient({ chain, batch: { multicall: { wait: 24, batchSize: 65_536 } }, transport: throttled(chain.rpcUrls.default.http[0]) });
}

export async function connectProvider(eth: Eip1193, chainId: number, silent = false): Promise<Wallet> {
  const chain = chainFor(chainId);
  const accounts = (await eth.request({ method: silent ? 'eth_accounts' : 'eth_requestAccounts' })) as Address[];
  if (!accounts?.length) throw new Error('The wallet did not share an account.');
  const hex = `0x${chainId.toString(16)}`;
  try {
    await eth.request({ method: 'wallet_switchEthereumChain', params: [{ chainId: hex }] });
  } catch {
    await eth.request({
      method: 'wallet_addEthereumChain',
      params: [{ chainId: hex, chainName: chain.name, nativeCurrency: chain.nativeCurrency, rpcUrls: chain.rpcUrls.default.http }],
    });
  }
  const client = createWalletClient({ chain, transport: custom(eth), account: accounts[0] });
  return { address: accounts[0], client, account: accounts[0], kind: 'injected', provider: eth };
}

export function connectDev(chainId: number): Wallet {
  let i = 0;
  try { i = sessionStorage.getItem('chog-credit:dev') === '2' ? 1 : 0; } catch { /* default to the first key */ }
  const account = privateKeyToAccount(ANVIL_KEYS[i]);
  const client = createWalletClient({ account, chain: chainFor(chainId), transport: http() });
  return { address: account.address, client, account, kind: 'dev' };
}
