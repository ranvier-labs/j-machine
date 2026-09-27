// Records a demo of the workbench: the tutorial performed step by step in a
// real Chrome, captured by Playwright, then encoded to MP4 with ffmpeg.
// Usage: node tools/record_demo.mjs [http://127.0.0.1:8017] [out/demo.mp4]
import { chromium } from '@playwright/test';
import { mkdir, readdir, rename, rm } from 'node:fs/promises';
import { spawnSync } from 'node:child_process';

const base = process.argv[2] ?? 'http://127.0.0.1:8017', output = process.argv[3] ?? 'out/demo.mp4';
const size = { width: 1600, height: 900 }, dir = 'out/video-frames';
await rm(dir, { recursive: true, force: true }); await mkdir(dir, { recursive: true });
const browser = await chromium.launch({ channel: process.env.PLAYWRIGHT_CHANNEL ?? 'chrome' });
const context = await browser.newContext({ viewport: size, deviceScaleFactor: 1, recordVideo: { dir, size } });
const page = await context.newPage();
const pause = seconds => page.waitForTimeout(seconds * 1000);
const status = () => page.locator('#status-text');
const tour = page.locator('[data-window=tutorial]');
const doIt = tour.locator('.tutorial-actions button').first(), next = tour.getByRole('button', { name: 'Next step' }), done = tour.locator('.tutorial-done');
const waitDone = async (seconds = 240) => { await page.waitForFunction(() => document.querySelector('.tutorial-done')?.textContent.includes('Done'), null, { timeout: seconds * 1000 }); };
const banner = async (text, seconds = 2.5) => {
  await page.evaluate(text => {
    let node = document.getElementById('demo-banner');
    if (!node) { node = document.createElement('div'); node.id = 'demo-banner'; document.body.append(node);
      // The caption never takes pointer events: an invisible overlay would
      // otherwise keep Playwright's clicks on the tour's buttons from landing.
      Object.assign(node.style, { position: 'fixed', left: '50%', bottom: '64px', transform: 'translateX(-50%)', padding: '12px 22px', background: '#111110', color: '#d7ae68', border: '1px solid #d7ae68', font: '15px Menlo, monospace', letterSpacing: '.04em', zIndex: 1000, boxShadow: '0 12px 40px #000c', pointerEvents: 'none' }); }
    node.textContent = text; node.hidden = false;
  }, text);
  await pause(seconds);
  await page.evaluate(() => { const node = document.getElementById('demo-banner'); if (node) node.hidden = true; });
};
const mouseTo = async locator => { const box = await locator.boundingBox().catch(() => null); if (box) await page.mouse.move(box.x + box.width / 2, box.y + box.height / 2, { steps: 12 }); };
const started = Date.now();
const log = text => console.log(`[${((Date.now() - started) / 1000).toFixed(0).padStart(4)}s] ${text}`);
// A click that cannot land within 15 s is skipped rather than stalling the recording.
const press = async locator => { await mouseTo(locator); await pause(.4); try { await locator.click({ timeout: 15_000 }); } catch (error) { log(`click skipped: ${String(error.message).split('\n')[0]}`); } };

await page.goto(base + '/'); await page.evaluate(() => localStorage.clear()); await page.goto(base + '/');
await status().filter({ hasText: /Loaded \/home\/user\/main\.c/ }).waitFor({ timeout: 90_000 });
await banner('J-Machine · a 1991 message-driven multicomputer, cycle-accurate in your browser', 4);
// Each step waits for its done mark up to `timeout` seconds, then lingers
// `watch` seconds. The sixteen-node programs and the 512-node mesh run at the
// pace of a cycle-accurate model, so they are shown while running rather than
// waited for; the tour's own text says so.
const steps = [
  { watch: 3, timeout: 40 }, { watch: 3, timeout: 40 },
  { watch: 2, timeout: 40, after: async () => { for (let i = 0; i < 6; i++) { await page.keyboard.press('F10'); await pause(.6); } await pause(1); await page.keyboard.press('F11'); await pause(1.5); } },
  { watch: 3, timeout: 40 }, { watch: 5, timeout: 15 }, { watch: 6, timeout: 60 }, { watch: 3, timeout: 40 }, { watch: 22, timeout: 20 },
  { watch: 45, timeout: 20 }, { watch: 45, timeout: 20 }, { watch: 25, timeout: 75 }, { watch: 3, timeout: 20 },
];
for (const [index, step] of steps.entries()) {
  await pause(index === 0 ? 3 : 2.2);
  log(`step ${index + 1}: ${await doIt.textContent()}`);
  await press(doIt);
  try { await waitDone(step.timeout); log('  done'); } catch { log('  still running; moving on'); }
  await pause(step.watch);
  if (step.after) await step.after();
  await press(next);
}
log('last step');
await pause(2);
await press(doIt);
await pause(2);
await banner('github.com/ranvier-labs/j-machine · j-machine.pages.dev', 4);
await context.close(); await browser.close();
const [webm] = (await readdir(dir)).filter(name => name.endsWith('.webm'));
await mkdir('out', { recursive: true });
const encoded = spawnSync('ffmpeg', ['-y', '-loglevel', 'error', '-i', `${dir}/${webm}`, '-c:v', 'libx264', '-preset', 'slow', '-crf', '20', '-pix_fmt', 'yuv420p', '-movflags', '+faststart', output], { stdio: 'inherit' });
if (encoded.status !== 0) { await rename(`${dir}/${webm}`, output.replace(/\.mp4$/, '.webm')); console.log(`ffmpeg failed; kept ${output.replace(/\.mp4$/, '.webm')}`); }
else console.log(`Wrote ${output}`);
