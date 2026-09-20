import { normalizePath, dirname } from './filesystem.js';
import { parseCommand } from './commands.js';

export const DEFAULT_BUILD = `# J-Machine build graph. Paths are relative to this file.
# Built-in rules: jmc, copy, phony. Each jmc input is one complete C program.
build /build/main.image: jmc main.c
  nodes = 2

build /build/mesh512.image: jmc /examples/mesh512.c
  nodes = 512

build all: phony /build/main.image /build/mesh512.image
default /build/main.image
`;
export class BuildError extends Error {
  constructor(message, path, line = 1, column = 1) { super(message); this.name = 'BuildError'; this.path = path; this.line = line; this.column = column; }
}
export function parseBuild(text, path) {
  const directory = dirname(path), targets = new Map(), defaults = []; let current;
  const fail = (message, line) => { throw new BuildError(message, path, line); };
  text.split(/\r?\n/).forEach((line, index) => {
    const number = index + 1, trimmed = line.trim(); if (!trimmed || trimmed.startsWith('#')) return;
    if (/^\s/.test(line)) {
      const option = trimmed.match(/^nodes\s*=\s*(2|4|16|512)$/);
      if (!current || current.rule !== 'jmc' || !option) fail('A jmc target accepts an indented nodes = 2|4|16|512 setting.', number);
      current.nodes = Number(option[1]); return;
    }
    let words; try { words = parseCommand(trimmed); } catch (error) { fail(error.message, number); }
    current = null;
    if (words[0] === 'default') {
      if (words.length < 2) fail('default requires at least one target.', number);
      defaults.push(...words.slice(1).map(value => normalizePath(value, directory))); return;
    }
    if (words[0] !== 'build') fail('Expected build output: jmc|copy|phony inputs, or default target.', number);
    let output = words[1], ruleIndex;
    if (output?.endsWith(':')) { output = output.slice(0, -1); ruleIndex = 2; }
    else if (words[2] === ':') ruleIndex = 3;
    else fail('A build statement needs one output followed by a colon.', number);
    const rule = words[ruleIndex], inputs = words.slice(ruleIndex + 1).map(value => normalizePath(value, directory));
    if (!output || !['jmc', 'copy', 'phony'].includes(rule)) fail('Available rules are jmc, copy, and phony.', number);
    if (rule !== 'phony' && inputs.length !== 1) fail(`${rule} requires exactly one input. Group several targets with phony.`, number);
    const target = normalizePath(output, directory);
    if (targets.has(target)) fail(`Duplicate target: ${target}`, number);
    current = { target, label: output, rule, inputs, nodes: 2, line: number, manifest: path };
    targets.set(target, current);
  });
  if (!targets.size) fail('The build file has no targets.', 1);
  for (const target of defaults) if (!targets.has(target)) fail(`Unknown default target: ${target}`, 1);
  return { path, text, directory, targets, defaults: defaults.length ? [...new Set(defaults)] : [targets.keys().next().value] };
}
export function buildPlan(graph, requested = graph.defaults) {
  const visiting = new Set(), done = new Set(), order = [], chain = [];
  const visit = target => {
    if (visiting.has(target)) throw new BuildError(`Dependency cycle: ${[...chain, target].join(' → ')}`, graph.path, graph.targets.get(target).line);
    if (done.has(target)) return;
    const step = graph.targets.get(target); if (!step) throw new BuildError(`Unknown target: ${target}`, graph.path);
    visiting.add(target); chain.push(target);
    for (const input of step.inputs) if (graph.targets.has(input)) visit(input);
    chain.pop(); visiting.delete(target); done.add(target); order.push(step);
  };
  for (const value of requested) visit(normalizePath(value, graph.directory));
  return order;
}
export async function contentHash(value) {
  const digest = await crypto.subtle.digest('SHA-256', new TextEncoder().encode(value));
  return [...new Uint8Array(digest)].map(byte => byte.toString(16).padStart(2, '0')).join('');
}

// Build a validated DAG using built-in actions. This layer has no windows,
// editor, LSP, or simulator dependency; the caller supplies the compiler.
export class BuildSystem {
  constructor(fs, { compile, compilerId, read = path => fs.read(path), onEvent = () => {} }) {
    this.fs = fs; this.compile = compile; this.compilerId = compilerId; this.read = read; this.onEvent = onEvent;
    this.running = false; this.records = new Map();
  }
  graph(path) { path = normalizePath(path); return parseBuild(this.read(path), path); }
  // Cheap provenance checks for menus. Loading additionally verifies the
  // content hashes, so an old or altered image cannot masquerade as a target.
  outputState(graph, target, checked = new Map()) {
    if (checked.has(target)) return checked.get(target);
    const unavailable = reason => { const state = { ready: false, reason }; checked.set(target, state); return state; };
    const step = graph.targets.get(target);
    if (!step || step.rule === 'phony') return unavailable('Select an image target.');
    if (!this.fs.exists(target)) return unavailable('Build this target first.');
    const entry = this.fs.stat(target), record = entry.metadata?.build, recipe = record?.recipe, artifact = entry.metadata?.artifact;
    if (!entry.generated || record?.manifest !== graph.path) return unavailable('This output was not built by the selected graph. Build it again.');
    if (recipe?.version !== 2 || recipe.rule !== step.rule || recipe.nodes !== (step.rule === 'jmc' ? step.nodes : null)
      || recipe.compiler !== (step.rule === 'jmc' ? this.compilerId : null)
      || JSON.stringify(recipe.inputs?.map(input => input.path)) !== JSON.stringify(step.inputs)) return unavailable('The target recipe changed. Build it again.');
    // Mark before descending, including malformed graphs opened for inspection.
    checked.set(target, { ready: false, reason: 'Dependency cycle.' });
    for (const input of step.inputs) {
      if (!this.fs.exists(input) || this.fs.stat(input).kind !== 'file') return unavailable(`Missing input: ${input}`);
      if (graph.targets.has(input)) {
        const dependency = this.outputState(graph, input, checked);
        if (!dependency.ready) return unavailable(dependency.reason);
      }
    }
    if (step.rule === 'jmc' && (artifact?.sourcePath !== step.inputs[0] || artifact.sourceText !== this.read(step.inputs[0]) || artifact.nodes !== step.nodes)) return unavailable('The image does not match this source and node count. Build it again.');
    if (step.rule === 'copy' && (this.read(target) !== this.read(step.inputs[0]) || JSON.stringify(artifact) !== JSON.stringify(this.fs.stat(step.inputs[0]).metadata?.artifact))) return unavailable('The copied input changed. Build it again.');
    if (artifact?.inputs?.some(input => !this.fs.exists(input.path) || this.read(input.path) !== input.text)) return unavailable('An input changed. Build this target again.');
    const state = { ready: true, reason: '' }; checked.set(target, state); return state;
  }
  async recipe(step, fingerprints = new Map()) {
    const inputs = await Promise.all(step.inputs.map(async path => ({ path, hash: fingerprints.has(path)
      ? fingerprints.get(path) : await contentHash(JSON.stringify({ content: this.read(path), artifact: this.fs.stat(path).metadata?.artifact })) })));
    return { version: 2, rule: step.rule, nodes: step.rule === 'jmc' ? step.nodes : null, compiler: step.rule === 'jmc' ? this.compilerId : null, inputs };
  }
  async validateOutput(graph, target) {
    const plan = buildPlan(graph, [target]), checked = new Map(), snapshots = new Map();
    const snapshot = path => JSON.stringify({ text: this.read(path), metadata: this.fs.stat(path).metadata, generated: this.fs.stat(path).generated });
    for (const path of new Set([graph.path, ...plan.filter(step => step.rule !== 'phony').flatMap(step => [step.target, ...step.inputs])])) {
      if (!this.fs.exists(path)) throw new BuildError(`Missing file: ${path}. Build the target again.`, graph.path);
      snapshots.set(path, snapshot(path));
    }
    const stable = () => {
      for (const [path, value] of snapshots) if (!this.fs.exists(path) || snapshot(path) !== value) throw new BuildError('The graph, input, or output changed while loading. Build and load again.', graph.path);
    };
    for (const step of plan) {
      const state = this.outputState(graph, step.target, checked);
      if (!state.ready) throw new BuildError(state.reason, graph.path, step.line);
      const record = this.fs.stat(step.target).metadata.build;
      if (record.signature !== await contentHash(JSON.stringify(await this.recipe(step)))
        || record.outputHash !== await contentHash(this.read(step.target))) throw new BuildError('The built input or output changed. Build this target again.', graph.path, step.line);
    }
    stable(); return stable;
  }
  async build(path, requested) {
    if (this.running) throw new Error('A build is already running.');
    this.running = true; const report = { built: 0, skipped: 0, steps: [], outputs: [] }; let current;
    try {
      const graph = this.graph(path), order = buildPlan(graph, requested), sources = new Map();
      // Validate the entire requested subgraph before producing any output.
      for (const step of order) {
        if (step.rule !== 'phony') {
          if (step.target === '/build/buffers' || step.target.startsWith('/build/buffers/')) throw new BuildError('/build/buffers is reserved for Compile & Load. Choose a project output outside it.', graph.path, step.line);
          this.fs.assertWritable(this.fs.data, step.target);
          if (this.fs.exists(step.target) && !this.fs.stat(step.target).generated) throw new BuildError(`Output would overwrite a user file: ${step.target}. Choose another output path.`, graph.path, step.line);
          for (const input of step.inputs) if (graph.targets.get(input)?.rule === 'phony') throw new BuildError(`${step.rule} requires a file input, not a phony target.`, graph.path, step.line);
        }
        for (const input of step.inputs) if (!graph.targets.has(input)) {
          if (!this.fs.exists(input) || this.fs.stat(input).kind !== 'file') throw new BuildError(`Missing input: ${input}`, graph.path, step.line);
          sources.set(input, this.read(input));
        }
      }
      const stable = () => {
        if (!this.fs.exists(graph.path) || this.read(graph.path) !== graph.text) throw new BuildError('The build file changed during the build. Build again.', graph.path);
        for (const [file, text] of sources) if (!this.fs.exists(file) || this.read(file) !== text) throw new BuildError('An input changed during the build. Build again.', file);
      };
      const fingerprints = new Map(), sourceDependencies = new Map();
      for (const step of order) {
        stable(); current = step;
        const dependencies = new Map();
        for (const input of step.inputs) for (const [file, text] of sourceDependencies.get(input) ?? [[input, sources.get(input)]]) dependencies.set(file, text);
        sourceDependencies.set(step.target, dependencies);
        const recipe = await this.recipe(step, new Map([...fingerprints].filter(([path]) => graph.targets.get(path)?.rule === 'phony')));
        const signature = await contentHash(JSON.stringify(recipe));
        if (step.rule === 'phony') {
          fingerprints.set(step.target, signature); this.event({ ...step, status: 'group', reason: 'Dependencies complete.' }); continue;
        }
        const entry = this.fs.exists(step.target) ? this.fs.stat(step.target) : null, previous = entry?.metadata?.build;
        const outputHash = entry ? await contentHash(this.read(step.target)) : null;
        const state = this.outputState(graph, step.target);
        const reason = !entry ? 'Output is missing.' : !previous ? 'No previous build record.' : previous.signature !== signature ? this.explain(previous.recipe, recipe) : previous.outputHash !== outputHash ? 'Output content changed.' : !state.ready ? state.reason : 'Inputs and recipe unchanged.';
        if (previous?.signature === signature && previous.outputHash === outputHash && state.ready) {
          stable(); report.skipped++; report.steps.push({ ...step, status: 'skipped', reason }); report.outputs.push(step.target); fingerprints.set(step.target, outputHash); this.event(report.steps.at(-1)); continue;
        }
        this.event({ ...step, status: 'building', reason });
        const input = this.read(step.inputs[0]); let output, artifact;
        try {
          if (step.rule === 'jmc') {
            const result = await this.compile(input, step.nodes); output = typeof result === 'string' ? result : result.image;
            artifact = { sourcePath: step.inputs[0], sourceText: input, nodes: step.nodes, inputs: [...dependencies].map(([path, text]) => ({ path, text })) };
          } else { output = input; artifact = this.fs.stat(step.inputs[0]).metadata?.artifact; }
        } catch (error) {
          const location = error.message.match(/:(\d+):(\d+):/);
          throw new BuildError(error.message, step.inputs[0], Number(location?.[1] ?? 1), Number(location?.[2] ?? 1));
        }
        stable(); const hash = await contentHash(output); stable();
        this.ensureDirectory(dirname(step.target));
        // Output and its build record are committed as one filesystem transaction.
        this.fs.write(step.target, output, { generated: true, metadata: { artifact, build: { signature, outputHash: hash, recipe, manifest: graph.path } } });
        fingerprints.set(step.target, hash); report.built++; report.outputs.push(step.target);
        report.steps.push({ ...step, status: 'built', reason }); this.event(report.steps.at(-1));
      }
      stable(); return report;
    } catch (error) {
      if (current) this.records.set(`${current.manifest}:${current.target}`, { ...current, status: 'failed', reason: error.message });
      this.onEvent({ status: 'failed', error }); throw error;
    }
    finally { this.running = false; }
  }
  event(record) { this.records.set(`${record.manifest}:${record.target}`, record); this.onEvent(record); }
  explain(before, after) {
    if (!before || before.rule !== after.rule) return 'Rule changed.';
    if (before.nodes !== after.nodes) return 'Node count changed.';
    if (before.compiler !== after.compiler) return 'Compiler changed.';
    const changed = after.inputs.filter((input, i) => input.path !== before.inputs[i]?.path || input.hash !== before.inputs[i]?.hash);
    return changed.length ? `Input changed: ${changed.map(input => input.path).join(', ')}` : 'Dependencies changed.';
  }
  ensureDirectory(path) {
    if (this.fs.exists(path)) { if (this.fs.stat(path).kind !== 'directory') throw new Error(`Not a directory: ${path}`); return; }
    this.ensureDirectory(dirname(path)); this.fs.mkdir(path);
  }
}
