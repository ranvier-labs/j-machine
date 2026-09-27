// Runs before publishing a rebuilt compiler into dist. No simulator build is
// needed: exercise the real Lean compiler over every source exposed by the UI.
import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import { CompilerWasm } from '../site/runtime.js';

const root = new URL('../../', import.meta.url);
const module = await WebAssembly.compile(await readFile(process.argv[2] ?? new URL('../dist/compiler.wasm', import.meta.url)));
const { examples } = JSON.parse(await readFile(new URL('../site/examples.json', import.meta.url), 'utf8'));
for (const example of examples) {
  const compiler = await CompilerWasm.fromBytes(module);
  const nodes = Math.max(2, example.nodes);
  const mesh = { 2: '2x1x1', 4: '2x2x1', 16: '4x4x1', 512: '8x8x8' }[nodes];
  assert.ok(mesh, `${example.file}: no mesh for ${nodes} nodes`);
  const source = await readFile(new URL(`compiler/examples/${example.file}`, root), 'utf8');
  const image = compiler.compile(source, nodes, mesh);
  assert.match(image, /@source \d+:\d+/);
  assert.ok(image.includes(`${nodes - 1}  `), `${example.file}: highest node is missing`);
  console.log(`${example.file}: compiled for ${nodes} nodes`);
}
const compiler = await CompilerWasm.fromBytes(module);
assert.throws(() => compiler.compile('int main(void) { return missing; }'), { name: 'JmcCompileError' });
assert.match(compiler.compile('int main(void) { int values[2] = {1, 2}; return values[1]; }'), /@source/);
console.log('Compiler source-error recovery and array-initializer regression passed.');
