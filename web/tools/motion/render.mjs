// Renders the lookbook frame by frame: a Chrome page draws each instant of the
// piece, Playwright screenshots it, ffmpeg encodes the frames with the music.
// Usage: node tools/motion/render.mjs [--label v4]   full render → out/lookbook-<label>.mp4 (+ a 720p copy); never overwrites
//        node tools/motion/render.mjs --stills 2,9.5,25   PNGs of those seconds → out/motion/stills/
import { chromium } from '@playwright/test';
import { mkdir, readFile, readdir, rm, writeFile, access } from 'node:fs/promises';
import { createServer } from 'node:http';
import { extname, join } from 'node:path';
import { spawnSync } from 'node:child_process';

const FPS = 30, W = 1920, H = 1080;
const args = process.argv.slice(2);
const stills = args.includes('--stills') ? args[args.indexOf('--stills') + 1].split(',').map(Number) : null;
// Every render gets its own file: a label from --label, else the short commit id, plus a counter if the name is taken.
const label = args.includes('--label') ? args[args.indexOf('--label') + 1] : (spawnSync('git', ['rev-parse', '--short', 'HEAD']).stdout ?? '').toString().trim() || 'local';
const unusedName = async base => { for (let i = 0; ; i++) { const name = i ? `${base}-${i + 1}` : base; if (await access(`${name}.mp4`).then(() => false, () => true)) return name; } };
const types = { '.html': 'text/html', '.js': 'text/javascript', '.json': 'application/json', '.css': 'text/css', '.wasm': 'application/wasm', '.png': 'image/png', '.svg': 'image/svg+xml' };
const serve = root => new Promise(resolve => { const server = createServer(async (req, res) => { const path = join(root, decodeURIComponent(new URL(req.url, 'http://x').pathname).replace(/\/$/, '/index.html')); try { const body = await readFile(path); res.writeHead(200, { 'content-type': types[extname(path)] ?? 'application/octet-stream' }); res.end(body); } catch { res.writeHead(404); res.end(); } }); server.listen(0, '127.0.0.1', () => resolve({ server, url: `http://127.0.0.1:${server.address().port}` })); });

const browser = await chromium.launch({ channel: process.env.PLAYWRIGHT_CHANNEL ?? 'chrome' });
await mkdir('out/motion', { recursive: true });
// Stills of the workbench with each tool in use come from tools/motion/ide_stills.mjs.
const ideDir = 'out/motion/ide';
const stillsIndex = JSON.parse(await readFile(`${ideDir}/stills.json`, 'utf8').catch(() => { console.error('run node tools/motion/ide_stills.mjs first'); process.exit(1); }));
const data = {};
for (const file of await readdir('out/motion/data').catch(() => [])) if (file.endsWith('.json')) data[file.replace('.json', '')] = JSON.parse(await readFile(join('out/motion/data', file), 'utf8'));
data.music = JSON.parse(await readFile('out/motion/music.json', 'utf8').catch(() => '{"rms":[],"fps":30}'));
data.stills = {}; for (const [name, still] of Object.entries(stillsIndex)) data.stills[name] = { ...still, data: 'data:image/png;base64,' + (await readFile(join(ideDir, still.file))).toString('base64') };
for (const p of Object.values(data)) if (p?.samples) console.log(`${p.name}: ${p.nodes} nodes, ${p.samples.length} samples, ${p.frames.length} frames`);

const { server, url } = await serve('tools/motion');
const page = await browser.newPage({ viewport: { width: W, height: H }, deviceScaleFactor: 1 });
page.on('pageerror', error => { console.error('page error:', error.message); });
await page.addInitScript(json => { window.DATA = JSON.parse(json); }, JSON.stringify(data));
await page.goto(url + '/scene.html');
const duration = await page.evaluate(() => window.ready);
await page.evaluate(() => Promise.all(Object.values(window.DATA.stills).map(s => new Promise(resolve => { const img = new Image(); img.onload = img.onerror = resolve; img.src = s.data; }))));
console.log(`piece: ${duration.toFixed(1)} s, ${Math.ceil(duration * FPS)} frames`);
const shoot = async (t, path) => { await page.evaluate(t => window.seek(t), t); await page.screenshot({ path, type: 'png', animations: 'disabled', caret: 'hide' }); };
if (stills) {
  await mkdir('out/motion/stills', { recursive: true });
  for (const t of stills) { const path = `out/motion/stills/t${t.toFixed(1).replace('.', '_')}.png`; await shoot(t, path); console.log('wrote', path); }
} else {
  const dir = 'out/motion/frames'; await rm(dir, { recursive: true, force: true }); await mkdir(dir, { recursive: true });
  const frames = Math.ceil(duration * FPS), started = Date.now();
  for (let i = 0; i < frames; i++) { await shoot(i / FPS, `${dir}/${String(i).padStart(5, '0')}.png`); if (i % 150 === 0) console.log(`frame ${i}/${frames} · ${((Date.now() - started) / 1000).toFixed(0)}s`); }
  const output = `${await unusedName(`out/lookbook-${label}`)}.mp4`;
  // Grain, a vignette, and a one-pixel chroma shift give the flat frames a filmed look.
  const filters = 'noise=alls=9:allf=t+u,vignette=angle=PI/4.6,rgbashift=rh=1:bh=-1,format=yuv420p';
  const ff = spawnSync('ffmpeg', ['-y', '-framerate', String(FPS), '-i', `${dir}/%05d.png`, '-i', 'out/motion/music.wav', '-vf', filters, '-c:v', 'libx264', '-preset', 'slow', '-crf', '17', '-c:a', 'aac', '-b:a', '192k', '-shortest', '-movflags', '+faststart', output], { stdio: ['ignore', 'inherit', 'pipe'] });
  if (ff.status !== 0) { console.error(String(ff.stderr).split('\n').slice(-12).join('\n')); process.exit(1); }
  const small = output.replace(/\.mp4$/, '_720p.mp4');
  spawnSync('ffmpeg', ['-v', 'error', '-y', '-i', output, '-vf', 'scale=1280:720', '-c:v', 'libx264', '-preset', 'slow', '-crf', '23', '-c:a', 'aac', '-b:a', '160k', '-movflags', '+faststart', small], { stdio: 'inherit' });
  console.log(`wrote ${output} and ${small} in ${((Date.now() - started) / 1000).toFixed(0)}s`);
}
server.close(); await browser.close();
