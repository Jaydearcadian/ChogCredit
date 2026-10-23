// The sale on Monad TESTNET: two throwaway wallets (w.json holds the seller, who already has a vault; w2.json the
// buyer). The seller borrows, offers the Chog with its loan and part-payoff, the buyer signs, the seller completes.
// Wallets are stand-ins for an extension. Never a real key. Fund both with a little test MON first.
import { chromium } from 'playwright-core';
import { createPublicClient, createWalletClient, http, defineChain } from 'viem';
import { privateKeyToAccount } from 'viem/accounts';
import { readFileSync, mkdirSync } from 'node:fs';
mkdirSync('shots', { recursive: true });
const URL = process.env.APP_URL ?? 'https://chog-credit.vercel.app';
const chain = defineChain({ id: 10143, name: 'Monad testnet', nativeCurrency: { name: 'MON', symbol: 'MON', decimals: 18 }, rpcUrls: { default: { http: ['https://testnet-rpc.monad.xyz'] } } });
const pub = createPublicClient({ chain, transport: http() });
const keyOf = (f) => { const d = JSON.parse(readFileSync(f, 'utf8')).data; return (Array.isArray(d) ? d[0] : d).private_key; };
const retry = async (fn) => { for (let i = 0; ; i++) { try { return await fn(); } catch (e) { if (i < 6 && /limited|rate|429|unknown rpc|RPC Request failed/i.test(String(e.message ?? e))) { await new Promise((r) => setTimeout(r, 700 * (i + 1))); continue; } throw e; } } };

const b = await chromium.launch({ executablePath: process.env.CHROMIUM_PATH ?? '/opt/pw-browsers/chromium-1194/chrome-linux/chrome', args: ['--no-sandbox'] });
async function person(file, name) {
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
const seller = await person('w.json', 'seller');
const buyer = await person('w2.json', 'buyer');
const final = (x) => x.p.getByText('Final on Monad.').first().waitFor({ timeout: 90000 });
const shot = (x, n) => x.p.screenshot({ path: `shots/ts-${n}.png` });
const step = async (x, s, fn) => { const t = Date.now(); try { await fn(); console.log('ok  ', x.name, s, `${((Date.now() - t) / 1000).toFixed(1)}s`); } catch (e) { console.log('FAIL', x.name, s, String(e.message).split('\n')[0]); await shot(x, 'fail'); console.log((await x.main.innerText().catch(() => '')).slice(0, 500)); await b.close(); process.exit(1); } };
const connect = async (x, path = '') => { await x.p.goto(URL + path); await x.p.getByRole('button', { name: /^Connect( wallet)?$/ }).first().click(); await x.p.getByRole('button', { name: 'Browser Wallet' }).click({ timeout: 5000 }).catch(() => {}); };

let offerLink, signedLink;
await step(seller, 'connect and borrow 100 USDC', async () => {
  await connect(seller); await seller.p.getByRole('button', { name: /In its vault/ }).first().click({ timeout: 40000 });
  await seller.main.getByRole('link', { name: 'Borrow', exact: true }).click({ timeout: 40000 });
  await seller.p.getByLabel('How much do you want to borrow?', { exact: true }).fill('100'); await seller.p.getByRole('button', { name: 'Borrow 100.00 USDC' }).click(); await final(seller);
});
await step(seller, 'write the offer with a loan and part-payoff', async () => {
  await seller.main.getByRole('link', { name: 'Back to account' }).click();
  await seller.p.getByRole('link', { name: 'Sell', exact: true }).click();
  await seller.p.getByRole('heading', { name: 'Sell this Chog with its loan' }).waitFor({ timeout: 40000 });
  await seller.p.getByLabel('Price the buyer pays').fill('500'); await seller.p.getByLabel("Buyer's wallet").fill(buyer.account.address);
  await seller.p.getByRole('switch', { name: 'Pay off part of the loan from the price' }).click(); await seller.p.getByLabel('Goes to repay the loan', { exact: true }).fill('40');
  await seller.p.getByRole('button', { name: 'Ask the buyer to sign' }).click(); offerLink = await seller.p.locator('.share code').first().innerText(); await shot(seller, '1-offer');
});
await step(buyer, 'review, get test USDC, approve, sign', async () => {
  await buyer.p.goto(offerLink); await buyer.p.getByRole('button', { name: /^Connect( wallet)?$/ }).first().click(); await buyer.p.getByRole('button', { name: 'Browser Wallet' }).click({ timeout: 5000 }).catch(() => {});
  await buyer.p.getByRole('heading', { name: 'Buy a Chog with its loan' }).waitFor({ timeout: 40000 }); await shot(buyer, '2-review');
  await buyer.p.getByRole('button', { name: 'Get test USDC' }).click(); await buyer.p.getByRole('button', { name: /Allow 500.00 USDC/ }).waitFor({ timeout: 90000 });
  await buyer.p.waitForTimeout(2500); await buyer.p.getByRole('button', { name: /Allow 500.00 USDC/ }).click();
  await buyer.p.getByRole('button', { name: /Sign these terms/ }).waitFor({ timeout: 90000 }); await buyer.p.waitForTimeout(800);
  await buyer.p.getByRole('button', { name: /Sign these terms/ }).click(); signedLink = await buyer.p.locator('.share code').first().innerText(); await shot(buyer, '3-signed');
});
await step(seller, 'every check passes, complete the sale', async () => {
  await seller.p.goto(signedLink); await seller.p.getByRole('button', { name: /^Connect( wallet)?$/ }).first().click(); await seller.p.getByRole('button', { name: 'Browser Wallet' }).click({ timeout: 5000 }).catch(() => {});
  await seller.p.getByRole('heading', { name: 'The buyer signed' }).waitFor({ timeout: 40000 }); await seller.p.waitForTimeout(1500); await shot(seller, '4-checks');
  const go = seller.p.getByRole('button', { name: /Complete sale/ }); await go.waitFor(); if (!(await go.isEnabled())) throw new Error('a check failed');
  await go.click(); await seller.p.getByRole('heading', { name: /has a new keeper/ }).waitFor({ timeout: 90000 }); await final(seller); await shot(seller, '5-sold');
});
await step(buyer, 'the buyer now keeps the Chog with the loan', async () => {
  await buyer.p.goto(URL + '/pick'); await buyer.p.getByRole('button', { name: /^Connect( wallet)?$/ }).first().click().catch(() => {}); await buyer.p.getByRole('button', { name: 'Browser Wallet' }).click({ timeout: 5000 }).catch(() => {});
  await buyer.p.getByRole('button', { name: /In its vault/ }).first().click({ timeout: 40000 });
  await buyer.main.getByRole('link', { name: 'Repay', exact: true }).waitFor({ timeout: 40000 }); await buyer.p.waitForTimeout(800); await shot(buyer, '6-buyer-account');
});
console.log('sold on testnet: seller', seller.account.address, 'buyer', buyer.account.address);
await b.close();
