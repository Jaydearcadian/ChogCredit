// The 60-second demo: asked before looking around, walks Account, Activity, Lend and Risk, ends by offering to connect.
// Run after sell.mjs or flow.mjs so a vault exists.
import { chromium } from 'playwright-core';
import { mkdirSync } from 'node:fs';
mkdirSync('shots', { recursive: true });
const URL = process.env.APP_URL ?? 'http://127.0.0.1:5173';
const b = await chromium.launch({ executablePath: process.env.CHROMIUM_PATH ?? '/opt/pw-browsers/chromium-1194/chrome-linux/chrome', args: ['--no-sandbox'] });
for (const [name, viewport] of [['phone', { width: 390, height: 844 }], ['desktop', { width: 1440, height: 900 }]]) {
  const p = await (await b.newContext({ viewport })).newPage();
  const errs = []; p.on('pageerror', (e) => errs.push(e.message));
  const shot = (n) => p.screenshot({ path: `shots/tour-${name}-${n}.png` });
  const step = async (s, fn) => { try { await fn(); console.log('ok  ', name, s); } catch (e) { console.log('FAIL', name, s, String(e.message).split('\n')[0]); await shot('fail'); await b.close(); process.exit(1); } };
  await step('Look around first asks about the demo', async () => { await p.goto(URL + '/'); await p.getByRole('button', { name: 'Look around first' }).click(); await p.getByRole('heading', { name: 'Want a 60-second demo?' }).waitFor({ timeout: 15000 }); await p.waitForTimeout(500); await shot('0-ask'); });
  await step('Yes opens a real vault with the guide', async () => { await p.getByRole('button', { name: 'Yes, show me' }).click(); await p.getByText('Demo · 1 of 5').waitFor({ timeout: 15000 }); await p.getByText('Assets in vault').or(p.getByText('In vault')).first().waitFor({ timeout: 20000 }); await p.waitForTimeout(600); await shot('1-account'); });
  await step('Next goes to Activity', async () => { await p.getByRole('button', { name: 'Next' }).click(); await p.getByText('Demo · 2 of 5').waitFor(); await p.waitForURL('**/activity'); await shot('2-activity'); });
  await step('Next goes to Lend and the yield is real', async () => { await p.getByRole('button', { name: 'Next' }).click(); await p.getByText('Demo · 3 of 5').waitFor(); await p.waitForURL('**/lend'); await p.getByText('Lenders earn').first().waitFor({ timeout: 15000 }); await p.waitForTimeout(800); await shot('3-lend'); });
  await step('Next goes to Risk', async () => { await p.getByRole('button', { name: 'Next' }).click(); await p.getByText('Demo · 4 of 5').waitFor(); await p.waitForURL('**/risk'); await p.getByText('The numbers').waitFor({ timeout: 15000 }); await shot('4-risk'); });
  await step('the last step offers to connect or keep looking', async () => { await p.getByRole('button', { name: 'Next' }).click(); await p.getByText('Demo · 5 of 5').waitFor(); await p.getByRole('button', { name: 'Connect wallet' }).waitFor(); await p.getByRole('link', { name: 'Keep looking around' }).waitFor(); await shot('5-end'); });
  await step('Keep looking closes the guide and shows the Chogs', async () => { await p.getByRole('link', { name: 'Keep looking around' }).click(); await p.getByRole('heading', { name: 'Chogs with a vault' }).waitFor({ timeout: 15000 }); if (await p.getByText(/Demo · \d of 5/).isVisible()) throw new Error('the guide should be closed'); });
  await step('No goes straight to the Chogs, no guide', async () => { await p.goto(URL + '/'); await p.getByRole('button', { name: 'Look around first' }).click(); await p.getByRole('button', { name: "No, I'll look around" }).click(); await p.getByRole('heading', { name: 'Chogs with a vault' }).waitFor({ timeout: 15000 }); if (await p.getByText(/Demo · \d of 5/).isVisible()) throw new Error('no guide expected'); });
  await step('the offer is also on the Look around screen', async () => { await p.getByRole('button', { name: '60-second demo' }).click(); await p.getByText('Demo · 1 of 5').waitFor({ timeout: 15000 }); });
  console.log(name, 'errors:', errs);
}
await b.close();
