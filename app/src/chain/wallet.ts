import { createPublicClient, createWalletClient, custom, http, type Account, type Address, type PublicClient, type WalletClient } from 'viem';
import { privateKeyToAccount } from 'viem/accounts';
import { chainFor } from './config';

export type Wallet = { address: Address; client: WalletClient; account: Account | Address; kind: 'injected' | 'dev' };

type Eip1193 = { request(a: { method: string; params?: unknown[] }): Promise<unknown> };
const injected = () => (window as unknown as { ethereum?: Eip1193 }).ethereum;

export const hasInjected = () => !!injected();

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

export function publicClientFor(chainId: number): PublicClient {
  return createPublicClient({ chain: chainFor(chainId), transport: http(undefined, { batch: true }) });
}

export async function connectInjected(chainId: number): Promise<Wallet> {
  const eth = injected();
  if (!eth) throw new Error('No wallet found in this browser.');
  const chain = chainFor(chainId);
  const accounts = (await eth.request({ method: 'eth_requestAccounts' })) as Address[];
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
  return { address: accounts[0], client, account: accounts[0], kind: 'injected' };
}

export function connectDev(chainId: number): Wallet {
  let i = 0;
  try { i = sessionStorage.getItem('chog-credit:dev') === '2' ? 1 : 0; } catch { /* default to the first key */ }
  const account = privateKeyToAccount(ANVIL_KEYS[i]);
  const client = createWalletClient({ account, chain: chainFor(chainId), transport: http() });
  return { address: account.address, client, account, kind: 'dev' };
}
