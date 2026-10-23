// Renders docs/brand/banner.html to docs/brand/chogathon-banner.png. Run: node banner.mjs (from app/e2e).
import { chromium } from 'playwright-core';
import { fileURLToPath } from 'node:url';
const here = fileURLToPath(new URL('../../docs/brand/', import.meta.url));
const b = await chromium.launch({ executablePath: process.env.CHROMIUM_PATH ?? '/opt/pw-browsers/chromium-1194/chrome-linux/chrome', args: ['--no-sandbox'] });
const p = await b.newPage({ viewport: { width: 1600, height: 900 } });
await p.goto('file://' + here + 'banner.html'); await p.evaluate(() => document.fonts.ready); await p.waitForTimeout(800);
await p.screenshot({ path: here + 'chogathon-banner.png' });
await b.close();
