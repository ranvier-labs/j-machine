// Compile and execute every program offered by the UI through its actual Wasm
// engines. This catches language features missing from the Wasm compiler even
// when the native compiler works. Pixel values have separate graphics tests.
import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import { CompilerWasm, SimulatorWasm } from '../site/runtime.js';
const root = new URL('../../', import.meta.url);
const dist = new URL('../dist/', import.meta.url);
const examples = JSON.parse(await readFile(new URL('../site/examples.json', import.meta.url), 'utf8')).examples;
const variants = JSON.parse(await readFile(new URL('variants.json', dist), 'utf8')).variants;
const compiled = await WebAssembly.compile(await readFile(new URL('compiler.wasm', dist)));
const expected = new Map(Object.entries({
  'factorial.c': 720, 'remote_call.c': 142, 'futures.c': 32, 'suspension.c': 41,
  'remote_bulk.c': 29, 'thread_local.c': 30, 'historical_hop.c': 0,
  'historical_dirichlet.c': 0, 'aggregates.c': 392, 'switch.c': 211, 'mesh512.c': 539,
  'distributed_mandelbrot.c': 1024, 'rule110.c': 24, 'message_hotspot.c': 32,
  'mesh_rainbow.c': 256, 'life16.c': 14, 'heat16.c': 196,
}));
const requested = process.argv.slice(2);
const selected = requested.length ? examples.filter(example => requested.includes(example.file)) : examples;
assert.equal(selected.length, requested.length || examples.length, 'unknown or duplicate example filename');
for (const example of selected) {
  const variant = variants.find(v => v.nodes === Math.max(2, example.nodes));
  const compiler = await CompilerWasm.fromBytes(compiled);
  const image = compiler.compile(await readFile(new URL(`compiler/examples/${example.file}`, root), 'utf8'), variant.nodes, variant.mesh);
  assert.match(image, /@source \d+:\d+/);
  const factory = (await import(new URL(variant.js, dist).href)).default;
  const simulator = await SimulatorWasm.create(factory, { nodes: variant.nodes, wasmBinary: await readFile(new URL(variant.wasm, dist)) });
  try {
    simulator.loadImage(image);
    simulator.traceEnabled(false);
    let elapsed = 0;
    while (elapsed < 40000000 && simulator.peek(0, 0x300) === 0n) { simulator.step(1000); elapsed += 1000; }
    assert.equal(simulator.peek(0, 0x300), 0x100000000n + BigInt(expected.get(example.file)), example.file);
    assert.ok(simulator.snapshot().nodes.every(node => !node.catastrophe), example.file);
    console.log(`${example.file}: ${variant.nodes} nodes, ${elapsed} cycles, result ${expected.get(example.file)}`);
  } finally { simulator.destroy(); }
}
console.log(`All ${selected.length} selected examples compiled and executed.`);
