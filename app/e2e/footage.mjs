// Records the demo video's real walkthrough footage from the app on a fresh local chain (run ./reset.sh first).
// One recording per scene into ../../video/footage/ (VIEW=desktop records 1280x800 at 1.5x into footage/desktop/). A pink pixel cursor and tap ripple are injected so taps read on video.
import { chromium } from 'playwright-core';
import { mkdirSync, rmSync, writeFileSync, readFileSync } from 'node:fs';
import { execFileSync } from 'node:child_process';
const DESK = process.env.VIEW === 'desktop';
const OUT = new URL(DESK ? '../../video/footage/desktop/' : '../../video/footage/', import.meta.url).pathname;
const VP = DESK ? { width: 1280, height: 800, s: 1.5 } : { width: 390, height: 844, s: 2 };
mkdirSync(OUT, { recursive: true });
const b = await chromium.launch({ executablePath: process.env.CHROMIUM_PATH ?? '/opt/pw-browsers/chromium-1194/chrome-linux/chrome', args: ['--no-sandbox'] });

const CURSOR = `(() => {
  const css = '.__cur{position:fixed;z-index:2147483647;left:0;top:0;width:'+(innerWidth>700?22:18)+'px;height:'+(innerWidth>700?22:18)+'px;margin:-3px 0 0 -3px;pointer-events:none;background:#E845A4;border:2px solid #0E0B1A;border-radius:3px;transform:translate(-40px,-40px);transition:transform .02s}.__rip{position:fixed;z-index:2147483646;pointer-events:none;width:14px;height:14px;margin:-7px 0 0 -7px;border-radius:50%;border:3px solid #836EF9;animation:__r .55s ease-out forwards}@keyframes __r{to{transform:scale(5);opacity:0}}';
  const go = () => { const s = document.createElement('style'); s.textContent = css; document.head.appendChild(s);
    const c = document.createElement('div'); c.className = '__cur'; document.body.appendChild(c);
    addEventListener('mousemove', (e) => { c.style.transform = 'translate(' + e.clientX + 'px,' + e.clientY + 'px)'; }, true);
    addEventListener('mousedown', (e) => { const r = document.createElement('div'); r.className = '__rip'; r.style.left = e.clientX + 'px'; r.style.top = e.clientY + 'px'; document.body.appendChild(r); setTimeout(() => r.remove(), 700); }, true); };
  if (document.body) go(); else addEventListener('DOMContentLoaded', go);
})();`;

async function scene(name, fn) {
  if (process.argv[2] && !process.argv.slice(2).some((a) => name.startsWith(a))) return;
  const ctx = await b.newContext({ viewport: { width: VP.width, height: VP.height }, deviceScaleFactor: VP.s });
  await ctx.addInitScript(CURSOR);
  const p = await ctx.newPage();
  p.setDefaultTimeout(40000);
  // Playwright's own recorder needs a ffmpeg build this machine lacks, so frames come from the browser's screencast and are encoded here.
  const cdp = await ctx.newCDPSession(p); const frames = [];
  cdp.on('Page.screencastFrame', ({ data, metadata, sessionId }) => { frames.push({ t: metadata.timestamp, data }); cdp.send('Page.screencastFrameAck', { sessionId }).catch(() => {}); });
  await cdp.send('Page.startScreencast', { format: 'jpeg', quality: 94, maxWidth: VP.width * VP.s, maxHeight: VP.height * VP.s, everyNthFrame: 1 });
  const errs = []; p.on('pageerror', (e) => errs.push(e.message));
  const at = Date.now();
  try { await fn(p); } catch (e) { console.log('FAIL', name, String(e.message).split('\n')[0]); await p.screenshot({ path: OUT + `_fail-${name}.png` }); }
  await p.waitForTimeout(500);
  await cdp.send('Page.stopScreencast'); await ctx.close();
  const dir = OUT + '_f-' + name + '/'; mkdirSync(dir, { recursive: true });
  const list = frames.map((f, i) => { writeFileSync(dir + i + '.jpg', Buffer.from(f.data, 'base64')); return `file '${dir}${i}.jpg'\nduration ${Math.max(0.01, (frames[i + 1]?.t ?? f.t + 0.5) - f.t).toFixed(4)}`; });
  writeFileSync(dir + 'list.txt', list.join('\n') + `\nfile '${dir}${frames.length - 1}.jpg'\n`);
  execFileSync('ffmpeg', ['-v', 'error', '-y', '-f', 'concat', '-safe', '0', '-i', dir + 'list.txt', '-vf', `fps=30,scale=${VP.width * VP.s}:${VP.height * VP.s},format=yuv420p`, '-c:v', 'libx264', '-crf', '16', '-preset', 'fast', OUT + name + '.mp4']);
  rmSync(dir, { recursive: true, force: true });
  console.log('ok  ', name, ((Date.now() - at) / 1000).toFixed(1) + 's', frames.length + ' frames', errs.length ? errs : '');
}
const wait = (p, ms) => p.waitForTimeout(ms);
async function tap(p, loc, { pause = 350 } = {}) {
  await loc.waitFor(); await loc.scrollIntoViewIfNeeded();
  const bb = await loc.boundingBox();
  await p.mouse.move(bb.x + bb.width / 2, bb.y + bb.height / 2, { steps: 22 }); await wait(p, 160);
  await p.mouse.down(); await wait(p, 70); await p.mouse.up(); await wait(p, pause);
}
async function type(p, loc, text) { await tap(p, loc, { pause: 150 }); await loc.fill(''); await loc.pressSequentially(text, { delay: 140 }); await wait(p, 450); }
const final = (p) => p.getByText('Final on Monad.').first().waitFor({ timeout: 40000 });
const connect = async (p) => { await p.goto('http://127.0.0.1:5173/?dev=1'); await wait(p, 900); await tap(p, p.getByRole('button', { name: 'Connect wallet' })); };
const enter = async (p) => { await connect(p); await tap(p, p.getByRole('button', { name: /In its vault/ }).first()); await p.getByRole('link', { name: 'Add assets' }).first().waitFor(); await wait(p, 900); };

const M = (p) => p.locator('main');
// The one-time "Want tiny sounds?" prompt is answered off camera so it never sits in a shot.
const quiet = (p) => p.addInitScript(() => { try { localStorage.setItem('chog-credit:prefs', JSON.stringify({ sound: false, riskSound: false, haptics: true, offered: true })); } catch {} });
const dismiss = async (p) => { const b = p.getByRole('button', { name: 'No thanks' }); if (await b.isVisible().catch(() => false)) await b.click(); };
const DEP = JSON.parse(readFileSync(new URL('../public/deployment.json', import.meta.url), 'utf8'));
const cast = (...a) => execFileSync('cast', [...a, '--private-key', '0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80', '--rpc-url', 'http://127.0.0.1:8545'], { stdio: 'ignore', env: { ...process.env, PATH: process.env.PATH + ':' + process.env.HOME + '/.foundry/bin' } });

await scene('01-open', async (p) => {
  await quiet(p);
  await p.goto('http://127.0.0.1:5173/?dev=1'); await wait(p, 2400);
  await tap(p, p.getByRole('button', { name: 'Connect wallet' }).first()); await wait(p, 1600);
  await tap(p, p.getByRole('button', { name: /No vault yet/ }).first()); await wait(p, 1400);
  await tap(p, p.getByRole('button', { name: 'Open vault' }));
  await p.getByRole('heading', { name: 'Vault opened.' }).waitFor(); await wait(p, 3400); await dismiss(p); await wait(p, 1500);
});
await scene('02-add', async (p) => {
  await quiet(p); await enter(p); await dismiss(p);
  await tap(p, M(p).getByRole('link', { name: 'Add assets' }).first()); await wait(p, 1000);
  await tap(p, p.getByRole('button', { name: 'Get test tokens' })); await p.getByText(/In your wallet: 100,000.00/).waitFor(); await wait(p, 900);
  await tap(p, p.getByRole('button', { name: /In your wallet/ })); await wait(p, 700);
  await tap(p, p.getByRole('button', { name: /^Add .* WMON$/ })); await final(p); await wait(p, 1800); await dismiss(p);
  await tap(p, p.getByRole('link', { name: 'Back to account' })); await wait(p, 3200);
});
await scene('03-borrow', async (p) => {
  await quiet(p); await enter(p); await dismiss(p);
  await tap(p, M(p).getByRole('link', { name: 'Borrow', exact: true })); await wait(p, 1000);
  await type(p, p.getByLabel('How much do you want to borrow?', { exact: true }), '300'); await wait(p, 1200);
  await tap(p, p.getByRole('button', { name: 'Borrow 300.00 USDC' })); await final(p); await wait(p, 2800); await dismiss(p);
  await tap(p, p.getByRole('link', { name: 'Back to account' })); await wait(p, 3200);
});
await scene('04-sell', async (p) => {
  await quiet(p); await enter(p); await dismiss(p);
  await tap(p, M(p).getByRole('link', { name: 'Sell', exact: true }).or(p.getByRole('link', { name: 'Sell', exact: true })).first());
  await p.getByRole('heading', { name: /Sell this Chog/ }).waitFor(); await wait(p, 1400);
  await type(p, p.getByLabel('Price the buyer pays'), '1000');
  const w = p.getByLabel("Buyer's wallet"); await tap(p, w, { pause: 200 }); await w.fill('0x70997970C51812dc3A010C7d01b50e0d17dc79C8'); await wait(p, 1200);
  await tap(p, p.getByRole('button', { name: 'Ask the buyer to sign' })); await wait(p, 600);
  await p.locator('.share code').first().scrollIntoViewIfNeeded(); await wait(p, 3600);
});
await scene('05-receive', async (p) => {
  await quiet(p); await enter(p); await dismiss(p);
  await tap(p, p.getByRole('link', { name: /Get paid/ }).first()); await wait(p, 4600);
  await tap(p, p.getByRole('link', { name: 'Lend', exact: true }).first()); await p.getByText('Lenders earn').first().waitFor().catch(() => {}); await wait(p, 4200);
});
await scene('06-pause', async (p) => {
  await quiet(p); await enter(p); await dismiss(p); await wait(p, 1500);
  cast('send', DEP.mockOracle, 'setDown(bool)', 'true');
  await tap(p, p.getByRole('link', { name: 'Risk', exact: true }).first()); await p.getByText('The numbers').waitFor(); await wait(p, 2600);
  await p.mouse.wheel(0, 500); await wait(p, 2000);
  await tap(p, p.getByRole('link', { name: 'Account', exact: true }).first()); await p.getByText('Borrow paused').first().waitFor(); await wait(p, 4200);
  cast('send', DEP.mockOracle, 'setDown(bool)', 'false');
});
await b.close();
