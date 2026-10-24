// A borrower who still holds exactly what they borrowed is a little short of owing it all once interest has added up.
// The Repay screen says so, offers test USDC, and then Repay all works. Local chain (it moves time with Anvil).
import { chromium } from 'playwright-core';
import { execFileSync } from 'node:child_process';
import { mkdirSync, readFileSync } from 'node:fs';
mkdirSync('shots', { recursive: true });
const env = { ...process.env, PATH: process.env.PATH + ':' + process.env.HOME + '/.foundry/bin' };
const cast = (...a) => execFileSync('cast', a, { stdio: 'ignore', env });
const R = 'http://127.0.0.1:8545';
const K = '0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80'; // the dev wallet's key (Anvil #0)
const dep = JSON.parse(readFileSync('../public/deployment.json', 'utf8'));
const out = (...a) => execFileSync('cast', a, { env }).toString().trim().split(' ')[0];
// The dev wallet starts with plenty of USDC; send it away so it holds only what it borrows, like a real borrower.
const emptyUsdc = () => { const me = out('wallet', 'address', '--private-key', K); const bal = out('call', dep.mockUsdc, 'balanceOf(address)(uint256)', me, '--rpc-url', R); if (bal !== '0') cast('send', dep.mockUsdc, 'transfer(address,uint256)', '0x000000000000000000000000000000000000dEaD', bal, '--private-key', K, '--rpc-url', R); };
const b = await chromium.launch({ executablePath: process.env.CHROMIUM_PATH ?? '/opt/pw-browsers/chromium-1194/chrome-linux/chrome', args: ['--no-sandbox'] });
const p = await (await b.newContext({ viewport: { width: 390, height: 844 } })).newPage();
const errs = []; p.on('pageerror', (e) => errs.push(e.message));
const main = p.locator('main'); const final = () => p.getByText('Final on Monad.').first().waitFor({ timeout: 40000 });
const shot = (n) => p.screenshot({ path: `shots/dust-${n}.png` });
const step = async (s, fn) => { try { await fn(); console.log('ok  ', s); } catch (e) { console.log('FAIL', s, String(e.message).split('\n')[0]); await shot('fail'); console.log((await p.locator('body').innerText().catch(() => '')).slice(0, 500)); await b.close(); process.exit(1); } };

await step('open a vault, add WMON, borrow 50 (the wallet then holds exactly 50)', async () => {
  await p.goto('http://127.0.0.1:5173/?dev=1'); await p.getByRole('button', { name: 'Connect wallet' }).click();
  await p.getByRole('button', { name: /No vault yet/ }).first().click(); await p.getByRole('button', { name: 'Open vault' }).click();
  await p.getByRole('heading', { name: 'Vault opened.' }).waitFor({ timeout: 30000 }); await p.getByRole('button', { name: 'No thanks' }).click();
  await p.getByRole('link', { name: 'Add assets' }).click(); await p.getByRole('button', { name: 'Get test tokens' }).click();
  await p.getByText(/In your wallet: 100,000.00/).waitFor({ timeout: 40000 });
  await p.getByRole('button', { name: /In your wallet/ }).click(); await p.getByRole('button', { name: /^Add .* WMON$/ }).click(); await final();
  await p.getByRole('link', { name: 'Back to account' }).click(); emptyUsdc(); await main.getByRole('link', { name: 'Borrow', exact: true }).click();
  await p.getByLabel('How much do you want to borrow?', { exact: true }).fill('50'); await p.getByRole('button', { name: 'Borrow 50.00 USDC' }).click(); await final();
  await main.getByRole('link', { name: 'Back to account' }).click(); await main.getByRole('link', { name: 'Repay', exact: true }).waitFor({ timeout: 20000 });
});
await step('a month of interest later, Repay says the wallet is a little short', async () => {
  cast('rpc', 'evm_increaseTime', '2592000', '--rpc-url', R); cast('rpc', 'evm_mine', '--rpc-url', R);
  await main.getByRole('link', { name: 'Repay', exact: true }).click(); // the screen re-reads the chain every 15 s, so it will notice the new block time
  await p.getByText('Includes interest so far').waitFor({ timeout: 20000 });
  await p.getByText("You're a little short of paying it all off").waitFor({ timeout: 30000 }); await p.waitForTimeout(800); await shot('1-short');
  if (await p.getByRole('button', { name: /^Repay all/ }).isVisible()) throw new Error('Repay all should not be offered while short');
});
await step('Get test USDC, then Repay all works', async () => {
  await p.getByRole('button', { name: 'Get test USDC' }).click();
  await p.getByRole('button', { name: /^Repay all/ }).waitFor({ timeout: 40000 }); await shot('2-topped-up');
  if (await p.getByText("You're a little short of paying it all off").isVisible()) throw new Error('the note should be gone');
  await p.getByRole('button', { name: /^Repay all/ }).click(); await p.getByText('Debt-free. Look at you.').waitFor({ timeout: 40000 });
});
console.log('errors:', errs);
await b.close();
