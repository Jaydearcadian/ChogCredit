// Shared by the testnet walks. Stand-in wallets for an extension; never a real key.
// (header from the sale walk)
// The sale on Monad TESTNET: two throwaway wallets (w.json holds the seller, who already has a vault; w2.json the
// buyer). The seller borrows, offers the Chog with its loan and part-payoff, the buyer signs, the seller completes.
// Wallets are stand-ins for an extension. Never a real key. Fund both with a little test MON first.
import { chromium } from 'playwright-core';
import { createPublicClient, createWalletClient, http, defineChain } from 'viem';
import { privateKeyToAccount } from 'viem/accounts';
import { readFileSync, mkdirSync } from 'node:fs';
mkdirSync('shots', { recursive: true });
const URL = process.env.APP_URL ?? 'https://chog-credit.vercel.app';
export { URL };
export const chain = defineChain({ id: 10143, name: 'Monad testnet', nativeCurrency: { name: 'MON', symbol: 'MON', decimals: 18 }, rpcUrls: { default: { http: ['https://testnet-rpc.monad.xyz'] } } });
export const pub = createPublicClient({ chain, transport: http() });
export const keyOf = (f) => { const d = JSON.parse(readFileSync(f, 'utf8')).data; return (Array.isArray(d) ? d[0] : d).private_key; };
export const retry = async (fn) => { for (let i = 0; ; i++) { try { return await fn(); } catch (e) { if (i < 6 && /limited|rate|429|unknown rpc|RPC Request failed/i.test(String(e.message ?? e))) { await new Promise((r) => setTimeout(r, 700 * (i + 1))); continue; } throw e; } } };


export const launch = () => chromium.launch({ executablePath: process.env.CHROMIUM_PATH ?? '/opt/pw-browsers/chromium-1194/chrome-linux/chrome', args: ['--no-sandbox'] });
export async function person(b, file, name) {
  const account = privateKeyToAccount(keyOf(file));
  const wal = createWalletClient({ chain, account, transport: http() });
  const ctx = await b.newContext({ viewport: { width: 390, height: 844 } });
  let authorized = false;
  await ctx.exposeBinding('__rpc', async (_s, method, params) => retry(async () => {
    switch (method) {
      case 'eth_requestAccounts': authorized = true; return [account.address];
      case 'eth_accounts': return authorized ? [account.address] : [];
      case 'eth_chainId': return '0x279f';
      case 'wallet_switchEthereumChain': case 'wallet_addEthereumChain': return null;
      case 'eth_sendTransaction': { const t = params[0]; return wal.sendTransaction({ to: t.to, data: t.data, value: t.value ? BigInt(t.value) : 0n }); }
      case 'eth_signTypedData_v4': { const d = JSON.parse(params[1]); const { EIP712Domain, ...types } = d.types; return account.signTypedData({ domain: d.domain, types, primaryType: d.primaryType, message: d.message }); }
      default: return pub.request({ method, params });
    }
  }));
  await ctx.addInitScript(() => { window.ethereum = { request: ({ method, params }) => window.__rpc(method, params ?? []), on() {}, removeListener() {} }; });
  const p = await ctx.newPage();
  p.on('pageerror', (e) => console.log(name, 'pageerror', e.message));
  return { p, account, name, main: p.locator('main') };
}
