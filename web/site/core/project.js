import { buildPlan } from './build.js';

// Shared by the header and Build window so target selection and loading agree.
export function projectFiles(ide) {
  const paths = ide.fs.files().filter(path => /\.jm$/.test(path));
  if (ide.fs.exists(ide.buildFile) && !paths.includes(ide.buildFile)) paths.push(ide.buildFile);
  return paths.sort();
}
export function projectSelection(ide) {
  const graph = ide.builder.graph(ide.buildFile);
  const target = graph.targets.has(ide.buildTarget) ? ide.buildTarget : null;
  const selected = target ? [target] : graph.defaults;
  buildPlan(graph, selected);
  // An image target loads that output. Only groups expand to their members;
  // intermediate images are dependencies, not alternate choices for Load.
  const candidates = new Set(), seen = new Set();
  const collect = target => {
    if (seen.has(target)) return; seen.add(target);
    const step = graph.targets.get(target); if (!step) return;
    if (step.rule === 'phony') step.inputs.forEach(collect); else candidates.add(step.target);
  };
  selected.forEach(collect);
  const checked = new Map();
  const images = [...candidates].filter(path => ide.builder.outputState(graph, path, checked).ready && ide.fs.stat(path).metadata?.artifact);
  return { graph, target, selected, images };
}
export function chooseProjectImage(ide) {
  const { graph, images } = projectSelection(ide);
  if (!images.length) throw new Error('Build the selected target before loading an image.');
  const load = path => ide.loadArtifact(path, { project: graph.path });
  if (images.length === 1) return load(images[0]);
  return ide.services.choose(images.map(path => ({ label: path, detail: `Built by ${graph.path}`, run: () => ide.perform(() => load(path)) })), { title: 'Load project image', label: 'Image target', placeholder: 'Filter built images…', verb: 'Load', help: 'build' });
}
