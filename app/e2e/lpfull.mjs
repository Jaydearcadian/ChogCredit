// A vault holds up to 2 pool positions. A third is refused up front with a plain reason, not an unknown RPC error.
// Needs the local chain deployed with ENABLE_LP=true (see reset.sh).
import { chromium } from 'playwright-core';
import { mkdirSync } from 'node:fs';
mkdirSync('shots', { recursive: true });
const b = await chromium.launch({ executablePath: process.env.CHROMIUM_PATH ?? '/opt/pw-browsers/chromium-1194/chrome-linux/chrome', args: ['--no-sandbox'] });
const p = await (await b.newContext({ viewport: { width: 390, height: 844 } })).newPage();
const errs = []; p.on('pageerror', (e) => errs.push(e.message));
const main = p.locator('main'); const final = () => p.getByText('Final on Monad.').first().waitFor({ timeout: 40000 });
const shot = (n) => p.screenshot({ path: `shots/lp-${n}.png` });
const step = async (s, fn) => { try { await fn(); console.log('ok  ', s); } catch (e) { console.log('FAIL', s, String(e.message).split('\n')[0]); await shot('fail'); console.log((await main.innerText().catch(() => '')).slice(0, 400)); await b.close(); process.exit(1); } };
await step('open a vault', async () => { await p.goto('http://127.0.0.1:5173/?dev=1'); await p.getByRole('button', { name: 'Connect wallet' }).click(); await p.getByRole('button', { name: /No vault yet/ }).first().click(); await p.getByRole('button', { name: 'Open vault' }).click(); await p.getByRole('heading', { name: 'Vault opened.' }).waitFor({ timeout: 30000 }); await p.getByRole('button', { name: 'No thanks' }).click(); });
await step('add two test positions', async () => {
  await p.getByRole('link', { name: 'Add assets' }).click(); await p.getByRole('tab', { name: 'Pool position' }).click();
  for (let i = 0; i < 2; i++) {
    await p.getByRole('button', { name: 'Get a test position' }).click(); await p.getByText(/Counts for/).first().waitFor({ timeout: 40000 }); await p.waitForTimeout(500);
    await p.getByRole('button', { name: /^Add position #/ }).click(); await final(); await p.getByRole('link', { name: 'Back to account' }).click();
    await p.getByText('Pool positions in the vault').waitFor({ timeout: 20000 }); if (i === 0) { await p.getByRole('link', { name: 'Add assets' }).click(); await p.getByRole('tab', { name: 'Pool position' }).click(); }
  }
});
await step('a third is refused with a plain reason', async () => {
  await p.getByRole('link', { name: 'Add assets' }).click(); await p.getByRole('tab', { name: 'Pool position' }).click();
  await p.getByRole('button', { name: 'Get a test position' }).click(); await p.getByText(/Counts for/).first().waitFor({ timeout: 40000 });
  await p.getByText('This vault is full').waitFor({ timeout: 10000 });
  const btn = p.getByRole('button', { name: 'Vault is full' }); if (!(await btn.isDisabled())) throw new Error('the Add button should be disabled'); await shot('full');
});
console.log('errors:', errs);
await b.close();
