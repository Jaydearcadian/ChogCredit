// Looking around with no wallet at all: landing, the Chogs list, a read-only account, Activity, and the connect gate.
// Run after flow.mjs or sell.mjs so at least one Chog has a vault.
import { chromium } from 'playwright-core';
import { mkdirSync } from 'node:fs';
mkdirSync('shots', { recursive: true });
const b = await chromium.launch({ executablePath: process.env.CHROMIUM_PATH ?? '/opt/pw-browsers/chromium-1194/chrome-linux/chrome', args: ['--no-sandbox'] });
const results = [];
for (const [name, viewport] of [['phone', { width: 390, height: 844 }], ['desktop', { width: 1440, height: 900 }]]) {
  const p = await (await b.newContext({ viewport })).newPage();
  const errs = []; p.on('pageerror', (e) => errs.push(e.message));
  const shot = (n) => p.screenshot({ path: `shots/b-${name}-${n}.png` });
  const main = p.locator('main');
  const step = async (s, fn) => { try { await fn(); console.log('ok  ', name, s); } catch (e) { console.log('FAIL', name, s, String(e.message).split('\n')[0]); await shot('fail'); console.log((await main.innerText().catch(() => '')).slice(0, 300)); await b.close(); process.exit(1); } };
  await step('landing has a way in without a wallet', async () => { await p.goto('http://127.0.0.1:5173/'); await p.getByRole('link', { name: 'Look around first' }).click(); });
  await step('Chogs list reads vaults from the chain', async () => { await p.getByRole('heading', { name: 'Chogs with a vault' }).waitFor(); await main.locator('.chip').first().waitFor({ timeout: 15000 }); await p.waitForTimeout(700); await shot('explore'); });
  await step('a read-only account', async () => { await main.locator('button.card').first().click(); await p.getByText('Read-only, straight from the chain.').waitFor({ timeout: 15000 }); await main.getByRole('button', { name: 'Connect to open your own vault' }).waitFor(); await p.waitForTimeout(800); await shot('account'); });
  await step('Activity without a wallet', async () => { await p.getByRole('link', { name: 'Activity', exact: true }).click(); await p.locator('table').waitFor({ timeout: 20000 }); await shot('activity'); });
  await step('Borrow asks to connect, nothing else', async () => { await p.getByRole('link', { name: 'Borrow', exact: true }).click(); await p.getByText(/Connect a wallet to/).waitFor(); await shot('gate'); });
  await step('Connect opens RainbowKit', async () => { await main.getByRole('button', { name: 'Connect wallet' }).click(); await p.getByRole('dialog').waitFor({ timeout: 8000 }); await p.waitForTimeout(600); await shot('rainbowkit'); });
  results.push([name, errs]);
}
console.log('errors:', JSON.stringify(results));
await b.close();
