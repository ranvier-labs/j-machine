import test from 'node:test';
import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import { VirtualFilesystem } from '../site/core/filesystem.js';
import { IDE } from '../site/core/ide.js';
import { projectSelection, projectFiles, chooseProjectImage } from '../site/core/project.js';
import { CompilerWasm, SimulatorWasm } from '../site/runtime.js';
import factory from '../dist/simulator_2.js';

const module = await WebAssembly.compile(await readFile(new URL('../dist/compiler.wasm', import.meta.url)));
const wasmBinary = await readFile(new URL('../dist/simulator_2.wasm', import.meta.url));
const source = 'int observed = 0;\nint main(void) {\n  observed = 41;\n  return observed;\n}\n';
const variants = [{ nodes: 2, mesh: '2x1x1' }];
// Exercise the IDE controller with the real compiler and RTL simulator. The
// editor adapter stands in for Monaco's document/version API, not its UI.
async function setup(t) {
  const entries = new Map(), storage = { getItem: key => entries.get(key), setItem: (key, value) => entries.set(key, value) };
  const fs = new VirtualFilesystem(storage); fs.seed([{ file: 'factorial.c', source, nodes: 2 }]);
  const compiler = await CompilerWasm.fromBytes(module), models = new Map();
  let active, version = 0;
  const editor = {
    async initialize() {}, configure() {}, model: null, breakpointDecorations: { getRange() {} },
    setSource(text, path) { if (!models.has(path)) models.set(path, { text, version: ++version }); active = path; this.model = models.get(path); },
    getText(path) { return models.get(path)?.text; }, getVersion(path = active) { return models.get(path)?.version; },
    syncSource(path, text) { const item = models.get(path); if (item && item.text !== text) { item.text = text; item.version = ++version; } },
    close(path) { models.delete(path); if (active === path) { active = null; this.model = null; } },
    setBreakpoints() {}, showExecution() {}, reveal() {},
    async compile() { return { image: compiler.compile(models.get(active).text, 2, '2x1x1') }; },
  };
  const ide = new IDE(fs, variants, { createSimulator: () => SimulatorWasm.create(factory, { wasmBinary }) });
  t.after(() => { clearTimeout(ide.draftTimer); ide.simulator?.destroy(); });
  await ide.initialize(editor);
  assert.ok(ide.debug?.image, ide.status);
  const edit = (path, text) => { editor.syncSource(path, text); ide.edited(path, text); };
  return { ide, fs, storage, editor, edit, compiler };
}

test('switching buffers preserves the loaded program and its source breakpoint', async t => {
  const { ide, fs } = await setup(t), compiled = '/home/user/main.c';
  ide.toggleBreakpoint(3);
  fs.create('/home/user/other.c', 'int main(void) { return 99; }'); ide.openFile('/home/user/other.c');
  assert.equal(ide.compiledPath, compiled); assert.equal(ide.stale, false);
  assert.equal(ide.debug.breakpoints.size, 1);
  await ide.execute();
  assert.equal(ide.debug.stopReason.type, 'breakpoint');
  assert.equal(ide.activePath, compiled, 'a source stop visits the loaded buffer');
  assert.equal(ide.debug.sourceLocation().line, 3);
  await ide.execute(); assert.equal(ide.simulator.peek(0, 0x300), 0x100000029n);
});

test('drafts, moving an open project, closing buffers and session reload retain source', async t => {
  const { ide, fs, editor, storage, edit } = await setup(t);
  fs.mkdir('/home/user/project'); ide.newFile('/home/user/project/work.c');
  const draft = 'int main(void) { return 73; }'; edit(ide.activePath, draft);
  ide.openFile('/home/user/main.c');
  assert.equal(fs.read('/home/user/project/work.c'), draft);
  fs.move('/home/user/project', '/home/user/renamed');
  assert.ok(ide.openPaths.includes('/home/user/renamed/work.c'));
  ide.openFile('/home/user/renamed/work.c'); assert.equal(editor.getText(ide.activePath), draft);
  ide.closeFile(ide.activePath); ide.openFile('/home/user/renamed/work.c');
  assert.equal(editor.getText(ide.activePath), draft);
  ide.save();
  const restored = new VirtualFilesystem(storage);
  assert.equal(restored.read(ide.activePath, { draft: false }), draft);
  assert.equal(restored.data.session.active, ide.activePath);
  assert.equal(restored.stat(ide.activePath).history.length, 1);
});

test('changed source disables execution and a stale compile cannot replace the machine', async t => {
  const { ide, fs, editor, edit } = await setup(t), oldImage = ide.debug.image;
  let resolve; editor.compile = () => new Promise(done => { resolve = done; });
  const compiling = ide.compile();
  edit(ide.activePath, 'int main(void) { return 88; }');
  resolve({ image: oldImage }); await compiling;
  assert.equal(ide.debug.image, oldImage); assert.equal(ide.stale, true); assert.equal(ide.canRun(), false);
  await assert.rejects(ide.execute(), /changed/);
  assert.match(ide.status, /changed or closed during compilation/);
  ide.flush(); fs.move('/home/user/main.c', '/home/user/renamed.c');
  assert.equal(ide.compiledPath, '/home/user/renamed.c'); assert.equal(ide.stale, true);
});

test('listener operates on virtual paths with spaces and preserves trashed drafts', async t => {
  const { ide, fs, edit } = await setup(t);
  await ide.command('mkdir "my project"'); await ide.command('cd "my project"');
  await ide.command('new "first file.c"'); edit(ide.activePath, 'int main(void) { return 12; }');
  await ide.command('CP "first file.c" copy.c');
  assert.equal(fs.read('/home/user/my project/copy.c'), 'int main(void) { return 12; }');
  await ide.command('trash "first file.c"'); assert.equal(ide.openPaths.includes('/home/user/my project/first file.c'), false);
  await ide.command('restore'); await ide.command('edit "first file.c"');
  assert.equal(ide.text(), 'int main(void) { return 12; }');
});

test('a built image loads without switching buffers and upstream edits make its machine stale', async t => {
  const { ide, fs, editor, edit, compiler } = await setup(t);
  editor.compilerIdentity = async () => 'test-compiler';
  editor.compileSource = async text => ({ image: compiler.compile(text, 2, '2x1x1') });
  fs.create('/home/user/build.jm', 'build staged.c: copy main.c\nbuild out.image: jmc staged.c\ndefault out.image');
  await ide.initializeBuilder();
  assert.equal((await ide.build()).built, 2);
  assert.equal((await ide.build()).skipped, 2);
  ide.newFile('/home/user/other.c');
  await ide.loadArtifact('/home/user/out.image');
  assert.equal(ide.activePath, '/home/user/other.c');
  assert.equal(ide.compiledPath, '/home/user/staged.c');
  assert.equal(ide.canRun(), true);
  await ide.execute(); assert.equal(ide.simulator.peek(0, 0x300), 0x100000029n);
  edit('/home/user/main.c', 'int main(void) { return 88; }');
  assert.equal(ide.stale, true); assert.equal(ide.canRun(), false);
});

test('mouse presentations visit exact paths and insert quoted arguments without executing them', async t => {
  const { ide, fs } = await setup(t); let inserted;
  ide.services.insertListener = (value, replace) => { inserted = { value, replace }; };
  fs.create('/home/user/my file.c', 'int main(void) { return 0; }');
  const path = { type: 'path', path: '/home/user/my file.c', text: 'my file.c' };
  await ide.selectPresentation(path, true);
  assert.equal(inserted.value, '"/home/user/my file.c"'); assert.equal(ide.activePath, '/home/user/main.c');
  await ide.selectPresentation(path); assert.equal(ide.activePath, path.path);
  await ide.selectPresentation({ type: 'command', command: 'trash "my file.c"', text: 'trash "my file.c"' });
  assert.equal(inserted.replace, true); assert.equal(fs.exists(path.path), true);
  await ide.command('ls');
  assert.ok(ide.logs.at(-1).parts.some(part => part.type === 'path' && part.path === path.path));
});

test('listener documentation links visit topics and Shift inserts their value', async t => {
  const { ide } = await setup(t); let visited, inserted;
  ide.services.openDocumentation = topic => { visited = topic; };
  ide.services.insertListener = value => { inserted = value; };
  await ide.command('help');
  const topic = ide.logs.at(-1).parts.find(part => part.type === 'documentation' && part.topic === 'build');
  assert.ok(topic);
  await ide.selectPresentation(topic, true); assert.equal(inserted, 'build'); assert.equal(visited, undefined);
  await ide.selectPresentation(topic); assert.equal(visited, 'build');
  await ide.command('doc future mailbox'); assert.equal(visited, 'future mailbox');
  await ide.command('help keyboard'); assert.equal(visited, 'keyboard');
});

test('project target selection drives build and load, with explicit choice for image groups', async t => {
  const { ide, fs, editor, compiler } = await setup(t);
  editor.compilerIdentity = async () => 'test-compiler';
  editor.compileSource = async text => ({ image: compiler.compile(text, 2, '2x1x1') });
  fs.create('/home/user/build.jm', 'build a.image: jmc main.c\nbuild b.image: jmc main.c\nbuild all: phony a.image b.image\ndefault a.image');
  fs.create('/home/user/other.jm', 'build only.image: jmc main.c');
  await ide.initializeBuilder();
  assert.deepEqual(projectSelection(ide).images, []);
  assert.throws(() => chooseProjectImage(ide), /Build the selected target/);
  let opened; ide.services.openWindow = id => { opened = id; };
  ide.selectBuildTarget('b.image');
  await ide.build(); assert.equal(opened, 'build');
  assert.equal(fs.exists('/home/user/a.image'), false);
  assert.deepEqual(projectSelection(ide).images, ['/home/user/b.image']);
  await chooseProjectImage(ide); assert.equal(ide.imagePath, '/home/user/b.image');
  ide.selectBuildTarget('all'); await ide.build();
  let choices; ide.services.choose = entries => { choices = entries; };
  await chooseProjectImage(ide); assert.equal(choices.length, 2);
  await choices[0].run(); assert.equal(ide.imagePath, '/home/user/a.image');
  assert.throws(() => ide.selectBuildTarget('missing'), /Unknown target/);
  fs.write('/home/user/build.jm', 'build a.image: jmc main.c');
  assert.equal(projectSelection(ide).target, null, 'removing a selected target restores defaults');
  assert.equal((await ide.build()).skipped, 1); assert.equal(ide.buildTarget, null);
  assert.ok(projectFiles(ide).includes('/home/user/other.jm'));
  ide.selectBuildFile('/home/user/other.jm'); assert.equal(ide.buildTarget, null);
  assert.deepEqual(projectSelection(ide).selected, ['/home/user/only.image']);
});

test('buffer images cannot collide with project targets or other buffers named main.c', async t => {
  const { ide, fs, editor, compiler } = await setup(t), firstBufferImage = ide.imagePath;
  editor.compilerIdentity = async () => 'test-compiler';
  editor.compileSource = async text => ({ image: compiler.compile(text, 2, '2x1x1') });
  fs.create('/home/user/build.jm', 'build /build/main.image: jmc main.c');
  await ide.initializeBuilder(); await ide.build();
  const projectImage = fs.read('/build/main.image');
  fs.mkdir('/home/user/scratch'); fs.create('/home/user/scratch/main.c', 'int main(void) { return 99; }');
  ide.openFile('/home/user/scratch/main.c'); await ide.compile();
  assert.notEqual(ide.imagePath, firstBufferImage);
  assert.notEqual(ide.imagePath, '/build/main.image');
  assert.equal(fs.read('/build/main.image'), projectImage);
  await chooseProjectImage(ide); await ide.execute();
  assert.equal(ide.compiledPath, '/home/user/main.c');
  assert.equal(ide.simulator.peek(0, 0x300), 0x100000029n);
});

test('failed Compile & Load retains inspection state and blocks execution until an explicit load', async t => {
  const { ide, fs } = await setup(t), previous = ide.debug, imagePath = ide.imagePath;
  fs.create('/home/user/broken.c', 'int main(void) { return undeclared; }');
  ide.openFile('/home/user/broken.c'); await ide.compile();
  assert.equal(ide.debug, previous); assert.equal(ide.canRun(), false);
  assert.equal(ide.commandState('continue').enabled, false);
  assert.equal(ide.commandState('step-cycle').enabled, false);
  assert.equal(ide.commandState('restart').enabled, false);
  await assert.rejects(ide.execute(), /Compile & Load failed/);
  assert.equal(previous.snapshot.cycle, 0n);
  await ide.loadArtifact(imagePath); await ide.execute();
  assert.equal(ide.simulator.peek(0, 0x300), 0x100000029n);
});

test('Run, Continue, completion, Reset, and Restart have distinct execution semantics', async t => {
  const { ide } = await setup(t);
  assert.equal(ide.commandState('continue').label, 'Run');
  await ide.execute('cycles', 1);
  assert.equal(ide.commandState('continue').label, 'Continue');
  await ide.execute(); const completedCycle = ide.debug.snapshot.cycle;
  assert.equal(ide.debug.completed, true); assert.equal(ide.canRun(), false);
  await assert.rejects(ide.execute(), /Main has returned/);
  assert.equal(ide.debug.snapshot.cycle, completedCycle);
  assert.equal(ide.commandState('restart').enabled, true);
  ide.reset(); assert.equal(ide.debug.snapshot.cycle, 0n); assert.equal(ide.commandState('continue').label, 'Run');
  await ide.execute('cycles', 1); await ide.restart();
  assert.equal(ide.debug.completed, true); assert.equal(ide.debug.snapshot.cycle, completedCycle);
  assert.equal(ide.simulator.peek(0, 0x300), 0x100000029n);
  assert.equal(ide.commandState('step-cycle').enabled, true, 'explicit cycle stepping remains available for post-return hardware inspection');
});

test('opening a graph is distinct from activating it, and selected targets survive reload', async t => {
  const { ide, fs, editor, storage, compiler } = await setup(t);
  editor.compilerIdentity = async () => 'test-compiler';
  editor.compileSource = async text => ({ image: compiler.compile(text, 2, '2x1x1') });
  fs.create('/home/user/build.jm', 'build first.image: jmc main.c');
  fs.create('/home/user/other.jm', 'build a.image: jmc main.c\nbuild b.image: jmc main.c');
  await ide.initializeBuilder(); ide.openFile('/home/user/other.jm');
  assert.equal(ide.buildFile, '/home/user/build.jm');
  assert.equal(ide.commandState('use-buffer-build').enabled, true);
  ide.selectBuildFile(ide.activePath); ide.selectBuildTarget('b.image');
  assert.equal(ide.commandState('use-buffer-build').enabled, false);
  ide.selectBuildFile(ide.activePath); assert.equal(ide.buildTarget, '/home/user/b.image', 'reselecting the same graph preserves its target');
  const restored = new IDE(new VirtualFilesystem(storage), variants);
  assert.equal(restored.buildFile, '/home/user/other.jm'); assert.equal(restored.buildTarget, '/home/user/b.image');
  await ide.selectPresentation({type:'target',manifest:'/home/user/other.jm',target:'/home/user/a.image'});
  assert.equal(new VirtualFilesystem(storage).data.session.buildTarget, '/home/user/a.image');
});

test('Project Load rejects altered output and graph ownership even when metadata remains', async t => {
  const { ide, fs, editor, compiler } = await setup(t);
  editor.compilerIdentity = async () => 'test-compiler';
  editor.compileSource = async text => ({ image: compiler.compile(text, 2, '2x1x1') });
  fs.create('/home/user/build.jm', 'build /build/main.image: jmc main.c');
  fs.create('/home/user/other.jm', 'build /build/main.image: jmc main.c');
  await ide.initializeBuilder(); await ide.build();
  const previous = ide.debug;
  fs.write('/build/main.image', fs.read('/build/main.image') + '\n# altered', {generated:true});
  await assert.rejects(chooseProjectImage(ide), /built input or output changed/);
  assert.equal(ide.debug, previous);
  await ide.build(); ide.selectBuildFile('/home/user/other.jm');
  assert.deepEqual(projectSelection(ide).images, []);
  assert.equal(ide.commandState('load-project').enabled, false);
  await ide.build(); assert.equal(fs.stat('/build/main.image').metadata.build.manifest, '/home/user/other.jm');
  await chooseProjectImage(ide); assert.equal(ide.imagePath, '/build/main.image');
  fs.write('/home/user/other.jm', 'build /build/main.image: jmc main.c\nbuild /build/selected.image: copy /build/main.image\ndefault /build/selected.image');
  await ide.build();
  assert.deepEqual(projectSelection(ide).images, ['/build/selected.image'], 'Load selects the requested image, not its intermediate image dependency');
  await chooseProjectImage(ide); assert.equal(ide.imagePath, '/build/selected.image');
});
