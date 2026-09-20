import test from 'node:test';
import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import { CompilerWasm, SimulatorWasm, parseImage } from '../site/runtime.js';
import { DebuggerController, ipAddress, ipPhase, debugImage } from '../site/debugger.js';
import factory from '../dist/simulator_2.js';
const compiled = await WebAssembly.compile(await readFile(new URL('../dist/compiler.wasm', import.meta.url)));
const simBytes = await readFile(new URL('../dist/simulator_2.wasm', import.meta.url));
const source = 'int observed = 0;\nint main(void) {\n  observed = 41;\n  observed = 42;\n  return observed;\n}\n';
async function setup(t, text = source, hooks = {}) {
  const compiler = await CompilerWasm.fromBytes(compiled);
  const simulator = await SimulatorWasm.create(factory, { wasmBinary: simBytes });
  t.after(() => simulator.destroy());
  const debug = new DebuggerController(simulator, { yieldFrame: () => Promise.resolve(), ...hooks });
  debug.load(compiler.compile(text, 2, '2x1x1'));
  return debug;
}

test('source breakpoints stop before side effects; source step, instruction step and result work', async t => {
  const debug = await setup(t);
  assert.equal(debug.snapshot.nodes[0].registers.length, 8);
  assert.equal(debug.snapshot.nodes[0].registers[0], debug.snapshot.nodes[0].r0);
  assert.equal(debug.snapshot.nodes[0].atFetch, true);
  assert.equal(debug.info.entries.has(1), false, 'globals are not executable source breakpoints');
  const watched = debug.info.globals.find(g => g.name === 'observed[0]').address;
  const bp = debug.addBreakpoint({ line: 3 });
  assert.equal((await debug.execute()).type, 'breakpoint');
  assert.equal(debug.sourceLocation().line, 3);
  assert.equal(ipPhase(debug.snapshot.nodes[0].ip), 0);
  assert.equal(debug.simulator.peek(0, watched), 0x100000000n, 'breakpoint must precede observed = 41');
  assert.equal((await debug.execute('source')).type, 'source');
  assert.equal(debug.sourceLocation().line, 4);
  assert.equal(debug.simulator.peek(0, watched), 0x100000029n);
  debug.breakpoints.delete(bp);
  const retired = debug.snapshot.nodes[0].retired;
  assert.equal((await debug.execute('instruction')).type, 'instruction');
  assert.equal(debug.snapshot.nodes[0].retired, retired + 1n);
  assert.equal((await debug.execute()).type, 'result');
  assert.equal(debug.simulator.peek(0, 0x300), 0x10000002an);
});

test('address breakpoints, memory watches and reset retain useful stop state', async t => {
  const debug = await setup(t);
  const address = debug.info.entries.get(3)[0];
  const bp = debug.addBreakpoint({ address, node: 0 });
  assert.equal((await debug.execute()).type, 'breakpoint');
  assert.equal(ipAddress(debug.snapshot.nodes[0].ip), address);
  debug.breakpoints.delete(bp);
  const watched = debug.info.globals[0].address;
  debug.addWatchpoint(0, watched);
  assert.equal((await debug.execute()).type, 'watchpoint');
  assert.equal(debug.simulator.peek(0, watched), 0x100000029n);
  assert.equal((await debug.execute()).type, 'watchpoint');
  assert.equal(debug.simulator.peek(0, watched), 0x10000002an);
  assert.equal((await debug.execute()).type, 'result');
  debug.load(debug.image);
  assert.equal(debug.snapshot.cycle, 0n);
  assert.equal((await debug.execute()).type, 'watchpoint');
});

test('pause freezes the whole mesh; reading memory and snapshots does not clock the model', async t => {
  let debug;
  debug = await setup(t, 'int main(void) { while (1) {} return 0; }', { yieldFrame: async () => debug.pause() });
  assert.equal((await debug.execute()).type, 'paused');
  const snapshot = debug.snapshot;
  for (let i = 0; i < 10; i++) {
    debug.simulator.peek(0, 0x300); debug.simulator.peek(1, 0x300);
    assert.deepEqual(debug.simulator.snapshot(), snapshot);
  }
  assert.equal(debug.running, false);
  const cycle = snapshot.cycle;
  await debug.execute('cycles', 1);
  assert.equal(debug.snapshot.cycle, cycle + 1n);
});

test('recursive breakpoints re-arm after continue', async t => {
  const source = await readFile(new URL('../../compiler/examples/factorial.c', import.meta.url), 'utf8');
  const debug = await setup(t, source);
  debug.addBreakpoint({ line: 6 });
  assert.equal((await debug.execute()).type, 'breakpoint');
  const first = debug.snapshot.cycle;
  assert.equal((await debug.execute()).type, 'breakpoint');
  assert.ok(debug.snapshot.cycle > first);
  debug.breakpoints.clear();
  assert.equal((await debug.execute()).type, 'result');
  assert.equal(debug.simulator.peek(0, 0x300), 0x1000002d0n);
});

test('cycle budget and fault stop are explicit; invalid images preserve the loaded machine', async t => {
  const debug = await setup(t, 'int value = 2147483647; int main(void) { return value + 1; }');
  debug.breakOnFault = true;
  assert.equal((await debug.execute()).type, 'fault');
  const snapshot = debug.simulator.snapshot();
  assert.throws(() => debug.load('0 000gg garbage'), /invalid|BigInt/i);
  assert.deepEqual(debug.simulator.snapshot(), snapshot);
  debug.load(debug.image);
  debug.maxCycles = 1;
  assert.equal((await debug.execute()).type, 'limit');
  assert.equal(debug.snapshot.cycle, 1n);
});
