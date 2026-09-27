// Screenshots of the workbench showing each tool in use, for Act III of the
// lookbook. Drives the guided tour in a real Chrome (its steps set the
// breakpoint, run the programs, select the packet), then switches to the
// layout that shows the tool best and captures the frame together with the
// bounding boxes of the visible windows, so the HUD can bracket them.
// Output: out/motion/ide/<name>.png and out/motion/ide/stills.json.
import { chromium } from '@playwright/test';
import { mkdir, readFile, writeFile } from 'node:fs/promises';
import { createServer } from 'node:http';
import { extname, join } from 'node:path';

const W = 1920, H = 1080, dir = 'out/motion/ide';
const types = { '.html': 'text/html', '.js': 'text/javascript', '.json': 'application/json', '.css': 'text/css', '.wasm': 'application/wasm', '.png': 'image/png', '.svg': 'image/svg+xml', '.ttf': 'font/ttf', '.woff2': 'font/woff2' };
const serve = root => new Promise(resolve => { const server = createServer(async (req, res) => { const path = join(root, decodeURIComponent(new URL(req.url, 'http://x').pathname).replace(/\/$/, '/index.html')); try { const body = await readFile(path); res.writeHead(200, { 'content-type': types[extname(path)] ?? 'application/octet-stream' }); res.end(body); } catch { res.writeHead(404); res.end(); } }); server.listen(0, '127.0.0.1', () => resolve({ server, url: `http://127.0.0.1:${server.address().port}` })); });

await mkdir(dir, { recursive: true });
const { server, url } = await serve('dist');
const browser = await chromium.launch({ channel: process.env.PLAYWRIGHT_CHANNEL ?? 'chrome' });
const page = await browser.newPage({ viewport: { width: W, height: H }, deviceScaleFactor: 1 });
const pause = s => page.waitForTimeout(s * 1000);
const tour = page.locator('[data-window=tutorial]');
const doIt = tour.locator('.tutorial-actions button').first(), next = tour.getByRole('button', { name: 'Next step' });
const waitDone = (seconds = 120) => page.waitForFunction(() => document.querySelector('.tutorial-done')?.textContent.includes('Done'), null, { timeout: seconds * 1000 }).then(() => true, () => false);
// Layouts are applied through the Layout menu's palette, which exists in every layout (the listener window does not).
const layout = async name => { await page.locator('#layout-menu').click(); const input = page.locator('dialog input[role=combobox]'); await input.waitFor(); await input.fill(`Layout: ${name}`); await pause(.3); await input.press('Enter'); await pause(.8); };
const openTour = async () => { if (!await tour.isVisible()) { await page.locator('#tutorial-menu').click(); await tour.waitFor(); } };
const step = async (label, seconds) => { await openTour(); const text = await doIt.textContent(); console.log(`step: ${text}`); await doIt.click(); const ok = await waitDone(seconds); console.log(ok ? '  done' : '  not done in time; continuing'); return ok; };
const nextStep = async () => { await openTour(); await next.click(); await pause(.5); };
const stills = {};
const shoot = async (name, preset, note) => {
  if (preset) await layout(preset); await pause(1.2);
  const windows = {};
  for (const handle of await page.locator('[data-window]').all()) { const id = await handle.getAttribute('data-window'); const box = await handle.boundingBox(); if (box && box.width > 40) windows[id] = { x: Math.round(box.x), y: Math.round(box.y), w: Math.round(box.width), h: Math.round(box.height) }; }
  await page.screenshot({ path: `${dir}/${name}.png` });
  stills[name] = { file: `${name}.png`, layout: preset, note, windows, status: await page.locator('#status-text').textContent() };
  console.log(`wrote ${dir}/${name}.png · ${Object.keys(windows).join(', ')}`);
};

await page.goto(url + '/'); await page.evaluate(() => localStorage.clear()); await page.goto(url + '/');
await page.locator('#status-text').filter({ hasText: /Loaded \/home\/user\/main\.c/ }).waitFor({ timeout: 90_000 });
await step('Run main.c', 40); await pause(1);
await shoot('workbench', 'development', 'main.c ran on two nodes; result 720');
await nextStep(); await step('Change 6 to 5 and run', 40); await nextStep();
await step('Break on line 6 and run', 40); await pause(1);
for (let i = 0; i < 5; i++) { await page.keyboard.press('F10'); await pause(.4); }
await shoot('debugger', 'debugging', 'stopped at the breakpoint on line 6, five instructions stepped');
await nextStep(); await step('Run remote_call.c', 40); await nextStep();
await step('Select the first packet', 15); await pause(1);
await shoot('packets', 'network', 'remote_call.c: first packet selected, route drawn');
// The hotspot is captured mid-run: pause with F5 while the queues are full, shoot, then continue.
await nextStep(); await openTour(); console.log(`step: ${await doIt.textContent()}`); await doIt.click(); await pause(2.5); await page.keyboard.press('F5'); await pause(1);
await shoot('contention', 'network', 'message_hotspot.c on sixteen nodes, paused mid-run');
await page.keyboard.press('F5'); await waitDone(90).then(ok => console.log(ok ? '  done' : '  not done in time; continuing'));
await nextStep(); await step('Build, load, and run /build/main.image', 40); await nextStep();
await step('Build and run the Mandelbrot image', 20); await pause(60);
await shoot('graphics', 'graphics', 'distributed_mandelbrot.c on four nodes, display while running');
await writeFile(`${dir}/stills.json`, JSON.stringify(stills, null, 2));
console.log('wrote', `${dir}/stills.json`);
await browser.close(); server.close();
