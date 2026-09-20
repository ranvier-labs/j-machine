import { SimulatorWasm } from '../runtime.js';
import { DebuggerController, debugImage } from '../debugger.js';
import { normalizePath, basename, dirname } from './filesystem.js';
import { parseCommand } from './commands.js';
import { NetworkTrace } from '../network/trace.js';
import { breakpointSpec } from '../network/commands.js';
import { BuildSystem } from './build.js';
import { commandState } from './command-state.js';
import { presentText, textOf, presentationValue, quoteArgument } from './presentations.js';

const inside = (path, parent) => path === parent || path?.startsWith(`${parent}/`);
export const LISTENER_HELP = `FILES    ls [path] · cd path · pwd · edit path · new path · mkdir path
         save · cp from to · mv from to · trash path · restore [id] · cat path
MACHINE  compile [path] · run · continue · pause · restart
         step [source|instruction|cycle] · reset · nodes 2|4|16|512 · inspect node
NETWORK  packets [filter] · packet id · break-network inject|deliver|link|handler|stall
         Conditions: node=0 src=0 dst=1 port=2 priority=0 handler=0x1000 cycles=20
         delete-network-breakpoint id · trace-cycle n · trace-live
         save-trace [path] · open-trace path
KEYBOARD commands · command id · keymap-reload · M-x searches all actions
DESKTOP  window files|editor|geometry|debugger|listener|packets|waiting|history|display|build
         tile development|editing|debugging|building|network|graphics|documentation
MANUAL   help [topic] · doc [topic or search words] · window documentation · clear
BUILD    use-build path · build [target] · load output.image

Pathnames are relative to the listener's current directory. Quote spaces.
Files and drafts live in this browser. Use Export for a separate copy.
Compile builds and loads the selected C buffer. Project builds produce image
files: select a graph and target, Build, Load, then Run (F5).`;

export class IDE {
  constructor(fs, variants, { baseUrl = globalThis.location?.href, createSimulator = SimulatorWasm.fromVariant } = {}) {
    this.fs = fs; this.variants = variants; this.listeners = new Set(); this.logs = [];
    this.openPaths = []; this.activePath = null; this.nodes = 2; this.cwd = fs.data.session.cwd ?? '/home/user';
    if (!fs.exists(this.cwd) || fs.stat(this.cwd).kind !== 'directory') this.cwd = '/home/user';
    this.pending = new Map(); this.diagnostics = new Map(); this.history = []; this.selectedNode = 0;
    this.busy = false; this.ready = false; this.stale = false; this.addressBreakpoints = [];
    this.status = 'Starting development environment…'; this.services = {};
    this.buildFile = fs.data.session.buildFile ?? '/home/user/build.jm';
    this.buildTarget = fs.data.session.buildTarget ?? null;
    this.baseUrl = baseUrl; this.createSimulator = createSimulator;
    fs.onChange(event => this.fileEvent(event));
    globalThis.addEventListener?.('beforeunload', () => { this.flush(); this.persistSession(); });
  }
  on(types, listener) { const entry = { types: [].concat(types), listener }; this.listeners.add(entry); return () => this.listeners.delete(entry); }
  emit(type) { for (const entry of this.listeners) if (entry.types.includes(type) || entry.types.includes('*')) entry.listener(type); }
  message(value, kind = 'info') {
    const parts = Array.isArray(value) ? value : presentText(String(value), Object.keys(this.fs.data.entries), this.compiledPath), text = textOf(parts);
    this.logs.push({ text, parts, kind, cycle: this.debug?.snapshot?.cycle.toString() ?? 'BOOT' });
    if (this.logs.length > 160) this.logs.shift();
    if (kind !== 'command') this.status = String(text).split('\n')[0];
    this.emit('log'); this.emit('state');
  }
  async perform(action) { try { return await action(); } catch (error) { this.message(error.message, 'error'); } }
  // Status-only updates for long operations; they do not enter the listener log.
  progress(text) { this.status = text; this.emit('state'); }
  loadProgress(nodes, event) {
    const mb = bytes => `${(bytes / 1048576).toFixed(1)} MB`;
    if (event.stage === 'fetch') this.progress(`Fetching the ${nodes}-node simulator · ${mb(event.loaded)}${event.total ? ` / ${mb(event.total)}` : ''}`);
    else if (event.stage === 'instantiate') this.progress(`Instantiating the ${nodes}-node simulator…`);
    else if (event.stage === 'image') this.progress(`Loading the image into ${nodes} nodes…`);
  }
  active() { return this.activePath && this.fs.exists(this.activePath) ? this.fs.stat(this.activePath) : null; }
  text(path = this.activePath) { return this.editor?.getText(path) ?? this.pending.get(path)?.text ?? this.fs.read(path); }
  dirty(path) { return this.pending.has(path) ? this.pending.get(path).text !== this.fs.read(path, { draft: false }) : this.fs.stat(path).draft !== undefined; }
  exportSnapshot() {
    const data = structuredClone(this.fs.data);
    for (const [path, pending] of this.pending) if (data.entries[path]) data.entries[path].draft = pending.text;
    data.session = { ...data.session, active: this.activePath, open: this.openPaths };
    return JSON.stringify(data, null, 2);
  }
  commandState(id) { return this.services.commandState?.(id) ?? commandState(this, id); }
  machineReason() {
    if (this.busy) return 'Wait for the current operation to finish.';
    if (this.stale) return 'The loaded source has changed. Rebuild and load its image, or compile again before running.';
    if (this.loadFailure) return `Compile & Load failed for ${this.loadFailure}. Compile successfully or explicitly load an image before running.${this.debug?.image ? ' The previous image is retained for inspection.' : ''}`;
    if (!this.debug?.image) return 'Build and load a project image, or compile a C buffer to load a machine.';
    return '';
  }
  canCompile() { return commandState(this, 'compile').enabled; }
  canRun() { return !this.machineReason() && !this.debug?.completed; }
  persistSession() { this.fs.setSession({ open: this.openPaths, active: this.activePath, cwd: this.cwd, buildFile: this.buildFile, buildTarget: this.buildTarget }); }
  async selectPresentation(value, insert = false) {
    if (value.type === 'command') { this.services.insertListener?.(value.command, true); return; }
    if (insert) { this.services.insertListener?.(quoteArgument(presentationValue(value))); return; }
    if (value.type === 'documentation') this.services.openDocumentation?.(value.topic);
    else if (value.type === 'packet') { this.network.selectedPacket = value.packet; this.emit('network'); this.services.openWindow?.('packets'); }
    else if (value.type === 'node') { this.selectNode(value.node); this.services.openWindow?.('debugger'); }
    else if (value.type === 'source') this.reveal(value.path, value.line, value.column);
    else if (value.type === 'target') { this.selectBuildFile(value.manifest); this.selectBuildTarget(value.target); this.services.openWindow?.('build'); }
    else if (value.type === 'path') {
      const entry = this.fs.stat(value.path);
      if (entry.kind === 'file') this.openFile(value.path);
      else { this.cwd = value.path; this.persistSession(); this.emit('cwd'); this.services.selectDirectory?.(value.path); this.services.openWindow?.('files'); }
    }
  }
  async initialize(editor, requested) {
    this.editor = editor;
    await editor.initialize({ nodes: this.nodes, mesh: this.variants.find(v => v.nodes === this.nodes)?.mesh });
    this.ready = true;
    const session = structuredClone(this.fs.data.session);
    for (const path of session.open ?? []) if (this.fs.exists(path) && this.fs.stat(path).kind === 'file') this.openFile(path, { focus: false });
    const active = requested && this.fs.exists(requested) ? requested : session.active;
    this.openFile(active && this.fs.exists(active) ? active : '/home/user/main.c', { focus: false });
    this.message('Environment ready. M-x opens commands; type help in the listener.');
    if (this.canCompile()) await this.compile();
  }
  openFile(value, { focus = true, adoptTarget = true } = {}) {
    this.flush();
    const path = normalizePath(value, this.cwd), entry = this.fs.stat(path);
    if (entry.kind !== 'file') throw new Error(`Not a file: ${path}`);
    if (!this.openPaths.includes(path)) this.openPaths.push(path);
    this.activePath = path;
    this.editor.setSource(this.fs.read(path), path, { readOnly: !!entry.readOnly || !!entry.generated });
    if (adoptTarget && this.variants.some(v => v.nodes === entry.metadata?.nodes)) this.setNodes(entry.metadata.nodes);
    this.persistSession(); this.refreshDecorations(); this.emit('buffers'); this.emit('state'); this.emit('cursor');
    if (focus) this.services.openWindow?.('editor');
  }
  closeFile(path) {
    this.flush(); this.editor.close(path); this.openPaths = this.openPaths.filter(p => p !== path); this.diagnostics.delete(path);
    if (this.activePath === path) {
      this.activePath = null;
      if (this.openPaths.length) this.openFile(this.openPaths.at(-1), { focus: false });
    }
    this.persistSession(); this.emit('buffers'); this.emit('diagnostics'); this.emit('state');
  }
  edited(path, text) {
    if (path === this.compiledPath && this.debug?.running) this.debug.pause();
    const breakpoints = this.breakpoints(path).map((bp, index) => {
      const range = this.editor.breakpointDecorations.getRange(index);
      return range && path === this.activePath ? { ...bp, line: range.startLineNumber } : bp;
    });
    this.pending.set(path, { text, breakpoints });
    clearTimeout(this.draftTimer); this.draftTimer = setTimeout(() => this.perform(() => this.flush()), 180);
    this.refreshStale(); this.refreshDecorations(); this.emit('buffers'); this.emit('state');
  }
  flush() {
    clearTimeout(this.draftTimer);
    for (const [path, pending] of this.pending) {
      if (this.fs.exists(path)) this.fs.setDraft(path, pending.text, { breakpoints: pending.breakpoints });
      this.pending.delete(path);
    }
  }
  save() {
    if (!this.activePath) throw new Error('No buffer is selected.');
    const entry = this.active();
    if (entry.readOnly || entry.generated) { this.services.saveAs?.(); return; }
    this.flush(); this.fs.write(this.activePath, this.text()); this.message(`Saved ${this.activePath}`);
  }
  saveAs(path) {
    const text = this.text(), metadata = this.active()?.metadata;
    this.fs.create(normalizePath(path, this.cwd), text, { ...metadata, nodes: this.nodes });
    this.openFile(path); this.message(`Wrote ${this.activePath}`);
  }
  newFile(path) {
    path = normalizePath(path, this.cwd);
    this.fs.create(path, path.endsWith('.c') ? 'int main(void) {\n  return 42;\n}\n' : '', { nodes: this.nodes }); this.openFile(path);
  }
  uniquePath(path) {
    path = normalizePath(path, this.cwd); if (!this.fs.exists(path)) return path;
    const dot = basename(path).lastIndexOf('.'), base = dot > 0 ? path.slice(0, path.length - basename(path).length + dot) : path;
    const extension = dot > 0 ? basename(path).slice(dot) : '';
    let index = 2; while (this.fs.exists(`${base}-${index}${extension}`)) index++;
    return `${base}-${index}${extension}`;
  }
  fileEvent(event) {
    if (event.type === 'session') return;
    if (event.type === 'move') {
      for (const path of this.openPaths.filter(p => inside(p, event.from))) { this.editor?.close(path); this.diagnostics.delete(path); }
      const move = path => inside(path, event.from) ? event.to + path.slice(event.from.length) : path;
      this.openPaths = this.openPaths.map(move); this.activePath = move(this.activePath); this.compiledPath = move(this.compiledPath); this.cwd = move(this.cwd);
      this.buildFile = move(this.buildFile);
      this.buildTarget = move(this.buildTarget); this.loadFailure = move(this.loadFailure);
      this.compiledInputs = this.compiledInputs?.map(input => ({ ...input, path: move(input.path) }));
      if (this.activePath) this.editor?.setSource(this.fs.read(this.activePath), this.activePath, { readOnly: !!this.active()?.readOnly || !!this.active()?.generated });
      this.persistSession();
    }
    if (event.type === 'remove') {
      for (const path of [...this.openPaths]) if (inside(path, event.path)) this.closeFile(path);
      if (inside(this.cwd, event.path)) this.cwd = dirname(event.path);
    }
    if (event.type === 'write' && this.fs.exists(event.path)) this.editor?.syncSource(event.path, this.fs.read(event.path));
    this.refreshStale(); this.refreshDecorations(); this.emit('files'); this.emit('buffers'); this.emit('state');
  }
  setNodes(nodes) {
    const variant = this.variants.find(v => v.nodes === Number(nodes));
    if (!variant) throw new Error('Choose an available physical node count.');
    this.nodes = variant.nodes; this.editor?.configure({ nodes: this.nodes, mesh: variant.mesh }); this.emit('state');
  }
  setDiagnostics(items, path) { this.diagnostics.set(path, items); this.emit('diagnostics'); }
  refreshStale() {
    this.stale = !!this.compiledPath && (!this.fs.exists(this.compiledPath) || this.text(this.compiledPath) !== this.compiledSource);
    this.stale ||= !!this.compiledInputs?.some(input => !this.fs.exists(input.path) || this.text(input.path) !== input.text);
    if (this.stale && this.debug?.running) this.debug.pause();
  }
  breakpoints(path = this.activePath) {
    if (!path || !this.fs.exists(path)) return [];
    return (this.pending.get(path)?.breakpoints ?? this.fs.stat(path).metadata?.breakpoints ?? []).filter(bp => Number.isInteger(bp.line) && bp.line > 0);
  }
  toggleBreakpoint(line) {
    if (!/\.c$/.test(this.activePath ?? '') || !Number.isInteger(line) || line < 1) return;
    this.flush(); const entries = this.breakpoints();
    const breakpoints = entries.some(bp => bp.line === line) ? entries.filter(bp => bp.line !== line) : [...entries, { line, node: null, enabled: true }];
    this.fs.setMetadata(this.activePath, { breakpoints }); this.bindBreakpoints(); this.refreshDecorations(); this.emit('machine');
  }
  bindBreakpoints() {
    if (!this.debug) return;
    this.debug.breakpoints.clear();
    for (const bp of [...this.breakpoints(this.compiledPath), ...this.addressBreakpoints]) if (bp.enabled !== false) this.debug.addBreakpoint(bp);
  }
  refreshDecorations() {
    if (!this.editor?.model) return;
    this.bindBreakpoints();
    this.editor.setBreakpoints(this.breakpoints(), this.debug?.info ?? { entries: new Map() }, this.stale || this.compiledPath !== this.activePath);
    this.editor.showExecution(this.activePath === this.compiledPath && !this.stale && !this.debug?.running ? this.debug?.sourceLocation()?.line : undefined);
  }
  async compile(path = this.activePath) {
    if (!this.ready || this.busy || this.debug?.running) throw new Error('Pause execution and wait for the current operation first.');
    if (path !== this.activePath) this.openFile(path, { focus: false });
    if (!/\.c$/.test(this.activePath ?? '')) throw new Error('Select a C source buffer to compile.');
    this.flush(); path = this.activePath;
    const source = this.text(path), version = this.editor.getVersion(path), nodes = this.nodes, variant = this.variants.find(v => v.nodes === nodes);
    this.busy = true; this.message(`Compiling ${path} for ${nodes} nodes…`); const started = performance.now();
    try {
      this.editor.configure({ nodes, mesh: variant.mesh }); const result = await this.editor.compile();
      if (!this.fs.exists(path) || this.editor.getVersion(path) !== version || this.text(path) !== source) throw new Error('The source changed or closed during compilation. Compile the buffer again.');
      const imagePath = `/build/buffers${path}.${nodes}.image`;
      const ensureDirectory = directory => { if (!this.fs.exists(directory)) { ensureDirectory(dirname(directory)); this.fs.mkdir(directory); } };
      ensureDirectory(dirname(imagePath));
      this.fs.write(imagePath, result.image, { generated: true, metadata: { build: null, artifact: { sourcePath: path, sourceText: source, nodes } } });
      this.fs.setMetadata(path, { nodes });
      const count = await this.installImage(result.image, path, source, nodes, () => {
        if (!this.fs.exists(path) || this.editor.getVersion(path) !== version || this.text(path) !== source) throw new Error('The source changed while the machine was loading. Compile again.');
      });
      this.image = result.image; this.imagePath = imagePath;
      this.message(`Loaded ${path} · ${count.toLocaleString()} words · ${Math.round(performance.now() - started)} ms`);
      this.emit('image');
    } catch (error) { this.loadFailure = path; this.refreshStale(); this.message(error.message, 'error'); }
    finally { this.busy = false; this.emit('state'); }
  }
  async installImage(image, path, source, nodes, validate = () => {}, inputs = []) {
    const variant = this.variants.find(item => item.nodes === nodes); if (!variant) throw new Error('The image needs an unavailable machine topology.');
    const previousSimulator = this.simulator;
    const simulator = previousSimulator?.nodes === nodes ? previousSimulator : await this.createSimulator(variant, this.baseUrl, { onProgress: event => this.loadProgress(nodes, event) });
    const debug = new DebuggerController(simulator, { yieldFrame: () => new Promise(resolve => setTimeout(resolve, 0)) });
    let count;
    this.loadProgress(nodes, { stage: 'image' });
    try { validate(); count = debug.load(image); }
    catch (error) { if (simulator !== previousSimulator) simulator.destroy(); throw error; }
    if (previousSimulator === simulator && this.compiledPath === path) for (const watch of this.debug.watchpoints.values()) debug.addWatchpoint(watch.node, watch.address);
    if (previousSimulator && previousSimulator !== simulator) previousSimulator.destroy();
    this.simulator = simulator; this.debug = debug; this.archiveTrace = null;
    debug.network.metadata = { sourcePath: path, sourceText: source, image, mesh: variant.mesh, nodes, inputs,
      compiler: this.builder?.compilerId ?? null };
    debug.onUpdate = snapshot => this.record(snapshot); debug.onStop = reason => this.stopped(reason); debug.breakOnFault = !!this.breakOnFault;
    this.compiledPath = path; this.compiledSource = source; this.history = []; this.previous = null; this.addressBreakpoints = []; this.selectedNode = 0;
    this.compiledInputs = inputs;
    this.loadFailure = null;
    this.refreshStale(); this.bindBreakpoints(); this.record(debug.snapshot); this.stopped(debug.stopReason); return count;
  }
  async initializeBuilder() {
    this.builder = new BuildSystem(this.fs, {
      compilerId: await this.editor.compilerIdentity(), read: path => this.text(path),
      compile: (source, nodes) => {
        const variant = this.variants.find(item => item.nodes === nodes); if (!variant) throw new Error(`No ${nodes}-node simulator was built.`);
        return this.editor.compileSource(source, nodes, variant.mesh);
      },
      onEvent: record => {
        if (record.status === 'failed') this.message([{ type: 'source', path: record.error.path ?? this.buildFile, line: record.error.line ?? 1, column: record.error.column ?? 1, text: `${record.error.path ?? this.buildFile}:${record.error.line ?? 1}` }, `: ${record.error.message}`], 'error');
        else this.message([`${record.status.toUpperCase()} `, { type: 'target', manifest: record.manifest, target: record.target, text: record.target }, ` · ${record.reason}`]);
        this.emit('build');
      },
    }); this.emit('build'); this.emit('state');
  }
  selectBuildFile(value) {
    if (this.busy) throw new Error('Wait for the current operation before changing the build graph.');
    const path = normalizePath(value, this.cwd); this.builder.graph(path);
    if (path !== this.buildFile) this.buildTarget = null;
    this.buildFile = path; this.buildError = null; this.persistSession(); this.emit('build'); this.emit('state');
  }
  selectBuildTarget(value) {
    const graph = this.builder.graph(this.buildFile), target = value ? normalizePath(value, graph.directory) : null;
    if (target && !graph.targets.has(target)) throw new Error(`Unknown target: ${target}`);
    if (this.busy) throw new Error('Wait for the current operation before changing the build target.');
    this.buildTarget = target; this.persistSession(); this.emit('build'); this.emit('state');
  }
  async build(target) {
    if (!this.builder || this.busy || this.debug?.running) throw new Error('Pause the machine and wait for the current operation before building.');
    if (target === undefined) {
      if (!this.builder.graph(this.buildFile).targets.has(this.buildTarget)) this.buildTarget = null;
      target = this.buildTarget;
    }
    this.persistSession();
    this.services.openWindow?.('build');
    this.flush(); this.busy = true; this.buildError = null; this.emit('state'); this.emit('build');
    try {
      const report = await this.builder.build(this.buildFile, target ? [target] : undefined);
      this.lastBuild = { manifest: this.buildFile, report };
      this.message(`Build complete · ${report.built} built · ${report.skipped} up to date`); return report;
    } catch (error) { this.buildError = error; throw error; }
    finally { this.busy = false; this.emit('state'); this.emit('build'); }
  }
  async loadArtifact(value, { project } = {}) {
    if (this.busy || this.debug?.running) throw new Error('Pause the machine before loading an image.');
    this.flush(); const path = normalizePath(value, this.cwd), entry = this.fs.stat(path), artifact = entry.metadata?.artifact;
    if (!artifact || typeof artifact.sourcePath !== 'string' || typeof artifact.sourceText !== 'string') throw new Error('This file has no JMC build metadata. Build a target before loading it.');
    this.busy = true; this.emit('state');
    try {
      const validate = project ? await this.builder.validateOutput(this.builder.graph(project), path) : () => {};
      const image = this.fs.read(path), count = await this.installImage(image, artifact.sourcePath, artifact.sourceText, artifact.nodes, validate, artifact.inputs);
      this.image = image; this.imagePath = path; this.emit('image');
      if (!this.fs.data.session.projectLoaded) this.fs.setSession({ projectLoaded: true });
      this.message(`Loaded ${path} · ${count.toLocaleString()} words${this.stale ? ' · source changed; rebuild before running' : ''}`);
    } finally { this.busy = false; this.emit('state'); }
  }
  record(snapshot) {
    if (!snapshot) return;
    const previous = this.history.at(-1);
    if (!previous || previous.cycle !== snapshot.cycle) { this.previous = previous; this.history.push(snapshot); if (this.history.length > 100) this.history.shift(); }
    this.emit('machine');
  }
  stopped(reason) {
    this.selectedNode = this.debug.selectedNode;
    if (reason.type === 'network' && reason.packet) this.message([{ type: 'packet', packet: reason.packet, text: `Packet #${reason.packet}` }, ` stopped at cycle ${this.debug.snapshot.cycle}`]);
    this.refreshDecorations(); this.message(reason.message, ['fault', 'error'].includes(reason.type) ? 'error' : 'info'); this.emit('machine');
    if (['source', 'breakpoint'].includes(reason.type) && !this.stale && this.compiledPath !== this.activePath) this.openFile(this.compiledPath, { adoptTarget: false });
  }
  async execute(mode = 'continue', count = 1) {
    const state = commandState(this, mode === 'continue' ? 'continue' : 'step-cycle');
    if (!state.enabled) throw new Error(state.reason);
    if (this.debug?.running) { this.debug.pause(); return; }
    this.archiveTrace = null; this.debug.network.cursor = null;
    this.debug.selectedNode = this.selectedNode; this.editor?.showExecution();
    const result = this.debug.execute(mode, count); this.emit('state'); this.emit('machine');
    await result; this.emit('state');
  }
  pause() { this.debug?.pause(); }
  reset() {
    const state = commandState(this, 'reset'); if (!state.enabled) throw new Error(state.reason);
    this.archiveTrace = null;
    this.history = []; this.previous = null; this.debug.load(this.debug.image); this.bindBreakpoints();
    this.emit('state'); this.emit('network');
  }
  async restart() { this.reset(); return this.execute(); }
  selectNode(node) {
    if (!this.debug || !Number.isInteger(node) || node < 0 || node >= this.simulator.nodes) throw new Error('That node is outside the loaded machine.');
    this.selectedNode = node; this.debug.selectedNode = node; this.refreshDecorations(); this.emit('machine');
  }
  reveal(path, line, column = 1) { this.openFile(path, { adoptTarget: false }); this.editor.reveal(line, column); }
  get network() { return this.archiveTrace ?? this.debug?.network; }
  addNetworkBreakpoint(spec) {
    if (!this.debug || this.archiveTrace) throw new Error('Load a live machine before adding breakpoints.');
    const id = this.debug.network.addBreakpoint(spec); this.message(`Network breakpoint ${id}: ${spec.type}`); this.emit('network'); return id;
  }
  async traceText() {
    if (!this.network) throw new Error('No trace is available.');
    const metadata = { ...this.network.metadata, capturedCycle: this.network.cycle };
    if (metadata.image && globalThis.crypto?.subtle) metadata.imageSHA256 = [...new Uint8Array(await crypto.subtle.digest('SHA-256', new TextEncoder().encode(metadata.image)))].map(n => n.toString(16).padStart(2,'0')).join('');
    return this.network.export(metadata);
  }
  openTrace(text) {
    if (this.debug?.running) throw new Error('Pause the live machine before opening a trace.');
    this.archiveTrace = NetworkTrace.import(text); this.selectedNode = 0; this.emit('network'); this.services.openWindow?.('history');
  }
  visitTraceSource(address) {
    if (!Number.isInteger(address)) throw new Error('No source instruction was recorded for this event.');
    const metadata = this.network?.metadata ?? {}, image = metadata.image ?? this.debug?.image ?? '', info = debugImage(image), location = info.locations.get(address);
    if (location && metadata.sourceText) {
      let path = metadata.sourcePath;
      if (!path || !this.fs.exists(path) || this.fs.read(path) !== metadata.sourceText) {
        path = this.uniquePath('/home/user/captured-source.c'); this.fs.create(path, metadata.sourceText, { nodes: metadata.nodes ?? this.nodes });
      }
      this.reveal(path, location.line, location.column); return;
    }
    let path = this.imagePath;
    if (!path || !this.fs.exists(path) || this.fs.read(path) !== image) { path = this.uniquePath('/home/user/captured.image'); this.fs.create(path, image); }
    const line = image.split(/\r?\n/).findIndex(row => { const fields = row.trim().split(/\s+/); return ['0','*'].includes(fields[0]) && parseInt(fields[1],16) === address; });
    this.reveal(path,Math.max(1,line+1));
  }
  async command(text) {
    if (!text.trim()) return;
    this.message([`${this.cwd}> `, { type: 'command', command: text, text }], 'command');
    await this.perform(async () => {
      const [name, ...args] = parseCommand(text), path = value => normalizePath(value ?? '.', this.cwd);
      const requireArgs = count => { if (args.length !== count) throw new Error(`${name} expects ${count} argument${count === 1 ? '' : 's'}. Quote pathnames containing spaces.`); };
      this.flush(); let result;
      switch (name.toLowerCase()) {
        case 'command': requireArgs(1); await this.services.command(args[0]); break;
        case 'commands': result = this.services.commandList?.().map(c => `${c.id}  ${c.label}`).join('\n'); break;
        case 'packets': if (!this.network) throw new Error('Load a machine first.'); this.network.filter = args.join(' '); this.services.openWindow?.('packets'); this.emit('network'); break;
        case 'packet': requireArgs(1); if (!this.network?.packets.has(Number(args[0]))) throw new Error('No such packet in this capture.'); this.network.selectedPacket = Number(args[0]); this.services.openWindow?.('packets'); this.emit('network'); break;
        case 'break-network': if (!args.length) throw new Error('break-network inject|deliver|link|handler|stall [conditions]'); this.addNetworkBreakpoint(breakpointSpec(args[0],args.slice(1).join(' '))); break;
        case 'delete-network-breakpoint': requireArgs(1); this.debug?.network.breakpoints.delete(Number(args[0])); this.emit('network'); break;
        case 'trace-cycle': requireArgs(1); if (!this.network || !Number.isSafeInteger(Number(args[0])) || Number(args[0]) < 0 || Number(args[0]) > this.network.cycle) throw new Error('Cycle is outside this capture.'); this.network.cursor = Number(args[0]); this.services.openWindow?.('history'); this.emit('network'); break;
        case 'trace-live': this.archiveTrace = null; if(this.network)this.network.cursor = null; this.emit('network'); break;
        case 'save-trace': if(args.length){requireArgs(1);this.fs.create(path(args[0]),await this.traceText());}else await this.services.saveTrace?.(); break;
        case 'open-trace': requireArgs(1); this.openTrace(this.fs.read(path(args[0]))); break;
        case 'keymap-reload': this.services.reloadKeymap?.(); break;
        case 'help':
          if (args.length) this.services.openDocumentation?.(args.join(' '));
          else result = [LISTENER_HELP, '\n\nRead: ', { type: 'documentation', topic: 'welcome', text: 'Manual' }, ' · ', { type: 'documentation', topic: 'build', text: 'Project builds' }, ' · ', { type: 'documentation', topic: 'keyboard', text: 'Keyboard' }];
          break;
        case 'doc': this.services.openDocumentation?.(args.join(' ') || 'welcome'); break;
        case 'pwd': result = this.cwd; break;
        case 'ls': result = this.fs.list(path(args[0])).flatMap(e => [`${e.kind === 'directory' ? 'DIR ' : e.draft !== undefined ? 'MOD ' : '    '} `, { type: 'path', path: e.path, text: `${e.name}${e.kind === 'directory' ? '/' : ''}` }, '\n']); if (!result.length) result = '(empty directory)'; break;
        case 'cd': requireArgs(1); if (this.fs.stat(path(args[0])).kind !== 'directory') throw new Error('Not a directory.'); this.cwd = path(args[0]); this.persistSession(); this.emit('cwd'); break;
        case 'open': case 'edit': requireArgs(1); this.openFile(path(args[0])); break;
        case 'new': requireArgs(1); this.newFile(path(args[0])); break;
        case 'mkdir': requireArgs(1); this.fs.mkdir(path(args[0])); break;
        case 'save': requireArgs(0); this.save(); break;
        case 'cp': case 'mv': requireArgs(2); this.fs[name.toLowerCase() === 'cp' ? 'copy' : 'move'](path(args[0]), path(args[1])); break;
        case 'trash': requireArgs(1); this.fs.remove(path(args[0])); result = 'Moved to trash. Use restore to recover the latest entry.'; break;
        case 'restore': { const item = args[0] ? this.fs.data.trash.find(e => e.id === args[0] || e.path === path(args[0])) : this.fs.data.trash[0]; if (!item) throw new Error('No matching trash entry.'); result = `Restored ${this.fs.restore(item.id)}`; break; }
        case 'cat': requireArgs(1); result = this.fs.read(path(args[0])); if (result.length > 16000) result = `${result.slice(0, 16000)}\n… Open the file to read the rest.`; break;
        case 'compile': await this.compile(args[0] ? path(args[0]) : this.activePath); break;
        case 'use-build': requireArgs(1); this.selectBuildFile(path(args[0])); result = `Build file: ${this.buildFile}`; break;
        case 'build': if (args.length > 1) throw new Error('build accepts one target. Use a phony target to group outputs.'); await this.build(args[0]); break;
        case 'load': requireArgs(1); await this.loadArtifact(path(args[0])); break;
        case 'run': case 'continue': await this.execute(); break;
        case 'pause': this.pause(); break;
        case 'step': { const mode = args[0] ?? 'instruction'; if (!['source', 'instruction', 'cycle'].includes(mode)) throw new Error('step source | instruction | cycle'); await this.execute(mode === 'cycle' ? 'cycles' : mode); break; }
        case 'reset': this.reset(); break;
        case 'restart': await this.restart(); break;
        case 'nodes': requireArgs(1); this.setNodes(Number(args[0])); break;
        case 'inspect': requireArgs(1); this.selectNode(Number(args[0])); this.services.openWindow?.('debugger'); break;
        case 'window': requireArgs(1); this.services.openWindow?.(args[0]); break;
        case 'tile': requireArgs(1); this.services.layout?.(args[0]); break;
        case 'clear': this.logs = []; this.emit('log'); break;
        default: throw new Error(`Unknown command: ${name}. Type help for available commands.`);
      }
      if (result !== undefined) this.message(result);
    });
  }
}
