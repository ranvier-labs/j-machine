import test from 'node:test';
import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import { CompilerWasm, SimulatorWasm } from '../site/runtime.js';
import { DebuggerController } from '../site/debugger.js';
import { NetworkTrace } from '../site/network/trace.js';
import { dimensions, coordinates, nodeAt, expectedRoute, neighbor } from '../site/network/geometry.js';
import factory from '../dist/simulator_2.js';
const compiled = await WebAssembly.compile(await readFile(new URL('../dist/compiler.wasm', import.meta.url)));
const simBytes = await readFile(new URL('../dist/simulator_2.wasm', import.meta.url));
const source = await readFile(new URL('../../compiler/examples/futures.c', import.meta.url), 'utf8');
async function setup(t) {
  const compiler = await CompilerWasm.fromBytes(compiled), simulator = await SimulatorWasm.create(factory, { wasmBinary: simBytes });
  t.after(() => simulator.destroy());
  const debug = new DebuggerController(simulator, { yieldFrame: () => Promise.resolve() });
  debug.load(compiler.compile(source, 2, '2x1x1')); return debug;
}
test('mesh coordinates and dimension-ordered paths preserve every physical neighbor', () => {
  for (const mesh of ['2x1x1', '2x2x1', '4x4x1', '8x8x8']) {
    const dims = dimensions(mesh), n = dims.reduce((a,b) => a*b);
    for (let id = 0; id < n; id++) assert.equal(nodeAt(coordinates(id, dims), dims), id);
    const path = expectedRoute(0, n - 1, dims);
    assert.equal(path.length, dims.reduce((a,b) => a+b-1, 0));
    for (const h of path) assert.equal(neighbor(h.node, h.port, dims), h.next);
  }
});
test('passive trace follows actual messages through header consumption, queue admission, and handlers', async t => {
  const d = await setup(t);
  assert.equal((await d.execute()).type, 'result');
  const trace = d.network, packets = [...trace.packets.values()];
  assert.equal(trace.dropped, 0);
  assert.ok(packets.length >= 4);
  assert.ok(packets.every(p => !p.incomplete));
  assert.ok(packets.some(p => p.source === 0 && p.destination === 1 && p.delivered && p.admitted && p.dispatched));
  assert.ok(packets.some(p => p.source === 1 && p.destination === 0 && p.delivered));
  assert.ok(trace.events.some(e => e.kind === 3));
  assert.ok(trace.events.some(e => e.kind === 10));
  const request = packets.find(p => p.reply && p.resolved);
  assert.ok(request, 'compiler mailbox metadata connects replies to future writes');
  assert.equal(trace.packets.get(request.reply).replyTo, request.id);
  assert.equal(trace.packetAt(request.id, request.sent).delivered, undefined);
  assert.equal(trace.packetAt(request.id, request.sent).resolved, undefined);
  for (const p of packets.filter(p => p.delivered)) {
    assert.equal(p.flits.length, 3 + p.words.length * 2);
    assert.deepEqual(p.hops.map(h => [h.node,h.port]), expectedRoute(p.source, p.destination, trace.dims).map(h => [h.node,h.port]));
  }
  const baseline = d.snapshot, result = d.simulator.peek(0, 0x300);
  d.simulator.traceEnabled(false); d.load(d.image);
  assert.equal((await d.execute()).type, 'result');
  assert.deepEqual(d.snapshot, baseline, 'observation must not change architectural state or completion cycle');
  assert.equal(d.simulator.peek(0, 0x300), result);
  assert.equal(d.network.events.length, 0);
});

for (const spec of [{type:'inject',destination:1},{type:'link',node:0,port:2},{type:'handler',node:1},{type:'stall',cycles:3}]) {
  test(`${spec.type} predicate stops on a real RTL observation`, async t => {
    const d = await setup(t);d.network.addBreakpoint(spec);
    const stop=await d.execute();assert.equal(stop.type,'network');
    const e=d.network.events.find(e=>e.id===stop.event);assert.ok(e);
    assert.equal(e.cycle,Number(d.snapshot.cycle));
    if(spec.type==='inject')assert.equal(e.sequence,0);
    if(spec.type==='stall')assert.ok(e.duration>=3);
    d.network.breakpoints.clear();assert.equal((await d.execute()).type,'result');
  });
}
test('capture bounds and malformed archives are explicit', () => {
  const trace=new NetworkTrace('2x1x1',{maxEvents:3,maxPackets:2});
  trace.consume(Array.from({length:10},(_,i)=>({cycle:i+1,kind:11,node:0,port:0,priority:0,aux:16,value:0,flags:0,ip:0,extra:0})));
  assert.equal(trace.events.length,3);assert.equal(trace.evicted,7);
  trace.consume([],5);assert.equal(trace.dropped,5);assert.equal(trace.buffers.size,0);
  const bad=JSON.parse(trace.export());bad.events[0].node=512;
  assert.throws(()=>NetworkTrace.import(JSON.stringify(bad)),/invalid/i);
  bad.events[0]=null;
  assert.throws(()=>NetworkTrace.import(JSON.stringify(bad)),/invalid/i);
});
test('packet eviction during execution keeps the machine running within the retention limit', async t => {
  const d=await setup(t);d.network.maxPackets=1;d.network.maxEvents=100;
  assert.equal((await d.execute()).type,'result');
  assert.equal(d.simulator.peek(0,0x300),0x100000020n);
  assert.ok(d.network.evictedPackets>0);assert.ok(d.network.packets.size<=1);assert.ok(d.network.events.length<=100);
});
test('resetting a capture cannot reuse the previous run’s historical queue state', () => {
  const trace=new NetworkTrace('2x1x1');
  const queue=occupancy=>({cycle:1,kind:11,node:0,port:0,priority:0,aux:1024,value:occupancy,flags:0,ip:0,extra:0});
  trace.consume([queue(5)]);assert.equal(trace.stateAt(1).queues[0].occupancy,5);
  trace.reset();trace.consume([queue(2)]);assert.equal(trace.stateAt(1).queues[0].occupancy,2);
});
test('network breakpoints stop at the accepted transfer and resume without an immediate re-hit', async t => {
  const d = await setup(t);
  const id = d.network.addBreakpoint({ type: 'deliver', destination: 1 });
  const stop = await d.execute(); assert.equal(stop.type, 'network');
  const p = d.network.packets.get(stop.packet); assert.equal(p.destination, 1); assert.equal(p.delivered, Number(d.snapshot.cycle));
  const snapshot = d.simulator.snapshot(); d.simulator.peek(1, 0x300); assert.deepEqual(d.simulator.snapshot(), snapshot);
  d.network.breakpoints.delete(id); assert.equal((await d.execute()).type, 'result');
  const restored = NetworkTrace.import(d.network.export({ source, image: d.image }));
  assert.equal(restored.events.length, d.network.events.length);
  assert.equal(restored.packets.size, d.network.packets.size);
  assert.equal(restored.metadata.source, source);
  assert.throws(() => restored.addBreakpoint({ type: 'stall', cycles: 0 }));
  assert.throws(() => NetworkTrace.import('{"format":"wrong"}'));
});
