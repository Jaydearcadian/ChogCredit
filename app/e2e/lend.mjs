// A second wallet lends and withdraws; the pool's totals move.
import { chromium } from 'playwright-core';
import { mkdirSync } from 'node:fs';
mkdirSync('shots', { recursive: true });
const b = await chromium.launch({ executablePath: process.env.CHROMIUM_PATH ?? '/opt/pw-browsers/chromium-1194/chrome-linux/chrome', args: ['--no-sandbox'] });
const p = await (await b.newContext({ viewport: { width: 390, height: 844 } })).newPage();
const errs = []; p.on('pageerror', (e) => errs.push(e.message));
const main = p.locator('main'); const final = () => p.getByText('Final on Monad.').first().waitFor({ timeout: 40000 });
const shot = (n) => p.screenshot({ path: `shots/l-${n}.png` });
const step = async (s, fn) => { try { await fn(); console.log('ok  ', s); } catch (e) { console.log('FAIL', s, String(e.message).split('\n')[0]); await shot('fail'); console.log((await main.innerText().catch(() => '')).slice(0, 400)); await b.close(); process.exit(1); } };
await step('see the pool without a wallet', async () => { await p.goto('http://127.0.0.1:5173/lend'); await p.getByText('Lenders earn').waitFor({ timeout: 15000 }); await p.getByRole('button', { name: 'Connect wallet' }).waitFor(); await p.waitForTimeout(600); await shot('1-nowallet'); });
await step('connect as lender and get test USDC', async () => { await p.goto('http://127.0.0.1:5173/lend?dev=2'); await p.getByRole('button', { name: 'Connect', exact: true }).first().click(); await p.getByText('Your deposit').waitFor(); await p.getByRole('button', { name: 'Get test USDC' }).click(); await p.getByText(/In your wallet: 10,000.00/).waitFor({ timeout: 40000 }); });
await step('lend 1,000', async () => { await p.getByLabel('How much do you want to lend?', { exact: true }).fill('1000'); await p.getByRole('button', { name: 'Lend 1,000.00 USDC' }).click(); await final(); await p.waitForTimeout(900); await shot('2-lent'); await p.getByText('Thanks for filling the pool.').waitFor(); });
await step('deposit shows', async () => { await p.getByText(/^1,000\.0\d USDC$|^1,000\.00 USDC$/).first().waitFor({ timeout: 20000 }); });
await step('withdraw 400', async () => { await p.getByRole('tab', { name: 'Withdraw' }).click(); await p.getByLabel('How much do you want to take out?', { exact: true }).fill('400'); await p.getByRole('button', { name: 'Withdraw 400.00 USDC' }).click(); await final(); await p.waitForTimeout(800); await shot('3-withdrawn'); });
await step('cannot withdraw more than you have', async () => { await p.getByLabel('How much do you want to take out?', { exact: true }).fill('9999'); await p.getByRole('alert').waitFor(); await shot('4-error'); });
console.log('errors:', errs);
await b.close();
