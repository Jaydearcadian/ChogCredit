// The Pause Drill on Monad TESTNET, live: with the buyer's account open, prices are switched off from outside (the
// deploy wallet owns the mock price source, via `cast`), Borrow locks, Repay does not move, then prices come back.
// Needs DEPLOYER_KEY in the environment (the test deploy wallet) and w2.json (a wallet that keeps a Chog with a loan).
import { execFileSync } from 'node:child_process';
import { readFileSync } from 'node:fs';
import { launch, person, URL } from './lib/standin.mjs';
const dep = JSON.parse(readFileSync('../public/deployments/monad-testnet.json', 'utf8'));
const flip = (down) => execFileSync('cast', ['send', dep.mockOracle, 'setDown(bool)', String(down), '--private-key', process.env.DEPLOYER_KEY, '--rpc-url', 'https://testnet-rpc.monad.xyz'], { stdio: 'ignore' });
const b = await launch();
const x = await person(b, 'w2.json', 'keeper');
await x.p.goto(URL); await x.p.getByRole('button', { name: /^Connect( wallet)?$/ }).first().click(); await x.p.getByRole('button', { name: 'Browser Wallet' }).click({ timeout: 5000 }).catch(() => {});
await x.p.getByRole('button', { name: /In its vault/ }).first().click({ timeout: 40000 });
await x.main.getByRole('link', { name: 'Repay', exact: true }).waitFor({ timeout: 40000 }); await x.p.waitForTimeout(1200);
const before = await x.main.getByRole('link', { name: 'Repay', exact: true }).boundingBox();
const swap = x.p.evaluate(() => new Promise((res) => { let seen = false; const o = new MutationObserver(() => { if (document.querySelector('.swap > .out')) seen = true; }); o.observe(document.body, { subtree: true, childList: true }); setTimeout(() => { o.disconnect(); res(seen); }, 45000); }));
flip(true);
try {
  await x.p.getByText('Borrow paused').waitFor({ timeout: 40000 }); await x.p.getByText('Prices are napping. Repay still works.').waitFor(); await x.p.waitForTimeout(800);
  const after = await x.main.getByRole('link', { name: 'Repay', exact: true }).boundingBox();
  await x.p.screenshot({ path: 'shots/tp-paused.png' });
  console.log('Borrow locked: yes | Repay moved:', Math.abs(before.x - after.x) > 1 || Math.abs(before.y - after.y) > 1 ? 'YES' : 'no');
} finally { flip(false); }
await x.p.getByRole('link', { name: 'Borrow', exact: true }).first().waitFor({ timeout: 40000 });
console.log('chip swap seen:', await swap, '| prices back, Borrow unlocked');
await b.close();
