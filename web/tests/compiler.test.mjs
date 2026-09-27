import test from 'node:test';
import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import { CompilerWasm, SimulatorWasm, parseImage } from '../site/runtime.js';
import factory from '../dist/simulator_2.js';

const module = await WebAssembly.compile(await readFile(new URL('../dist/compiler.wasm', import.meta.url)));
const simulatorBytes = await readFile(new URL('../dist/simulator_2.wasm', import.meta.url));

test('array initializer compiles through Wasm closures and executes', async t => {
  const compiler = await CompilerWasm.fromBytes(module);
  const simulator = await SimulatorWasm.create(factory, { wasmBinary: simulatorBytes });
  t.after(() => simulator.destroy());
  const source = await readFile(new URL('fixtures/array_initializer.c', import.meta.url), 'utf8');
  const image = compiler.compile(source, 2, '2x1x1');
  assert.match(image, /^\*\s/m, 'browser images should use compact broadcast records');
  const expanded = parseImage(image, 2);
  assert.equal(simulator.loadImage(image), expanded.length);
  simulator.step(10000);
  assert.equal(simulator.peek(0, 0x300), 0x100000002n);
  const snapshot = simulator.snapshot();
  simulator.loadImage(expanded.map(word => `${word.node} ${word.address.toString(16)} ${word.value.toString(16)}`).join('\n'));
  simulator.step(10000);
  assert.deepEqual(simulator.snapshot(), snapshot, 'broadcast loading must preserve execution');
});

test('larger programs reuse closed constants within the compiler memory limit', async () => {
  const compiler = await CompilerWasm.fromBytes(module);
  const source = await readFile(new URL('../../compiler/examples/historical_dirichlet.c', import.meta.url), 'utf8');
  const image = compiler.compile(source, 4, '2x2x1');
  assert.match(image, /@source \d+:\d+/);
  assert.ok(compiler.memory.buffer.byteLength < 128 * 1024 * 1024,
    'closed constants must be cached, rather than leaking on each reference');
});

// Comparison results are BOOL-tagged; `||` must not take its true branch when
// both operands are false. (Regression: BNZ on a BOOL operand.)
test('logical or of two false comparisons is false, and true cases stay true', async t => {
  const compiler = await CompilerWasm.fromBytes(module);
  const source = `int g = -1; int h = -1;
int probe(void) { return (g < 0 || g != h) ? 100 : 0; }
int main(void) {
  int a = 0; int b = 0; int c = a < 0; int d = a != b; int n = 0;
  int r = 0;
  if (a < 0 || a != b) r = r + 1;
  if (c || d) r = r + 2;
  if (a != 0 || b != 0) r = r + 4;
  while ((a < 0 || b != a) && n < 5) n++;
  r = r + n * 8;
  if (a == 0 || b == 9) r = r + 16;
  if (b == 9 || a == 0) r = r + 32;
  g = 0; h = 0;
  return r + probe() + ((a < 0 || a != b) ? 0 : 200);
}
`;
  const image = compiler.compile(source, 2, '2x1x1');
  const simulator = await SimulatorWasm.create(factory, { nodes: 2, wasmBinary: simulatorBytes });
  t.after(() => simulator.destroy());
  simulator.loadImage(image);
  let elapsed = 0;
  while (elapsed < 200000 && simulator.peek(0, 0x300) === 0n) { simulator.step(500); elapsed += 500; }
  assert.equal(simulator.peek(0, 0x300), 0x100000000n + 248n);
});
