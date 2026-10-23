import { chromium } from 'playwright-core';
const b = await chromium.launch({ executablePath: process.env.CHROMIUM_PATH ?? '/opt/pw-browsers/chromium-1194/chrome-linux/chrome', args: ['--no-sandbox'] });
const p = await (await b.newContext({ viewport: { width: 390, height: 844 } })).newPage();
await p.goto('http://127.0.0.1:5173/risk');
await p.getByText('The numbers').waitFor({ timeout: 15000 });
const t = await p.locator('main').innerText();
for (const w of ['40%', '65%', '8%', '$5,000.00', '$15,000.00', 'Health 1.50 or more']) if (!t.includes(w)) { console.log('FAIL missing', w, '\n' + t); process.exit(1); }
console.log('ok   risk numbers read from the pool');
await b.close();
