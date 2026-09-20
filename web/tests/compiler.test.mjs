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
