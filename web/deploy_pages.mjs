// Stages web/dist for Cloudflare Pages and deploys it with wrangler. The
// project was created once with `wrangler pages project create j-machine
// --production-branch main --force` (classic Pages; without --force wrangler
// 4.138 delegates to the Workers-based Pages and needs a Worker config).
// Uploads prefer IPv4: with the default address order the multipart uploads
// die with EPIPE/ETIMEDOUT from this network.
// Pages rejects single files above 25 MiB, so larger binaries are split into
// parts with a `<name>.parts.json` listing that runtime.js reassembles.
import { cp, mkdir, readdir, readFile, rm, stat, writeFile } from 'node:fs/promises';
import { spawnSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';

process.chdir(fileURLToPath(new URL('.', import.meta.url)));
const project = process.env.PAGES_PROJECT ?? 'j-machine', branch = process.env.PAGES_BRANCH ?? 'main';
const LIMIT = 24 * 1024 * 1024, PART = 20 * 1024 * 1024;
const staged = 'dist-pages';
await rm(staged, { recursive: true, force: true });
await cp('dist', staged, { recursive: true, filter: source => !source.endsWith('.map') });
let split = 0; const immutable = [];
for (const name of await readdir(staged)) {
  const path = `${staged}/${name}`, info = await stat(path);
  if (!info.isFile() || info.size <= LIMIT) continue;
  const bytes = await readFile(path), parts = [];
  for (let offset = 0; offset < bytes.length; offset += PART) { const part = `${name}.part${parts.length}`; await writeFile(`${staged}/${part}`, bytes.subarray(offset, offset + PART)); parts.push(part); }
  await writeFile(`${path}.parts.json`, JSON.stringify({ size: bytes.length, parts })); immutable.push(...parts, `${name}.parts.json`);
  await rm(path); split++;
  console.log(`${name}: ${bytes.length} bytes in ${parts.length} parts`);
}
await writeFile(`${staged}/_headers`, `/index.html
  Cache-Control: no-cache
/*.wasm
  Cache-Control: public, max-age=31536000, immutable
${immutable.map(name => `/${name}
  Cache-Control: public, max-age=31536000, immutable
`).join('')}/*.js
  Cache-Control: public, max-age=31536000, immutable
/*.css
  Cache-Control: public, max-age=31536000, immutable
`);
console.log(`Staged ${staged} (${split} files split).`);
if (process.argv.includes('--stage-only')) process.exit(0);
const result = spawnSync('npx', ['wrangler', 'pages', 'deploy', staged, '--project-name', project, '--branch', branch, '--commit-dirty=true'], { stdio: 'inherit', env: { ...process.env, NODE_OPTIONS: [process.env.NODE_OPTIONS, '--dns-result-order=ipv4first'].filter(Boolean).join(' ') } });
process.exit(result.status ?? 1);
