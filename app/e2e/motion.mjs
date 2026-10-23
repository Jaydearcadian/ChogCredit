// Walks the motion-board moments that need a particular state: tear-off, digit roll, chip swap, Pause Drill, sparkles.
// Same setup as flow.mjs (reset.sh, dev server). Screenshots go to e2e/shots/m-*.png.
import { chromium } from 'playwright-core';
import { mkdirSync } from 'node:fs';
mkdirSync('shots', { recursive: true });
const b = await chromium.launch({ executablePath: process.env.CHROMIUM_PATH ?? '/opt/pw-browsers/chromium-1194/chrome-linux/chrome', args: ['--no-sandbox'] });
const p = await (await b.newContext({ viewport: { width: 390, height: 844 } })).newPage();
const errs = []; p.on('pageerror', (e) => errs.push(e.message));
const shot = (n) => p.screenshot({ path: `shots/m-${n}.png` });
const final = () => p.getByText('Final on Monad.').first().waitFor({ timeout: 40000 });
const main = () => p.locator('main');
const step = async (name, fn) => { try { await fn(); console.log('ok  ', name); } catch (e) { console.log('FAIL', name, String(e.message).split('\n')[0]); await shot('fail'); console.log((await main().innerText().catch(() => '')).slice(0, 300)); await b.close(); process.exit(1); } };

await step('setup', async () => {
  await p.goto('http://127.0.0.1:5173/?dev=1'); await p.getByRole('button', { name: 'Connect wallet' }).click();
  await p.getByRole('button', { name: /No vault yet/ }).first().click(); await p.getByRole('button', { name: 'Open vault' }).click();
  await p.getByRole('heading', { name: 'Vault opened.' }).waitFor({ timeout: 30000 }); await p.getByRole('button', { name: 'No thanks' }).click();
  await p.getByRole('link', { name: 'Add assets' }).click(); await p.getByRole('button', { name: 'Get test tokens' }).click();
  await p.getByText(/In your wallet: 100,000.00/).waitFor({ timeout: 40000 });
  await p.getByRole('button', { name: /In your wallet/ }).click(); await p.getByRole('button', { name: /^Add .* WMON$/ }).click(); await final();
  await main().getByRole('link', { name: 'Back to account' }).click();
});
await step('first borrow: the stub tears off, once', async () => {
  await main().getByRole('link', { name: 'Borrow', exact: true }).click();
  await p.getByLabel('How much do you want to borrow?', { exact: true }).fill('400');
  await p.getByRole('button', { name: 'Borrow 400.00 USDC' }).click();
  await p.getByRole('img', { name: /first credit slip/ }).waitFor({ timeout: 40000 }); await p.waitForTimeout(900); await shot('tear'); await final();
});
await step('first paint is still: no digit rolls on arrival', async () => {
  await main().getByRole('link', { name: 'Back to account' }).click(); await p.getByText('You owe', { exact: true }).waitFor(); await p.waitForTimeout(500);
  if (await p.locator('.digit').count()) throw new Error('digits rolled on first paint');
});
await step('price falls: chip swaps Safe to Watch, digits roll, dot slides', async () => {
  await main().getByRole('link', { name: 'Settings' }).click(); await p.getByRole('button', { name: 'WMON price down' }).click(); await final();
  await p.getByRole('link', { name: 'Account', exact: true }).click();
  await p.locator('.chip.watch').first().waitFor({ timeout: 15000 }); await p.waitForTimeout(600); await shot('watch');
});
await step('Pause Drill: Borrow locks in place, Repay does not move', async () => {
  const repayBefore = await main().getByRole('link', { name: 'Repay', exact: true }).boundingBox();
  await main().getByRole('link', { name: 'Settings' }).click(); await p.getByRole('button', { name: 'Pause prices' }).click(); await final();
  await p.getByRole('link', { name: 'Account', exact: true }).click();
  await p.getByText('Borrow paused').waitFor({ timeout: 15000 }); await p.getByText('Prices are napping. Repay still works.').waitFor();
  const repayAfter = await main().getByRole('link', { name: 'Repay', exact: true }).boundingBox();
  if (Math.abs(repayBefore.x - repayAfter.x) > 1 || Math.abs(repayBefore.width - repayAfter.width) > 1) throw new Error('Repay moved sideways');
  await p.waitForTimeout(600); await shot('paused');
});
await step('repay all while paused: sparkles and the bubble', async () => {
  await main().getByRole('link', { name: 'Repay', exact: true }).click(); await p.getByRole('button', { name: /Repay all/ }).click();
  await p.getByText('Debt-free. Look at you.').waitFor({ timeout: 40000 }); await p.waitForTimeout(700); await shot('debtfree');
});
console.log('errors:', errs);
await b.close();
