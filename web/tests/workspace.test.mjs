import test from 'node:test';
import assert from 'node:assert/strict';
import { VirtualFilesystem, normalizePath, FILESYSTEM_KEY } from '../site/core/filesystem.js';
import { TileLayout, leaf, split, leaves, restoreLayout } from '../site/shell/layout.js';
import { parseCommand } from '../site/core/commands.js';
const storage = () => { const values = new Map(); return { getItem: key => values.get(key), setItem: (key, value) => values.set(key, value) }; };
function setup() { const saved = storage(), fs = new VirtualFilesystem(saved); fs.seed([{ file: 'factorial.c', source: 'int main(void) { return 720; }', nodes: 2 }]); return { fs, saved }; }

test('files, recovered drafts, revisions and nested directories survive a reload', () => {
  const { fs, saved } = setup();
  fs.mkdir('/home/user/project'); fs.create('/home/user/project/a.c', 'old');
  fs.setDraft('/home/user/project/a.c', 'edited');
  let restored = new VirtualFilesystem(saved);
  assert.equal(restored.read('/home/user/project/a.c'), 'edited');
  assert.equal(restored.read('/home/user/project/a.c', { draft: false }), 'old');
  restored.write('/home/user/project/a.c', 'edited');
  restored = new VirtualFilesystem(saved);
  assert.equal(restored.stat('/home/user/project/a.c').draft, undefined);
  assert.equal(restored.stat('/home/user/project/a.c').history[0].content, 'old');
  assert.equal(restored.list('/home/user/project')[0].name, 'a.c');
});
test('directory moves retain drafts; trash restore refuses to overwrite another file', () => {
  const { fs } = setup(); fs.mkdir('/home/user/project'); fs.create('/home/user/project/a.c', 'saved'); fs.setDraft('/home/user/project/a.c', 'draft');
  fs.move('/home/user/project', '/home/user/renamed');
  assert.equal(fs.read('/home/user/renamed/a.c'), 'draft');
  assert.throws(() => fs.move('/home/user/renamed', '/home/user/renamed/child'), /inside itself/);
  fs.remove('/home/user/renamed'); const trash = fs.data.trash[0];
  fs.mkdir('/home/user/renamed'); assert.throws(() => fs.restore(trash.id), /overwrite/);
  fs.move('/home/user/renamed', '/home/user/other'); fs.restore(trash.id);
  assert.equal(fs.read('/home/user/renamed/a.c'), 'draft');
});
test('example volumes are immutable; copying creates an editable file', () => {
  const { fs } = setup();
  assert.throws(() => fs.move('/home/user', '/home/renamed'), /volumes cannot be moved/);
  assert.throws(() => fs.write('/examples/factorial.c', 'changed'), /Read-only/);
  assert.throws(() => fs.remove('/examples/factorial.c'), /Read-only/);
  fs.copy('/examples/factorial.c', '/home/user/copy.c'); fs.write('/home/user/copy.c', 'changed');
  assert.notEqual(fs.read('/examples/factorial.c'), fs.read('/home/user/copy.c'));
});
test('storage failure rolls back a mutation and leaves persisted work recoverable', () => {
  const { fs, saved } = setup(), before = fs.export();
  const original = saved.setItem; saved.setItem = () => { throw new Error('quota'); };
  assert.throws(() => fs.move('/home/user/main.c', '/home/user/moved.c'), /not applied/);
  assert.equal(fs.export(), before); saved.setItem = original;
  assert.equal(new VirtualFilesystem(saved).export(), before);
});
test('legacy buffers migrate once and future seeding never overwrites user work', () => {
  const saved = storage(), fs = new VirtualFilesystem(saved);
  fs.seed([], { active: 'mine.c', buffers: { 'mine.c': { source: 'edited source', nodes: 512, breakpoints: [{ line: 3 }] } } });
  assert.equal(fs.data.session.active, '/home/user/mine.c');
  assert.equal(fs.stat('/home/user/mine.c').metadata.nodes, 512);
  fs.write('/home/user/mine.c', 'newer'); fs.seed([], { buffers: { 'mine.c': { source: 'old' } } });
  assert.equal(fs.read('/home/user/mine.c'), 'newer');
});
test('tiling, movement, closing and restoration keep each window unique', () => {
  const layout = new TileLayout(split('x', .25, leaf('files'), leaf('editor')));
  layout.open('listener', { relativeTo: 'editor', edge: 'bottom' });
  layout.open('editor'); assert.deepEqual(leaves(layout.tree), ['files', 'editor', 'listener']);
  layout.move('listener', 'files', 'top'); assert.deepEqual(leaves(layout.tree), ['listener', 'files', 'editor']);
  layout.zoom('editor'); layout.close('editor'); assert.equal(layout.zoomed, null);
  assert.ok(leaves(layout.tree).includes(layout.focused));
  const restored = restoreLayout(JSON.parse(JSON.stringify(layout.tree)), ['files', 'listener']);
  assert.deepEqual(leaves(restored), ['listener', 'files']);
  assert.deepEqual(leaves(restoreLayout(split('x', 9, leaf('files'), leaf('files')), ['files'])), ['files']);
  layout.close('files'); layout.close('listener'); assert.equal(layout.tree, null);
  layout.open('editor'); assert.deepEqual(leaves(layout.tree), ['editor']);
});
test('listener quoting and path normalization handle filenames with spaces', () => {
  assert.deepEqual(parseCommand('mv "my source.c" ../main.c'), ['mv', 'my source.c', '../main.c']);
  assert.deepEqual(parseCommand('new one\\ two.c'), ['new', 'one two.c']);
  assert.throws(() => parseCommand('edit "unfinished'), /Unfinished/);
  assert.equal(normalizePath('../user/./my source.c', '/home/user'), '/home/user/my source.c');
  assert.equal(normalizePath('~/main.c'), '/home/user/main.c');
});

test('an outdated tab cannot overwrite files committed by another tab', () => {
  const { fs, saved } = setup(), other = new VirtualFilesystem(saved);
  fs.create('/home/user/new.c', 'new work');
  assert.throws(() => other.write('/home/user/main.c', 'old tab'), /another tab/);
  assert.equal(new VirtualFilesystem(saved).read('/home/user/new.c'), 'new work');
});

test('the previous filesystem migrates without allowing an old tab to replace the new store', () => {
  const { fs } = setup(), saved = storage(), previous = JSON.parse(fs.export()); previous.version = 1;
  saved.setItem('jmc.filesystem.v1', JSON.stringify(previous));
  const migrated = new VirtualFilesystem(saved);
  assert.equal(migrated.read('/home/user/main.c'), fs.read('/home/user/main.c'));
  migrated.create('/home/user/new-work.c', 'int main(void) { return 73; }');
  saved.setItem('jmc.filesystem.v1', JSON.stringify(previous));
  assert.equal(new VirtualFilesystem(saved).read('/home/user/new-work.c'), 'int main(void) { return 73; }');
  assert.equal(JSON.parse(saved.getItem(FILESYSTEM_KEY)).version, 2);
});
