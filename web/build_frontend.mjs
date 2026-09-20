import { build } from "esbuild";
import { copyFile, cp, mkdir } from "node:fs/promises";
import { fileURLToPath } from "node:url";

process.chdir(fileURLToPath(new URL('.', import.meta.url)));
await mkdir('dist/examples', { recursive: true });
await build({
  absWorkingDir: fileURLToPath(new URL('.', import.meta.url)),
  entryPoints: {
    app: 'site/app.js',
    'editor.worker': 'node_modules/monaco-editor/esm/vs/editor/editor.worker.js',
    'language.worker': 'site/language.worker.js',
  },
  outdir: 'dist', bundle: true, format: 'esm', splitting: true,
  target: 'es2022', minify: true, sourcemap: true,
  loader: { '.ttf': 'file' }, assetNames: 'assets/[name]-[hash]',
});
for (const file of ['index.html', 'styles.css', 'runtime.js']) {
  await copyFile(`site/${file}`, `dist/${file}`);
}
await cp('../compiler/examples', 'dist/examples', { recursive: true });
await copyFile('site/examples.json', 'dist/examples/examples.json');
console.log('Built Monaco, the language worker, and the simulator workbench in web/dist.');
