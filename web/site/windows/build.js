import { DEFAULT_BUILD } from '../core/build.js';
import { projectFiles, projectSelection, chooseProjectImage } from '../core/project.js';
import { requestPath } from '../shell/dialogs.js';
import { element, button, observe, syncCommandButton } from './common.js';

export function buildWindow(ide) {
  const root = element('div', 'build-window'), toolbar = element('div', 'build-toolbar'), select = element('select'); select.ariaLabel = 'Project build file';
  select.onchange = () => ide.perform(() => ide.selectBuildFile(select.value));
  const build = button('Build', 'Build selected targets (Cmd/Ctrl B)', () => ide.perform(() => ide.build()), 'primary');
  const target = element('select'); target.ariaLabel = 'Build window target';
  target.onchange = () => ide.perform(() => ide.selectBuildTarget(target.value));
  const loadSelected = button('Load', 'Load an image from the selected target', () => ide.perform(() => chooseProjectImage(ide)));
  const edit = button('Edit graph', 'Edit the selected build file', () => ide.perform(() => ide.openFile(ide.buildFile)));
  const create = button('New graph', 'Create a build file', () => requestPath({ title: 'Create build file', value: ide.uniquePath(`${ide.cwd}/build.jm`), submit: 'Create', run: path => {
    ide.fs.create(path, DEFAULT_BUILD); ide.selectBuildFile(path); ide.openFile(path);
  } }));
  toolbar.append(select, target, build, loadSelected, edit, create, button('Guide', 'Read the project build guide', () => ide.services.openDocumentation('build')));
  const summary = element('div', 'build-summary', 'Preparing build system…'), targets = element('div', 'build-targets'), hint = element('p', 'build-hint', 'jmc: compile one C program · copy: produce a file · phony: group targets. Changed inputs rebuild their dependents.');
  const workflow = element('p', 'build-workflow', 'Select target → Build → Load → Run (F5)');
  root.append(workflow, toolbar, summary, targets, hint);
  const render = observe(ide, ['build', 'files', 'state'], () => {
    const paths = projectFiles(ide);
    select.replaceChildren(...paths.map(path => new Option(path, path))); select.value = ide.buildFile;
    select.disabled = !ide.builder || ide.busy; target.disabled = select.disabled || !!ide.debug?.running;
    syncCommandButton(build,ide,'build'); syncCommandButton(loadSelected,ide,'load-project'); syncCommandButton(edit,ide,'build-graph');
    create.disabled = !ide.builder || ide.busy;
    targets.replaceChildren();
    if (!ide.builder) return;
    let graph;
    try {
      const selection = projectSelection(ide); graph = selection.graph;
      target.replaceChildren(new Option('Defaults', ''), ...[...graph.targets.values()].map(step => new Option(step.label, step.target)));
      target.value = selection.target ?? '';
    }
    catch (error) { summary.textContent = error.message; summary.classList.add('error-text'); target.replaceChildren(new Option('Invalid graph', '')); target.disabled = true; return; }
    summary.classList.toggle('error-text', !!ide.buildError);
    summary.textContent = ide.buildError ? ide.buildError.message : `${graph.targets.size} targets · defaults: ${graph.defaults.map(path => graph.targets.get(path).label).join(', ')}`;
    for (const step of graph.targets.values()) {
      const row = element('section', `build-target${ide.buildTarget === step.target ? ' selected' : ''}`), heading = element('div', 'build-target-heading');
      const visit = button(step.label, `Visit target ${step.target}`, () => ide.perform(() => ide.fs.exists(step.target) ? ide.openFile(step.target) : ide.reveal(graph.path, step.line)), 'text-button');
      const state = element('span', 'build-state'), actions = element('div', 'build-target-actions');
      const record = ide.builder.records.get(`${graph.path}:${step.target}`);
      const output = ide.builder.outputState(graph,step.target);
      state.textContent = record?.status === 'building' ? 'BUILDING' : step.rule === 'phony' ? 'GROUP' : output.ready ? 'AVAILABLE' : ide.fs.exists(step.target) ? 'REBUILD' : 'NOT BUILT';
      heading.append(visit, state);
      const inputs = element('div', 'build-inputs'); inputs.append(element('span', '', `${step.rule}${step.rule === 'jmc' ? ` / ${step.nodes} nodes` : ''} ← `));
      for (const [index, input] of step.inputs.entries()) {
        if (index) inputs.append(document.createTextNode(', '));
        inputs.append(button(input.startsWith(`${graph.directory}/`) ? input.slice(graph.directory.length + 1) : input, `Visit input ${input}`, () => ide.perform(() => {
          if (ide.fs.exists(input)) ide.openFile(input); else if (graph.targets.has(input)) ide.reveal(graph.path, graph.targets.get(input).line); else throw new Error(`Missing input: ${input}`);
        }), 'text-button'));
      }
      const run = button('Build', `Build target ${step.target}`, () => ide.perform(() => ide.build(step.target))); run.disabled = build.disabled;
      const load = button('Load', `Load built image ${step.target}`, () => ide.perform(() => ide.loadArtifact(step.target,{project:graph.path})));
      load.disabled = ide.busy || !!ide.debug?.running || !output.ready || !ide.fs.stat(step.target).metadata?.artifact;
      if (!output.ready) load.title = load.ariaLabel = output.reason;
      actions.append(run); if (step.rule !== 'phony') actions.append(load);
      actions.append(button('Definition', `Visit target definition in ${graph.path}`, () => ide.perform(() => ide.reveal(graph.path, step.line))));
      const reason = element('p', 'build-reason', step.rule !== 'phony' && !output.ready ? output.reason : record?.reason ?? (step.rule === 'phony' ? 'Builds its dependencies in order.' : 'Build checks input contents, recipe, and compiler identity.'));
      row.append(heading, inputs, reason, actions); targets.append(row);
    }
  }); render();
  return { id: 'build', title: 'BUILD', element: root, onFocus: () => select.focus() };
}
