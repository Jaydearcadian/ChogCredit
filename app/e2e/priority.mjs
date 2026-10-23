// Priority access: a new vault is held back from a big borrow while the pool is busy, says so before anything is signed, and is let
// through after a day. Also the "Holder since" card. Local chain only (it moves time with Anvil).
import { chromium } from 'playwright-core';
import { execFileSync } from 'node:child_process';
import { readFileSync, mkdirSync } from 'node:fs';
mkdirSync('shots', { recursive: true });
const dep = JSON.parse(readFileSync('../public/deployment.json', 'utf8'));
const K = '0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80', R = 'http://127.0.0.1:8545';
const env = { ...process.env, PATH: process.env.PATH + ':' + process.env.HOME + '/.foundry/bin' };
const cast = (...a) => execFileSync('cast', a, { stdio: 'ignore', env });
const b = await chromium.launch({ executablePath: process.env.CHROMIUM_PATH ?? '/opt/pw-browsers/chromium-1194/chrome-linux/chrome', args: ['--no-sandbox'] });
const p = await (await b.newContext({ viewport: { width: 390, height: 844 } })).newPage();
const errs = []; p.on('pageerror', (e) => errs.push(e.message));
const main = p.locator('main'); const final = () => p.getByText('Final on Monad.').first().waitFor({ timeout: 40000 });
const shot = (n) => p.screenshot({ path: `shots/pr-${n}.png` });
const step = async (s, fn) => { try { await fn(); console.log('ok  ', s); } catch (e) { console.log('FAIL', s, String(e.message).split('\n')[0]); await shot('fail'); console.log((await main.innerText().catch(() => '')).slice(0, 400)); await b.close(); process.exit(1); } };

await step('WMON is priced at $1 so a small vault can borrow most of the pool', async () => { cast('send', dep.mockOracle, 'setPrice(address,uint256)', dep.mockWmon, '1000000', '--private-key', K, '--rpc-url', R); });
await step('open a vault and add WMON', async () => {
  await p.goto('http://127.0.0.1:5173/?dev=1'); await p.getByRole('button', { name: 'Connect wallet' }).click();
  await p.getByRole('button', { name: /No vault yet/ }).first().click(); await p.getByRole('button', { name: 'Open vault' }).click();
  await p.getByRole('heading', { name: 'Vault opened.' }).waitFor({ timeout: 30000 }); await p.getByRole('button', { name: 'No thanks' }).click();
  await p.getByRole('link', { name: 'Add assets' }).click(); await p.getByRole('button', { name: 'Get test tokens' }).click();
  await p.getByText(/In your wallet: 100,000.00/).waitFor({ timeout: 40000 });
  await p.getByRole('button', { name: /In your wallet/ }).click(); await p.getByRole('button', { name: /^Add .* WMON$/ }).click(); await final();
  await p.getByRole('link', { name: 'Back to account' }).click();
});
await step('the account shows Holder since and priority access in a day', async () => {
  await p.getByText('Holder since').waitFor({ timeout: 20000 }); await p.getByText('Priority access').waitFor(); await p.getByText('in 24 hours').waitFor(); await shot('1-account');
});
await step('a big borrow on a busy pool is held back, with the reason, before signing', async () => {
  await main.getByRole('link', { name: 'Borrow', exact: true }).click();
  await p.getByLabel('How much do you want to borrow?', { exact: true }).fill('4800');
  await p.getByText('The pool is busy').waitFor({ timeout: 20000 }); await shot('2-held');
  const btn = p.getByRole('button', { name: /^Borrow/ }); if (!(await btn.isDisabled())) throw new Error('the Borrow button should be disabled');
});
await step('a smaller borrow under the line goes through', async () => {
  await p.getByLabel('How much do you want to borrow?', { exact: true }).fill('1000');
  await p.getByText('The pool is busy').waitFor({ state: 'detached', timeout: 20000 });
  await p.getByRole('button', { name: 'Borrow 1,000.00 USDC' }).click(); await final();
  await main.getByRole('link', { name: 'Back to account' }).click();
});
await step('the Risk page states the rule', async () => { await p.getByRole('link', { name: 'Risk', exact: true }).click(); await p.getByText(/Busy pool: vaults open/).waitFor({ timeout: 20000 }); await shot('3-risk'); });
await step('a day later the vault has priority and the big borrow goes through', async () => {
  cast('rpc', 'evm_increaseTime', '90000', '--rpc-url', R); cast('rpc', 'evm_mine', '--rpc-url', R);
  await p.getByRole('link', { name: 'Account', exact: true }).click();
  await p.getByText('Yes', { exact: true }).waitFor({ timeout: 30000 }); await shot('4-priority');
  await main.getByRole('link', { name: 'Borrow', exact: true }).click();
  await p.getByLabel('How much do you want to borrow?', { exact: true }).fill('3600'); // pool is at 20% + 72% = over the line, but the vault is tenured now
  await p.getByRole('button', { name: 'Borrow 3,600.00 USDC' }).waitFor({ timeout: 20000 });
  if (await p.getByText('The pool is busy').isVisible()) throw new Error('a tenured vault should not be held back');
  await p.getByRole('button', { name: 'Borrow 3,600.00 USDC' }).click(); await final();
});
console.log('errors:', errs);
await b.close();
