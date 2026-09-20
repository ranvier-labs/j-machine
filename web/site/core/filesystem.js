export const FILESYSTEM_KEY = 'jmc.filesystem.v2';

export function normalizePath(value, cwd = '/home/user') {
  if (typeof value !== 'string' || /[\0-\x1f]/.test(value)) throw new Error('Invalid pathname.');
  value = value.replace(/^~(?=\/|$)/, '/home/user');
  const parts = (value.startsWith('/') ? value : `${cwd}/${value}`).split('/');
  const result = [];
  for (const part of parts) {
    if (!part || part === '.') continue;
    if (part === '..') result.pop(); else result.push(part);
  }
  return `/${result.join('/')}`;
}
export const basename = path => path.split('/').filter(Boolean).at(-1) ?? '/';
export const dirname = path => normalizePath(path).split('/').slice(0, -1).join('/') || '/';
const within = (path, parent) => path === parent || path.startsWith(`${parent}/`);
const fresh = () => ({ version: 2, entries: { '/': { kind: 'directory', created: 0 } }, trash: [], session: {} });

// All mutations commit atomically. A quota/storage failure leaves both the
// in-memory filesystem and the last persisted filesystem unchanged.
export class VirtualFilesystem {
  constructor(storage, key = FILESYSTEM_KEY) {
    this.storage = storage; this.key = key; this.listeners = new Set();
    const raw = storage?.getItem(key);
    this.persisted = raw ?? null;
    // Import the earlier filesystem once, then use a separate store. Tabs
    // running the earlier code cannot overwrite this generation's files.
    const imported = raw ?? (key === FILESYSTEM_KEY ? storage?.getItem('jmc.filesystem.v1') : null);
    if (imported) {
      try {
        this.data = JSON.parse(imported);
        if (![1, 2].includes(this.data.version) || this.data.entries?.['/']?.kind !== 'directory'
          || !Array.isArray(this.data.trash)) throw new Error();
        this.data.version = 2;
      } catch { throw new Error('The saved filesystem could not be read. Its stored data has been retained.'); }
    } else this.data = fresh();
  }
  onChange(listener) { this.listeners.add(listener); return () => this.listeners.delete(listener); }
  commit(type, update, detail = {}) {
    if (this.storage && (this.storage.getItem(this.key) ?? null) !== this.persisted) throw new Error('Files changed in another tab. Export any local edits, then reload this tab to use the latest filesystem.');
    const next = structuredClone(this.data);
    const result = update(next);
    const serialized = JSON.stringify(next);
    try { this.storage?.setItem(this.key, serialized); }
    catch { throw new Error('The filesystem could not be saved. Export files to keep a separate copy; this operation was not applied.'); }
    this.data = next; this.persisted = serialized;
    for (const listener of this.listeners) listener({ type, ...detail });
    return result;
  }
  exists(path) { return Object.hasOwn(this.data.entries, normalizePath(path)); }
  stat(path) {
    path = normalizePath(path);
    const entry = this.data.entries[path];
    if (!entry) throw new Error(`No such file or directory: ${path}`);
    return { ...structuredClone(entry), path, name: basename(path) };
  }
  list(path = '/') {
    path = normalizePath(path);
    if (this.stat(path).kind !== 'directory') throw new Error(`Not a directory: ${path}`);
    return Object.keys(this.data.entries).filter(p => p !== path && dirname(p) === path)
      .map(p => this.stat(p)).sort((a, b) => (a.kind === b.kind ? 0 : a.kind === 'directory' ? -1 : 1)
        || a.name.localeCompare(b.name));
  }
  files() { return Object.keys(this.data.entries).filter(p => this.data.entries[p].kind === 'file').sort(); }
  read(path, { draft = true } = {}) {
    const entry = this.stat(path);
    if (entry.kind !== 'file') throw new Error(`Not a file: ${entry.path}`);
    return draft && entry.draft !== undefined ? entry.draft : entry.content;
  }
  assertWritable(data, path) {
    for (let current = path; ; current = dirname(current)) {
      if (data.entries[current]?.readOnly) throw new Error(`Read-only volume: ${current}. Copy the file into /home/user to edit it.`);
      if (current === '/') break;
    }
  }
  assertParent(data, path) {
    if (path === '/' || data.entries[dirname(path)]?.kind !== 'directory') throw new Error(`Parent directory does not exist: ${dirname(path)}`);
  }
  mkdir(path) {
    path = normalizePath(path);
    return this.commit('create', data => {
      this.assertWritable(data, path); this.assertParent(data, path);
      if (data.entries[path]) throw new Error(`Path already exists: ${path}`);
      data.entries[path] = { kind: 'directory', created: Date.now() };
    }, { path });
  }
  create(path, content = '', metadata = {}) {
    path = normalizePath(path);
    return this.commit('create', data => {
      this.assertWritable(data, path); this.assertParent(data, path);
      if (data.entries[path]) throw new Error(`Path already exists: ${path}`);
      data.entries[path] = { kind: 'file', content, metadata, revision: 1, history: [], created: Date.now(), modified: Date.now() };
    }, { path });
  }
  write(path, content, { generated = false, metadata } = {}) {
    path = normalizePath(path);
    return this.commit('write', data => {
      this.assertWritable(data, path); this.assertParent(data, path);
      let entry = data.entries[path];
      if (entry?.kind === 'directory') throw new Error(`Not a file: ${path}`);
      if (generated && entry && !entry.generated) throw new Error(`Output would overwrite a user file: ${path}. Choose another output path.`);
      if (!entry) entry = data.entries[path] = { kind: 'file', content: '', metadata: {}, revision: 0, history: [], created: Date.now() };
      if (entry.content !== content && entry.revision && !generated) {
        entry.history = [{ content: entry.content, revision: entry.revision, modified: entry.modified }, ...entry.history].slice(0, 5);
      }
      entry.content = content; delete entry.draft;
      entry.revision++; entry.modified = Date.now(); entry.generated = generated;
      if (metadata) entry.metadata = { ...entry.metadata, ...metadata };
    }, { path });
  }
  setDraft(path, content, metadata) {
    path = normalizePath(path);
    return this.commit('draft', data => {
      this.assertWritable(data, path);
      const entry = data.entries[path];
      if (entry?.kind !== 'file') throw new Error(`Not a file: ${path}`);
      if (entry.content === content) delete entry.draft; else entry.draft = content;
      if (metadata) entry.metadata = { ...entry.metadata, ...metadata };
    }, { path });
  }
  setMetadata(path, metadata) {
    path = normalizePath(path);
    this.commit('metadata', data => {
      if (!data.entries[path]) throw new Error(`No such path: ${path}`);
      data.entries[path].metadata = { ...data.entries[path].metadata, ...metadata };
    }, { path });
  }
  move(from, to) {
    from = normalizePath(from); to = normalizePath(to);
    if (from === to) return;
    if (['/', '/home', '/home/user', '/examples', '/build'].includes(from)) throw new Error('The workspace volumes cannot be moved.');
    this.commit('move', data => {
      this.assertWritable(data, from); this.assertWritable(data, to); this.assertParent(data, to);
      if (!data.entries[from]) throw new Error(`No such path: ${from}`);
      if (data.entries[to]) throw new Error(`Path already exists: ${to}`);
      if (from === '/' || within(to, from)) throw new Error('A directory cannot be moved inside itself.');
      const paths = Object.keys(data.entries).filter(path => within(path, from));
      for (const path of paths) this.assertWritable(data, path);
      for (const path of paths) { data.entries[to + path.slice(from.length)] = data.entries[path]; delete data.entries[path]; }
    }, { from, to });
  }
  copy(from, to) {
    from = normalizePath(from); to = normalizePath(to);
    this.commit('create', data => {
      this.assertWritable(data, to); this.assertParent(data, to);
      if (!data.entries[from]) throw new Error(`No such path: ${from}`);
      if (data.entries[to]) throw new Error(`Path already exists: ${to}`);
      if (from === '/' || within(to, from)) throw new Error('A directory cannot be copied inside itself.');
      for (const path of Object.keys(data.entries).filter(path => within(path, from))) {
        const entry = structuredClone(data.entries[path]);
        delete entry.readOnly; delete entry.generated;
        if (entry.kind === 'file') {
          entry.content = entry.draft ?? entry.content; delete entry.draft;
          entry.history = []; entry.revision = 1;
        }
        data.entries[to + path.slice(from.length)] = entry;
      }
    }, { path: to });
  }
  remove(path) {
    path = normalizePath(path);
    if (['/', '/home', '/home/user', '/examples', '/build'].includes(path)) throw new Error('The workspace volumes cannot be removed.');
    this.commit('remove', data => {
      this.assertWritable(data, path);
      if (!data.entries[path]) throw new Error(`No such path: ${path}`);
      const paths = Object.keys(data.entries).filter(p => within(p, path));
      for (const p of paths) this.assertWritable(data, p);
      const entries = {};
      for (const p of paths) { entries[p] = data.entries[p]; delete data.entries[p]; }
      data.trash.unshift({ id: crypto.randomUUID(), path, removed: Date.now(), entries });
    }, { path });
  }
  restore(id) {
    const item = this.data.trash.find(entry => entry.id === id);
    if (!item) throw new Error('That trash entry no longer exists.');
    this.commit('restore', data => {
      this.assertWritable(data, item.path); this.assertParent(data, item.path);
      for (const path of Object.keys(item.entries)) if (data.entries[path]) throw new Error(`Restore would overwrite ${path}. Rename that path first.`);
      Object.assign(data.entries, item.entries); data.trash = data.trash.filter(entry => entry.id !== id);
    }, { path: item.path });
    return item.path;
  }
  setSession(session) { this.commit('session', data => { data.session = { ...data.session, ...session }; }); }
  export() { return JSON.stringify(this.data, null, 2); }

  mountExamples(examples) {
    const changed = examples.filter(e => this.data.entries[`/examples/${e.file}`]?.content !== e.source);
    if (!changed.length) return;
    this.commit('examples', data => {
      for (const e of changed) data.entries[`/examples/${e.file}`] = {
        kind: 'file', content: e.source, readOnly: true, metadata: { nodes: Math.max(2,e.nodes), blurb:e.blurb },
        revision: 1, history: [], created: Date.now(), modified: Date.now(),
      };
    });
  }
  seed(examples, legacy) {
    if (this.data.seeded) return;
    this.commit('seed', data => {
      for (const path of ['/home', '/home/user', '/examples', '/build']) data.entries[path] ??= { kind: 'directory', created: Date.now() };
      for (const example of examples) data.entries[`/examples/${example.file}`] = {
        kind: 'file', content: example.source, readOnly: true, metadata: { nodes: Math.max(2, example.nodes), blurb: example.blurb },
        revision: 1, history: [], created: Date.now(), modified: Date.now(),
      };
      data.entries['/examples'].readOnly = true;
      for (const [name, buffer] of Object.entries(legacy?.buffers ?? {})) {
        if (!/^[\w.-]+\.c$/.test(name) || typeof buffer.source !== 'string') continue;
        data.entries[`/home/user/${name}`] = { kind: 'file', content: buffer.source,
          metadata: { nodes: buffer.nodes, breakpoints: buffer.breakpoints ?? [] }, revision: 1, history: [], created: Date.now(), modified: Date.now() };
      }
      data.entries['/home/user/main.c'] ??= { kind: 'file', content: examples.find(e => e.file === 'factorial.c')?.source ?? 'int main(void) { return 42; }\n',
        metadata: { nodes: 2 }, revision: 1, history: [], created: Date.now(), modified: Date.now() };
      const active = data.entries[`/home/user/${legacy?.active}`] ? `/home/user/${legacy.active}` : '/home/user/main.c';
      data.session = { open: [active], active, cwd: '/home/user' }; data.seeded = true;
    });
  }
}
