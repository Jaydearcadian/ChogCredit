// Two wallets, two tabs: the seller sells a Chog whose vault carries a loan, part of the price repays it, the buyer
// approves and signs, the seller completes. Then Activity shows the history on both sides.
import { chromium } from 'playwright-core';
import { mkdirSync } from 'node:fs';
mkdirSync('shots', { recursive: true });
const BUYER = '0x70997970C51812dc3A010C7d01b50e0d17dc79C8'; // Anvil's second test account
const b = await chromium.launch({ executablePath: process.env.CHROMIUM_PATH ?? '/opt/pw-browsers/chromium-1194/chrome-linux/chrome', args: ['--no-sandbox'] });
const seller = await (await b.newContext({ viewport: { width: 390, height: 844 }, permissions: ['clipboard-read', 'clipboard-write'] })).newPage();
const buyer = await (await b.newContext({ viewport: { width: 390, height: 844 } })).newPage();
const errs = []; for (const p of [seller, buyer]) p.on('pageerror', (e) => errs.push(e.message));
const final = (p) => p.getByText('Final on Monad.').first().waitFor({ timeout: 40000 });
const shot = (p, n) => p.screenshot({ path: `shots/s-${n}.png` });
const step = async (name, p, fn) => { try { await fn(); console.log('ok  ', name); } catch (e) { console.log('FAIL', name, String(e.message).split('\n')[0]); await shot(p, 'fail'); console.log((await p.locator('main').innerText().catch(() => '')).slice(0, 500)); console.log(errs); await b.close(); process.exit(1); } };
const S = seller.locator('main');

await step('seller: vault with assets and a loan', seller, async () => {
  await seller.goto('http://127.0.0.1:5173/?dev=1'); await seller.getByRole('button', { name: 'Connect wallet' }).click();
  await seller.getByRole('button', { name: /No vault yet/ }).first().click(); await seller.getByRole('button', { name: 'Open vault' }).click();
  await seller.getByRole('heading', { name: 'Vault opened.' }).waitFor({ timeout: 30000 }); await seller.getByRole('button', { name: 'No thanks' }).click();
  await seller.getByRole('link', { name: 'Add assets' }).click(); await seller.getByRole('button', { name: 'Get test tokens' }).click();
  await seller.getByText(/In your wallet: 100,000.00/).waitFor({ timeout: 40000 });
  await seller.getByRole('button', { name: /In your wallet/ }).click(); await seller.getByRole('button', { name: /^Add .* WMON$/ }).click(); await final(seller);
  await S.getByRole('link', { name: 'Back to account' }).click();
  await S.getByRole('link', { name: 'Borrow', exact: true }).click();
  await seller.getByLabel('How much do you want to borrow?', { exact: true }).fill('300'); await seller.getByRole('button', { name: 'Borrow 300.00 USDC' }).click(); await final(seller);
  await S.getByRole('link', { name: 'Back to account' }).click(); await S.getByRole('link', { name: 'Repay', exact: true }).waitFor({ timeout: 15000 });
});
let offer;
await step('seller: write the offer', seller, async () => {
  await seller.getByRole('link', { name: 'Sell', exact: true }).click();
  await seller.getByRole('heading', { name: 'Sell this Chog with its loan' }).waitFor({ timeout: 15000 });
  await seller.getByLabel('Price the buyer pays').fill('1000');
  await seller.getByLabel("Buyer's wallet").fill(BUYER);
  await seller.getByRole('switch', { name: 'Pay off part of the loan from the price' }).click();
  await seller.getByLabel('Goes to repay the loan', { exact: true }).fill('100');
  await seller.waitForTimeout(500); await shot(seller, '1-setup');
  await seller.getByRole('button', { name: 'Ask the buyer to sign' }).click();
  offer = await seller.locator('.share code').first().innerText();
  await seller.waitForTimeout(400); await shot(seller, '2-link');
});
let signedLink;
await step('buyer: review, get test USDC, approve, sign', buyer, async () => {
  await buyer.goto(offer + '&dev=2');
  await buyer.getByRole('button', { name: 'Connect wallet' }).click();
  await buyer.getByRole('heading', { name: 'Buy a Chog with its loan' }).waitFor({ timeout: 15000 });
  await buyer.waitForTimeout(500); await shot(buyer, '3-review');
  await buyer.getByRole('button', { name: 'Get test USDC' }).click(); await buyer.getByRole('button', { name: /Allow 1,000.00 USDC/ }).waitFor();
  await buyer.waitForTimeout(2500);
  await buyer.getByRole('button', { name: /Allow 1,000.00 USDC/ }).click();
  await buyer.getByRole('button', { name: /Sign these terms/ }).waitFor({ timeout: 40000 }); await buyer.waitForTimeout(800);
  await buyer.getByRole('button', { name: /Sign these terms/ }).click();
  signedLink = await buyer.locator('.share code').first().innerText();
  await buyer.waitForTimeout(400); await shot(buyer, '4-signed');
});
await step('seller: checks pass, complete the sale', seller, async () => {
  await seller.goto(signedLink + '&dev=1');
  await seller.getByRole('button', { name: 'Connect wallet' }).click();
  await seller.getByRole('heading', { name: 'The buyer signed' }).waitFor({ timeout: 15000 });
  await seller.getByRole('button', { name: /Complete sale/ }).waitFor();
  await seller.waitForTimeout(800); await shot(seller, '5-checks');
  if (!(await seller.getByRole('button', { name: /Complete sale/ }).isEnabled())) throw new Error('checks did not pass');
  await seller.getByRole('button', { name: /Complete sale/ }).click();
  await seller.getByRole('heading', { name: /has a new keeper/ }).waitFor({ timeout: 40000 }); await final(seller); await shot(seller, '6-sold');
});
await step('buyer: owns the account and its loan; Activity shows the purchase', buyer, async () => {
  await buyer.goto('http://127.0.0.1:5173/pick?dev=2');
  await buyer.getByRole('button', { name: 'Connect wallet' }).click().catch(() => {});
  await buyer.getByText('In its vault').first().waitFor({ timeout: 20000 });
  await buyer.getByRole('button', { name: /In its vault/ }).first().click();
  await buyer.locator('main').getByRole('link', { name: 'Repay', exact: true }).waitFor({ timeout: 15000 });
  await buyer.waitForTimeout(600); await shot(buyer, '7-buyer-account');
  await buyer.getByRole('link', { name: 'Activity', exact: true }).click();
  await buyer.getByText(/Bought from/).waitFor({ timeout: 20000 }); await buyer.waitForTimeout(500); await shot(buyer, '8-activity');
});
console.log('errors:', errs);
await b.close();
