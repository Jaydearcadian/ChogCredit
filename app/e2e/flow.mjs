// End-to-end walk through the money flow on a fresh local chain: connect, open a vault, add, borrow, repay, release.
// Run `e2e/reset.sh` first, start `npm run dev`, then `node e2e/flow.mjs`. Screenshots go to e2e/shots (ignored by git).
import { chromium } from 'playwright-core';
const shot = (p, n) => p.screenshot({ path: `shots/${n}.png` });
const b = await chromium.launch({ executablePath: process.env.CHROMIUM_PATH ?? '/opt/pw-browsers/chromium-1194/chrome-linux/chrome', args: ['--no-sandbox'] });
const p = await (await b.newContext({ viewport: { width: 390, height: 844 } })).newPage();
const errs = []; p.on('console', (m) => m.type() === 'error' && errs.push(m.text())); p.on('pageerror', (e) => errs.push('PAGEERR ' + e.message));
const step = async (name, fn) => { try { await fn(); console.log('ok  ', name); } catch (e) { console.log('FAIL', name, String(e.message).split('\n')[0]); await shot(p, 'fail-' + name.replace(/\W+/g, '-')); console.log((await p.locator('main').innerText().catch(() => '')).slice(0, 400)); console.log('errs', errs.slice(0,4)); throw e; } };
import { mkdirSync } from 'node:fs'; mkdirSync('shots', { recursive: true });
await step('connect', async () => { await p.goto('http://127.0.0.1:5173/?dev=1'); await p.getByRole('button', { name: 'Connect wallet' }).waitFor(); await shot(p, '01-connect'); await p.getByRole('button', { name: 'Connect wallet' }).click(); });
await step('pick', async () => { await p.getByRole('heading', { name: 'Pick your Chog' }).waitFor(); await p.getByText('No vault yet').first().waitFor(); await shot(p, '02-pick'); });
await step('open vault', async () => { const card = p.locator('.card', { hasText: 'No vault yet' }).first(); await card.getByRole('button', { name: 'Select' }).click(); await p.getByRole('heading', { name: 'Open a vault' }).waitFor(); await shot(p, '03-open'); await p.getByRole('button', { name: 'Open vault' }).click(); await p.getByRole('heading', { name: 'Vault opened.' }).waitFor({ timeout: 30000 }); await shot(p, '04-opened'); });
await step('account empty', async () => { await p.getByRole('link', { name: 'Look around first' }).click(); await p.getByText('Nothing yet').waitFor(); await shot(p, '05-account-empty'); });
await step('faucet + add', async () => {
  await p.getByRole('link', { name: 'Add assets' }).first().click();
  await p.getByRole('button', { name: 'Get test tokens' }).click();
  await p.getByText(/wallet 100,000.00 WMON/).waitFor({ timeout: 40000 });
  await shot(p, '06-add-faucet');
  await p.getByRole('button', { name: 'MAX' }).click();
  await p.getByText('After adding').waitFor();
  await shot(p, '07-add-filled');
  await p.getByRole('button', { name: /^Add .* WMON$/ }).click();
  await p.getByText('Done and final on Monad.').waitFor({ timeout: 40000 });
  await shot(p, '08-add-done');
});
await step('account has funds', async () => { await p.getByRole('link', { name: 'Back to account' }).click(); await p.getByText('In the vault').waitFor(); await p.getByText('WMON').first().waitFor(); await shot(p, '09-account'); });
await step('borrow', async () => {
  await p.getByRole('link', { name: 'Borrow', exact: true }).first().click();
  await p.getByRole('heading', { name: 'Borrow USDC' }).waitFor();
  await p.getByLabel(/Amount/).fill('100');
  await p.getByText('Health after').waitFor();
  await shot(p, '10-borrow');
  await p.getByRole('button', { name: 'Borrow 100 USDC' }).click();
  await p.getByText('Done and final on Monad.').waitFor({ timeout: 40000 });
  await shot(p, '11-borrowed');
});
await step('account with debt', async () => { await p.getByRole('link', { name: 'Back to account' }).click(); await p.getByText('You owe').waitFor(); await p.waitForTimeout(800); await shot(p, '12-account-debt'); });
await step('repay all', async () => {
  await p.getByRole('link', { name: 'Borrow', exact: true }).first().click();
  await p.getByRole('tab', { name: 'Repay' }).click();
  await shot(p, '13-repay');
  await p.getByRole('button', { name: /Repay all/ }).click();
  await p.getByText('Done and final on Monad.').waitFor({ timeout: 40000 });
  await shot(p, '14-repaid');
});
await step('release', async () => {
  await p.getByRole('link', { name: 'Back to account' }).click();
  await p.getByRole('link', { name: 'Release the Chog' }).click();
  await p.getByRole('heading', { name: 'Get your Chog back' }).waitFor({ timeout: 15000 });
  await shot(p, '15-release');
  await p.getByRole('button', { name: 'Withdraw all' }).click();
  await p.getByText('Done and final on Monad.').waitFor({ timeout: 40000 });
  await p.waitForTimeout(1500);
  await shot(p, '16-release-ready');
  await p.getByRole('button', { name: 'Release Chog' }).click();
  await p.getByRole('heading', { name: 'Pick your Chog' }).waitFor({ timeout: 30000 });
  await shot(p, '17-picked-again');
});
console.log('errors:', errs.slice(0, 5));
await b.close();
