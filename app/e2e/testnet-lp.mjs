// Pool-position collateral on Monad TESTNET: get a test position, add it, borrow, see it locked, repay, take it back.
// Drives the app on Monad TESTNET (hosted, or APP_URL) with a throwaway key behind a minimal EIP-1193 stand-in.
// Needs w.json from `cast wallet new --json` in the working directory, funded with a little test MON. Never a real key.
import { chromium } from 'playwright-core';
import { createPublicClient, createWalletClient, http, defineChain } from 'viem';
import { privateKeyToAccount } from 'viem/accounts';
import { readFileSync, mkdirSync } from 'node:fs';
mkdirSync('shots', { recursive: true });
const w = JSON.parse(readFileSync('w.json', 'utf8')).data; const key = (Array.isArray(w) ? w[0] : w).private_key;
const chain = defineChain({ id: 10143, name: 'Monad testnet', nativeCurrency: { name: 'MON', symbol: 'MON', decimals: 18 }, rpcUrls: { default: { http: ['https://testnet-rpc.monad.xyz'] } } });
const account = privateKeyToAccount(key);
const pub = createPublicClient({ chain, transport: http() });
const wal = createWalletClient({ chain, account, transport: http() });
const URL = process.env.APP_URL ?? 'https://chog-credit-jaydearcadians-projects.vercel.app';

const b = await chromium.launch({ executablePath: process.env.CHROMIUM_PATH ?? '/opt/pw-browsers/chromium-1194/chrome-linux/chrome', args: ['--no-sandbox'] });
const ctx = await b.newContext({ viewport: { width: 390, height: 844 } });
let authorized = false;
// The public RPC allows about 15 requests a second; this stand-in wallet retries when it is refused, as a real wallet's own RPC would not need to.
const retry = async (fn) => { for (let i = 0; ; i++) { try { return await fn(); } catch (e) { if (i < 6 && /limited|rate|429|unknown rpc/i.test(String(e.message ?? e))) { await new Promise((r) => setTimeout(r, 700 * (i + 1))); continue; } throw e; } } };
await ctx.exposeBinding('__rpc', async (_s, method, params) => retry(async () => {
  switch (method) {
    case 'eth_requestAccounts': authorized = true; return [account.address];
    case 'eth_accounts': return authorized ? [account.address] : []; // like a real wallet: nothing until the user connects
    case 'eth_chainId': return '0x279f';
    case 'wallet_switchEthereumChain': case 'wallet_addEthereumChain': return null;
    case 'eth_sendTransaction': { const t = params[0]; try { return await wal.sendTransaction({ to: t.to, data: t.data, value: t.value ? BigInt(t.value) : 0n, gas: t.gas ? BigInt(t.gas) : undefined }); } catch (e) { console.log('SENDFAIL to', t.to, 'sel', String(t.data).slice(0, 10), 'gas', t.gas, '|', String(e.shortMessage ?? e.message).slice(0, 200), '|', String(e.cause?.message ?? '').slice(0, 300)); throw e; } }
    case 'eth_signTypedData_v4': { const d = JSON.parse(params[1]); const { EIP712Domain, ...types } = d.types; return account.signTypedData({ domain: d.domain, types, primaryType: d.primaryType, message: d.message }); }
    default: return pub.request({ method, params });
  }
}));
await ctx.addInitScript(() => { window.ethereum = { request: ({ method, params }) => window.__rpc(method, params ?? []), on() {}, removeListener() {} }; });
const p = await ctx.newPage();
const errs = []; p.on('pageerror', (e) => errs.push(e.message));
p.on('console', (m) => { if (m.type() !== 'log') errs.push('console ' + m.type() + ': ' + m.text().slice(0, 300)); });
p.on('requestfailed', (r) => errs.push('reqfail ' + r.url().slice(0, 80) + ' ' + r.failure()?.errorText));
p.on('response', async (r) => { if (r.url().includes('monad') && r.status() !== 200) errs.push('rpc ' + r.status() + ' ' + (await r.text().catch(() => '')).slice(0, 200)); else if (r.url().includes('monad')) { const t = await r.text().catch(() => ''); if (t.includes('error')) errs.push('rpcerr ' + t.slice(0, 300)); } });
const main = p.locator('main');
const final = () => p.getByText('Final on Monad.').first().waitFor({ timeout: 90000 });
const shot = (n) => p.screenshot({ path: `shots/${n}.png` });
const t0 = Date.now();
const step = async (name, fn) => { const s = Date.now(); try { await fn(); console.log('ok  ', name, `${((Date.now() - s) / 1000).toFixed(1)}s`); } catch (e) { console.log('ERRS', JSON.stringify(errs.filter((x) => x.startsWith('rpcerr') || x.startsWith('rpc ')).slice(-4))); console.log('FAIL', name, String(e.message).split('\n')[0]); await shot('fail'); console.log((await main.innerText().catch(() => '')).slice(0, 500)); console.log(errs); await b.close(); process.exit(1); } };

await step('connect', async () => { await p.goto(URL); await p.getByRole('button', { name: 'Connect wallet' }).click(); await p.getByRole('button', { name: 'Browser Wallet' }).click({ timeout: 5000 }).catch(() => {}); await p.getByRole('heading', { name: 'Pick your Chog' }).waitFor({ timeout: 30000 }); });
await step('get a test Chog and open its vault (or reuse the one from an earlier run)', async () => {
  const had = p.getByRole('button', { name: /In its vault/ }).first();
  await had.or(p.getByRole('button', { name: /Get a test Chog/ })).first().waitFor({ timeout: 60000 });
  if (await had.isVisible()) await had.click();
  else {
    await p.getByRole('button', { name: /Get a test Chog/ }).click();
    await p.getByRole('button', { name: /No vault yet/ }).first().click({ timeout: 90000 });
    await p.getByRole('button', { name: 'Open vault' }).click();
    await p.getByRole('heading', { name: 'Vault opened.' }).waitFor({ timeout: 90000 });
    await p.getByRole('button', { name: 'No thanks' }).click().catch(() => {});
  }
  await main.getByRole('link', { name: 'Add assets' }).first().waitFor({ timeout: 60000 }); await p.waitForTimeout(800); await shot('2-account');
});
await step('get a test position and see what it counts for', async () => {
  await main.getByRole('link', { name: 'Add assets' }).first().click(); await p.getByRole('tab', { name: 'Pool position' }).click();
  await p.getByRole('button', { name: 'Get a test position' }).click(); await p.getByText(/Counts for/).first().waitFor({ timeout: 120000 }); await p.waitForTimeout(600); await shot('lp-1-pick');
});
await step('add it to the vault', async () => {
  await p.getByRole('button', { name: /^Add position #/ }).click(); await Promise.race([final(), p.getByText("Didn't go through").waitFor({ timeout: 90000 }).then(async () => { throw new Error('TX FAILED: ' + (await p.locator('.banner.danger').innerText()).replace(/\n/g, ' | ')); })]);
  await p.getByRole('link', { name: 'Back to account' }).click(); await p.getByText('Pool positions in the vault').waitFor({ timeout: 60000 }); await p.waitForTimeout(700); await shot('lp-2-account');
});
await step('borrow against it', async () => {
  await main.getByRole('link', { name: 'Borrow', exact: true }).click({ timeout: 30000 });
  await p.getByLabel('How much do you want to borrow?', { exact: true }).fill('25'); await p.getByRole('button', { name: 'Borrow 25.00 USDC' }).click(); await final();
  await main.getByRole('link', { name: 'Back to account' }).click(); await main.getByRole('link', { name: 'Repay', exact: true }).waitFor({ timeout: 60000 });
});
await step('the position cannot leave while it backs the loan', async () => {
  await main.getByRole('link', { name: 'Withdraw', exact: true }).click(); await p.getByText('It backs your loan. Repay first.').first().waitFor({ timeout: 60000 }); await shot('lp-3-locked');
});
await step('repay, then take it back', async () => {
  await main.getByRole('link', { name: 'Cancel' }).click(); await main.getByRole('link', { name: 'Repay', exact: true }).click();
  await p.getByRole('button', { name: /Repay all/ }).click(); await p.getByText('Debt-free. Look at you.').waitFor({ timeout: 90000 }); await final();
  await main.getByRole('link', { name: 'Back to account' }).click(); await main.getByRole('link', { name: 'Withdraw', exact: true }).click();
  await p.getByRole('button', { name: /^Withdraw position #/ }).first().click(); await final();
});
console.log('total', ((Date.now() - t0) / 1000).toFixed(0), 's; errors:', errs);
await b.close();
