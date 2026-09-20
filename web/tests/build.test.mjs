import test from 'node:test';
import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import { VirtualFilesystem } from '../site/core/filesystem.js';
import { BuildSystem, parseBuild, buildPlan, contentHash } from '../site/core/build.js';
import { presentText, textOf, presentationValue, quoteArgument } from '../site/core/presentations.js';
import { CompilerWasm, SimulatorWasm } from '../site/runtime.js';
import factory from '../dist/simulator_2.js';
const bytes = await readFile(new URL('../dist/compiler.wasm', import.meta.url));
const module = await WebAssembly.compile(bytes), compilerId = await contentHash(bytes.toString('base64'));
const wasmBinary = await readFile(new URL('../dist/simulator_2.wasm', import.meta.url));
const graphPath = '/home/user/build.jm';
const graph = `build staged.c: copy main.c
build out/main.image: jmc staged.c
  nodes = 2
build all: phony out/main.image
default all
`;
function setup() {
  const data = new Map(), storage = { getItem: key => data.get(key), setItem: (key, value) => data.set(key, value) };
  const fs = new VirtualFilesystem(storage); fs.seed([]); fs.create(graphPath, graph);
  fs.write('/home/user/main.c', 'int main(void) { return 42; }');
  const events = []; let calls = 0;
  const compile = async (source, nodes) => { calls++; return (await CompilerWasm.fromBytes(module)).compile(source, nodes, '2x1x1'); };
  const create = (identity = compilerId, filesystem = fs) => new BuildSystem(filesystem, { compile, compilerId: identity, onEvent: event => events.push(event) });
  return { fs, storage, events, create, calls: () => calls };
}

test('build graph orders dependencies, compiles a runnable image, and persists incremental results', async t => {
  const { fs, storage, create, calls } = setup(), builder = create();
  assert.deepEqual(buildPlan(builder.graph(graphPath)).map(step => step.rule), ['copy', 'jmc', 'phony']);
  const first = await builder.build(graphPath); assert.equal(first.built, 2); assert.equal(calls(), 1);
  const validate = await builder.validateOutput(builder.graph(graphPath), '/home/user/out/main.image'); validate();
  const simulator = await SimulatorWasm.create(factory, { wasmBinary }); t.after(() => simulator.destroy());
  simulator.loadImage(fs.read('/home/user/out/main.image')); simulator.step(10000);
  assert.equal(simulator.peek(0, 0x300), 0x10000002an);
  const restored = new VirtualFilesystem(storage), second = await create(compilerId, restored).build(graphPath);
  assert.equal(second.built, 0); assert.equal(second.skipped, 2); assert.equal(calls(), 1);
  assert.equal(restored.stat('/home/user/out/main.image').metadata.artifact.sourcePath, '/home/user/staged.c');
});

test('editing one input rebuilds its dependents; unchanged content and unrelated files skip work', async () => {
  const { fs, create, calls } = setup(), builder = create(); await builder.build(graphPath);
  fs.create('/home/user/unrelated.c', 'int x;');
  assert.equal((await builder.build(graphPath)).built, 0);
  fs.setDraft('/home/user/main.c', 'int main(void) { return 73; }');
  assert.equal((await builder.build(graphPath)).built, 2); assert.equal(calls(), 2);
  assert.match(fs.read('/home/user/staged.c'), /73/);
  fs.write('/home/user/main.c', fs.read('/home/user/main.c'));
  assert.equal((await builder.build(graphPath)).built, 0);
  assert.equal((await create('different-compiler').build(graphPath)).built, 1, 'only jmc depends on the compiler identity');
});

test('changed recipe, deleted output and tampered output invalidate the appropriate targets', async () => {
  const { fs, create, events } = setup(), builder = create(); await builder.build(graphPath);
  fs.remove('/home/user/out/main.image'); assert.equal((await builder.build(graphPath)).built, 1);
  fs.write('/home/user/out/main.image', 'broken', { generated: true });
  assert.equal((await builder.build(graphPath)).built, 1);
  assert.ok(events.some(event => event.reason === 'Output content changed.'));
  fs.write(graphPath, graph.replace('nodes = 2', 'nodes = 4'));
  await assert.rejects(builder.build(graphPath), /mesh|node/i);
  assert.ok(events.some(event => event.reason === 'Node count changed.'));
});

test('missing inputs, duplicate outputs and cycles fail before writing output', async () => {
  const { fs, create } = setup(), builder = create();
  assert.throws(() => parseBuild('build a: copy main.c\nbuild a: copy main.c', graphPath), /Duplicate/);
  fs.write(graphPath, 'build a: copy b\nbuild b: copy a\ndefault a');
  await assert.rejects(builder.build(graphPath), /cycle/); assert.equal(fs.exists('/home/user/a'), false);
  fs.write(graphPath, 'build a: copy main.c\nbuild b: copy missing.c\nbuild all: phony a b\ndefault all');
  await assert.rejects(builder.build(graphPath), /Missing input/); assert.equal(fs.exists('/home/user/a'), false);
  fs.write(graphPath, 'build main.c: copy /examples/factorial.c');
  await assert.rejects(builder.build(graphPath), /overwrite a user file/);
  assert.match(fs.read('/home/user/main.c'), /42/);
});

test('compiler failure and edits during a build retain the last successful output', async () => {
  const { fs, create } = setup(), builder = create(); await builder.build(graphPath);
  const previous = fs.read('/home/user/out/main.image');
  fs.write('/home/user/main.c', 'int main(void) { return missing; }');
  await assert.rejects(builder.build(graphPath), /undeclared/);
  assert.equal(fs.read('/home/user/out/main.image'), previous);
  fs.write('/home/user/main.c', 'int main(void) { return 91; }');
  let release, entered;
  const started = new Promise(resolve => { entered = resolve; });
  builder.compile = () => { entered(); return new Promise(resolve => { release = resolve; }); };
  const pending = builder.build(graphPath); await started;
  fs.setDraft('/home/user/main.c', 'int main(void) { return 92; }'); release(previous);
  await assert.rejects(pending, /input changed/);
  assert.equal(fs.read('/home/user/out/main.image'), previous);
});

test('quoted build paths and typed listener selections retain their exact values', () => {
  const parsed = parseBuild('build "out image": copy "my file.c"\ndefault "out image"', graphPath);
  assert.equal(parsed.targets.values().next().value.inputs[0], '/home/user/my file.c');
  const text = 'Loaded /home/user/my file.c:12:3 on node 1 · line 7';
  const parts = presentText(text, ['/home/user', '/home/user/my file.c'], '/home/user/main.c');
  assert.equal(textOf(parts), text);
  assert.deepEqual(parts.filter(part => typeof part !== 'string').map(part => [part.type, presentationValue(part)]), [
    ['source', '/home/user/my file.c'], ['node', '1'], ['source', '/home/user/main.c'],
  ]);
  assert.equal(quoteArgument('/home/user/my file.c'), '"/home/user/my file.c"');
});

test('build repairs obsolete image provenance and reserves buffer outputs', async () => {
  const { fs, create } = setup(), builder = create(); await builder.build(graphPath);
  const target = '/home/user/out/main.image', artifact = fs.stat(target).metadata.artifact;
  fs.setMetadata(target, {artifact:{...artifact,sourcePath:'/home/user/scratch/main.c'}});
  assert.equal(builder.outputState(builder.graph(graphPath),target).ready,false);
  assert.equal((await builder.build(graphPath)).built,1);
  assert.equal(fs.stat(target).metadata.artifact.sourcePath,'/home/user/staged.c');
  const stable = await builder.validateOutput(builder.graph(graphPath),target);
  fs.setDraft('/home/user/main.c','int main(void) { return 99; }');
  assert.throws(stable,/changed while loading/);
  fs.write(graphPath,'build /build/buffers/claimed.image: jmc main.c');
  await assert.rejects(builder.build(graphPath),/reserved for Compile & Load/);
});
