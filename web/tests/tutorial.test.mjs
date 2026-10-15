import test from 'node:test';
import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import { CompilerWasm, SimulatorWasm } from '../site/runtime.js';
import { DebuggerController } from '../site/debugger.js';
import { tilePositions } from '../site/shell/layout.js';
import { CHAPTERS, STEPS, openLessonWorkspace } from '../site/tutorial/steps.js';
import factory from '../dist/simulator_2.js';

const compiled = await WebAssembly.compile(await readFile(new URL('../dist/compiler.wasm', import.meta.url)));
const wasmBinary = await readFile(new URL('../dist/simulator_2.wasm', import.meta.url));
async function setup(t, file) {
  const source = await readFile(new URL(`../../compiler/examples/${file}`, import.meta.url), 'utf8');
  const compiler = await CompilerWasm.fromBytes(compiled), simulator = await SimulatorWasm.create(factory, { wasmBinary });
  t.after(() => simulator.destroy());
  const debug = new DebuggerController(simulator, { yieldFrame: () => Promise.resolve() });
  debug.load(compiler.compile(source, 2, '2x1x1'));
  return { debug, source };
}

test('chapters cover every uniquely identified lesson in order', () => {
  assert.equal(new Set(STEPS.map(step => step.id)).size, STEPS.length);
  assert.equal(new Set(CHAPTERS.map(chapter => chapter.id)).size, CHAPTERS.length);
  assert.equal(STEPS[0].id, 'welcome'); assert.equal(STEPS.at(-1).id, 'desktop');
  let previous = -1;
  for (const step of STEPS) {
    const chapter = CHAPTERS.findIndex(chapter => chapter.id === step.chapter);
    assert.ok(chapter >= previous && chapter >= 0); previous = chapter;
    assert.ok(step.title && step.text && typeof step.layout === 'function');
    assert.equal(step.action, undefined, 'lessons must not execute programs for the reader');
  }
  for (const chapter of CHAPTERS) assert.ok(STEPS.some(step => step.chapter === chapter.id));
});

test('opening every lesson only selects source, topology, targets, and tools', async () => {
  for (const step of STEPS) {
    const calls = [], record = name => (...args) => calls.push([name, ...args]);
    const ide = {
      debug: { running: false }, openFile: record('file'), setNodes: record('nodes'), selectNode: record('node'),
      selectBuildFile: record('project'), selectBuildTarget: record('target'),
      services: { applyLayout: record('layout'), selectTool: record('tab'), openWindow: record('window') },
    };
    await openLessonWorkspace(ide, step);
    assert.deepEqual(calls.find(call => call[0] === 'file')?.slice(1), step.workspace?.file ? [step.workspace.file, { focus: false }] : undefined);
    assert.deepEqual(calls.find(call => call[0] === 'tab'), ['tab', step.workspace?.tab ?? 'instructions']);
    // Every lesson retains source and the shared bottom tool panel.
    const layout = JSON.stringify(step.layout());
    assert.match(layout, /editor/); assert.match(layout, /listener/); assert.doesNotMatch(layout, /debugger/);
    const panes = tilePositions(step.layout()), tutorial = panes.get('tutorial'), code = panes.get('editor'), machine = panes.get('machine'), tools = panes.get('listener');
    assert.equal(tutorial.x, 0); assert.equal(tutorial.height, 1);
    assert.equal(code.y, 0); assert.ok(code.x >= tutorial.width);
    assert.equal(machine.y, tools.y); assert.ok(machine.x >= tools.x + tools.width - 1e-10);
    assert.equal(machine.x + machine.width, code.x + code.width);
    assert.ok(tools.y >= code.y + code.height); assert.equal(tools.x, code.x);
  }
});

test('opening a lesson waits for running execution to pause', async () => {
  let notify, arranged = false;
  const ide = { debug: { running: true }, on: (event, callback) => { notify = callback; return () => {}; },
    pause: () => queueMicrotask(() => { ide.debug.running = false; notify(); }), selectNode: () => {},
    services: { applyLayout: () => { assert.equal(ide.debug.running, false); arranged = true; }, selectTool: () => {}, openWindow: () => {} },
  };
  await openLessonWorkspace(ide, STEPS[0]); assert.ok(arranged);
});

test('ordinary local C call returns 42 without network requests', async t => {
  const { debug } = await setup(t, 'tutorial_local.c');
  assert.equal((await debug.execute()).type, 'result');
  assert.equal(debug.simulator.peek(0, 0x300), 0x10000002an);
  assert.equal(debug.network.packets.size, 0);
});

test('the same global address holds independent values on the two nodes', async t => {
  const { debug } = await setup(t, 'tutorial_memory.c');
  assert.equal((await debug.execute()).type, 'result');
  const address = debug.info.globals.find(entry => entry.name === 'observed[0]').address;
  assert.equal(debug.simulator.peek(0, address), 0x100000007n);
  assert.equal(debug.simulator.peek(1, address), 0x100000029n);
  assert.equal(debug.simulator.peek(0, 0x300), 0x1000002e5n);
});

test('a one-way send reaches the next caller statement before the remote store', async t => {
  const { debug, source } = await setup(t, 'tutorial_oneway.c');
  const line = source.split('\n').findIndex(line => line.includes('int independent = 7')) + 1;
  const id = debug.addBreakpoint({ node: 0, line });
  assert.equal((await debug.execute()).type, 'breakpoint');
  assert.equal(debug.sourceLocation(0).line, line);
  const address = debug.info.globals.find(entry => entry.name === 'observed[0]').address;
  assert.equal(debug.simulator.peek(1, address), 0x100000000n);
  assert.ok(debug.network.packets.size > 0);
  debug.breakpoints.delete(id);
  assert.equal((await debug.execute()).type, 'result');
  assert.equal(debug.simulator.peek(0, 0x300), 0x100000030n);
});

test('both futures are issued before consumption, then resolve to a result of 39', async t => {
  const { debug, source } = await setup(t, 'tutorial_futures.c');
  const line = source.split('\n').findIndex(line => line.includes('return first + second')) + 1;
  const id = debug.addBreakpoint({ node: 0, line });
  assert.equal((await debug.execute()).type, 'breakpoint');
  assert.equal(debug.sourceLocation(0).line, line);
  const requests = [...debug.network.packets.values()].filter(packet => packet.source === 0 && packet.destination === 1 && packet.returnWords > 0);
  assert.equal(requests.length, 2);
  assert.ok(requests.every(packet => !packet.resolved));
  debug.breakpoints.delete(id);
  assert.equal((await debug.execute()).type, 'result');
  assert.equal(debug.simulator.peek(0, 0x300), 0x100000027n);
});
