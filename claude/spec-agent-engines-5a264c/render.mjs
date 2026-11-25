import { chromium } from 'playwright-core';
import path from 'node:path';
const dir = path.dirname(new URL(import.meta.url).pathname);
const exe = process.env.HOME + '/Library/Caches/ms-playwright/chromium-1248/chrome-mac-arm64/Google Chrome for Testing.app/Contents/MacOS/Google Chrome for Testing';
const browser = await chromium.launch({ executablePath: exe });
const page = await browser.newPage({ deviceScaleFactor: 2, viewport: { width: 1400, height: 1000 } });
await page.goto('file://' + path.join(dir, 'mockups.html'));
await page.evaluate(() => document.fonts.ready);
const ids = await page.evaluate(() => window.FRAMES);
for (const id of ids) {
  await page.locator('[id="' + id + '"]').screenshot({ path: path.join(dir, 'out', id + '.png') });
}
console.log('rendered', ids.length, 'frames; fonts:', await page.evaluate(() => [...document.fonts].map(f => f.family + ':' + f.status).join(', ')));
await browser.close();
