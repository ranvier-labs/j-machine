import { build } from "esbuild";
import { copyFile, cp, mkdir, readdir, readFile, rm, writeFile } from "node:fs/promises";
import { createHash } from "node:crypto";
import { fileURLToPath } from "node:url";

process.chdir(fileURLToPath(new URL('.', import.meta.url)));
await mkdir('dist/examples', { recursive: true });
// Remove earlier esbuild outputs so dist/ holds only the chunks this build
// references. Engine artifacts (compiler.wasm, simulator_*.{js,wasm}) stay.
for (const name of await readdir('dist')) {
  if (/^(app\.(js|css)|chunk-[\w-]+\.js|editor\.worker\.js|language\.worker\.js)(\.map)?$/.test(name) || name === 'assets') await rm(`dist/${name}`, { recursive: true, force: true });
}
// A build id derived from the frontend sources and the engine binaries. Every
// script, stylesheet, worker, and Wasm URL carries it as a query string, so a
// rebuilt site is never served from a browser cache of the previous build.
async function buildId() {
  const hash = createHash('sha256');
  const walk = async directory => { for (const entry of (await readdir(directory, { withFileTypes: true })).sort((a, b) => a.name.localeCompare(b.name))) {
    const path = `${directory}/${entry.name}`; if (entry.isDirectory()) await walk(path); else hash.update(path).update(await readFile(path));
  } };
  await walk('site');
  for (const name of (await readdir('dist')).filter(name => /\.wasm$|^simulator_\d+\.js$|^variants\.json$/.test(name)).sort()) hash.update(name).update(await readFile(`dist/${name}`));
  return hash.digest('hex').slice(0, 12);
}
const id = await buildId();
await build({
  absWorkingDir: fileURLToPath(new URL('.', import.meta.url)),
  define: { 'globalThis.__JM_BUILD_ID__': JSON.stringify(id) },
  entryPoints: {
    app: 'site/app.js',
    'editor.worker': 'node_modules/monaco-editor/esm/vs/editor/editor.worker.js',
    'language.worker': 'site/language.worker.js',
  },
  outdir: 'dist', bundle: true, format: 'esm', splitting: true,
  target: 'es2022', minify: true, sourcemap: true,
  loader: { '.ttf': 'file' }, assetNames: 'assets/[name]-[hash]',
});
for (const file of ['styles.css', 'runtime.js']) {
  await copyFile(`site/${file}`, `dist/${file}`);
}
await writeFile('dist/index.html', (await readFile('site/index.html', 'utf8')).replaceAll(/"\.\/(app\.js|app\.css|styles\.css)"/g, `"./$1?v=${id}"`));
await cp('../compiler/examples', 'dist/examples', { recursive: true });
await copyFile('site/examples.json', 'dist/examples/examples.json');
console.log(`Built Monaco, the language worker, and the simulator workbench in web/dist (build ${id}).`);
