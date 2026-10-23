// End-to-end walk through the money flow on a fresh local chain: connect, open a vault, add, borrow, repay, release.
// Run `e2e/reset.sh` first, start `npm run dev`, then `node e2e/flow.mjs`. Screenshots go to e2e/shots (ignored by git).
import { chromium } from 'playwright-core';
import { mkdirSync } from 'node:fs';
mkdirSync('shots', { recursive: true });
const b = await chromium.launch({ executablePath: process.env.CHROMIUM_PATH ?? '/opt/pw-browsers/chromium-1194/chrome-linux/chrome', args: ['--no-sandbox'] });
const p = await (await b.newContext({ viewport: { width: 390, height: 844 } })).newPage();
const errs = []; p.on('pageerror', (e) => errs.push('PAGEERR ' + e.message)); p.on('console', (m) => m.type() === 'error' && errs.push(m.text()));
const shot = (n) => p.screenshot({ path: `shots/${n}.png` });
const still = () => p.waitForTimeout(700); // let entrances settle before a screenshot
const final = () => p.getByText('Final on Monad.').waitFor({ timeout: 40000 });
const step = async (name, fn) => { try { await fn(); console.log('ok  ', name); } catch (e) { console.log('FAIL', name, String(e.message).split('\n')[0]); await shot('fail-' + name.replace(/\W+/g, '-')); console.log((await p.locator('main').innerText().catch(() => '')).slice(0, 400)); console.log('errs', errs.slice(0, 4)); await b.close(); process.exit(1); } };

await step('connect', async () => { await p.goto('http://127.0.0.1:5173/?dev=1'); await p.getByRole('button', { name: 'Connect wallet' }).waitFor(); await still(); await shot('01-connect'); await p.getByRole('button', { name: 'Connect wallet' }).click(); });
await step('pick', async () => { await p.getByRole('heading', { name: 'Pick your Chog' }).waitFor(); await p.getByText('No vault yet').first().waitFor(); await still(); await shot('02-pick'); });
await step('open vault', async () => {
  await p.getByRole('button', { name: /No vault yet/ }).first().click();
  await p.getByRole('heading', { name: 'Open a vault' }).waitFor(); await still(); await shot('03-open');
  await p.getByRole('button', { name: 'Open vault' }).click();
  await p.getByRole('heading', { name: 'Vault opened.' }).waitFor({ timeout: 30000 }); await p.waitForTimeout(1200); await shot('04-opened');
});
await step('account empty', async () => { await p.getByRole('link', { name: 'Look around first' }).click(); await p.getByText('Nothing to withdraw').waitFor(); await still(); await shot('05-account-empty'); });
await step('faucet + add', async () => {
  await p.getByRole('link', { name: 'Add assets' }).first().click();
  await p.getByRole('button', { name: 'Get test tokens' }).click();
  await p.getByText(/In your wallet: 100,000.00/).waitFor({ timeout: 40000 }); await still(); await shot('06-add');
  await p.getByRole('button', { name: /In your wallet: 100,000.00/ }).click();
  await p.getByText('After adding').waitFor(); await still(); await shot('07-add-filled');
  await p.getByRole('button', { name: /^Add .* WMON$/ }).click(); await final(); await still(); await shot('08-add-done');
});
await step('account has funds', async () => { await p.getByRole('link', { name: 'Back to account' }).click(); await p.getByText('In vault').waitFor(); await p.locator('main').getByRole('link', { name: 'Borrow', exact: true }).waitFor({ timeout: 15000 }); await still(); await shot('09-account'); });
await step('borrow', async () => {
  await p.locator('main').getByRole('link', { name: 'Borrow', exact: true }).click();
  await p.getByLabel('How much do you want to borrow?', { exact: true }).fill('100');
  await p.getByText('Health after').waitFor(); await still(); await shot('10-borrow');
  await p.getByRole('button', { name: 'Borrow 100.00 USDC' }).click(); await final(); await still(); await shot('11-borrowed');
});
await step('account with debt', async () => { await p.getByRole('link', { name: 'Back to account' }).click(); await p.locator('main').getByRole('link', { name: 'Repay', exact: true }).waitFor({ timeout: 15000 }); await still(); await shot('12-account-debt'); });
await step('repay all', async () => {
  await p.locator('main').getByRole('link', { name: 'Repay', exact: true }).click();
  await p.getByRole('button', { name: /Repay all/ }).waitFor(); await still(); await shot('13-repay');
  await p.getByRole('button', { name: /Repay all/ }).click();
  await p.getByText('Debt-free. Look at you.').waitFor({ timeout: 40000 }); await final(); await still(); await shot('14-debt-free');
});
await step('release', async () => {
  await p.getByRole('link', { name: 'Get your Chog back' }).click();
  await p.getByRole('heading', { name: 'Get your Chog back' }).waitFor(); await still(); await shot('15-release');
  await p.getByRole('button', { name: 'Withdraw all' }).click(); await final();
  await p.getByRole('button', { name: 'Release Chog' }).click();
  await p.getByRole('heading', { name: 'Pick your Chog' }).waitFor({ timeout: 40000 }); await still(); await shot('16-picked-again');
});
console.log('errors:', errs);
await b.close();
