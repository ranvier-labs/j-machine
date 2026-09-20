import { VirtualFilesystem, FILESYSTEM_KEY, basename } from './core/filesystem.js';
import { IDE, LISTENER_HELP } from './core/ide.js';
import { DEFAULT_BUILD } from './core/build.js';
import { WindowManager } from './shell/window-manager.js';
import { leaf, split } from './shell/layout.js';
import { CommandPalette, requestPath, download } from './shell/dialogs.js';
import { filesWindow } from './windows/files.js';
import { editorWindow } from './windows/editor.js';
import { listenerWindow } from './windows/listener.js';
import { traceWindow } from './windows/machine.js';
import { debuggerWindow } from './windows/debugger.js';
import { problemsWindow, imageWindow } from './windows/problems.js';
import { buildWindow } from './windows/build.js';
import { observe, syncCommandButton } from './windows/common.js';
import { geometryWindow, packetsWindow, waitingWindow, historyWindow } from './windows/network.js';
import { displayWindow } from './windows/display.js';
import { CommandRegistry } from './shell/commands.js';
import { nodeAt } from './network/geometry.js';
import { documentationWindow } from './windows/documentation.js';
import { TOPICS, CONTEXT_TOPICS } from './documentation/manual.js';
import { projectFiles, projectSelection, chooseProjectImage } from './core/project.js';
import { commandState } from './core/command-state.js';

const el = id => document.getElementById(id);
const presets = {
  documentation: () => split('x', .58, leaf('documentation'), split('y', .72, leaf('editor'), leaf('listener'))),
  network: () => split('x', .52, split('y', .60, leaf('machine'), leaf('history')), split('y', .65, leaf('packets'), leaf('waiting'))),
  graphics: () => split('x', .48, split('y', .65, leaf('editor'), leaf('listener')), split('y', .65, leaf('display'), leaf('machine'))),
  development: () => split('x', .23, split('y', .52, leaf('files'), leaf('build')), split('x', .61, split('y', .72, leaf('editor'), leaf('listener')), split('y', .40, leaf('machine'), leaf('debugger')))),
  editing: () => split('x', .20, leaf('files'), split('y', .77, leaf('editor'), leaf('listener'))),
  debugging: () => split('y', .70, split('x', .55, leaf('editor'), leaf('debugger')), split('x', .5, leaf('machine'), leaf('trace'))),
  building: () => split('x', .18, leaf('files'), split('y', .62, leaf('editor'), split('x', .53, leaf('build'), leaf('listener')))),
};
async function fetchJson(path) {
  const response = await fetch(path); if (!response.ok) throw new Error(`${path}: HTTP ${response.status}`); return response.json();
}
async function initialize() {
  const [manifest, examples] = await Promise.all([fetchJson('./variants.json'), fetchJson('./examples/examples.json')]);
  const variants = manifest.variants.filter(v => Number.isInteger(v.nodes) && /^[\w.-]+\.js$/.test(v.js) && /^\d+x\d+x\d+$/.test(v.mesh));
  if (!variants.length) throw new Error('No usable simulator variants were built.');
  let storage;
  try { storage = window.localStorage; } catch { /* Explicitly report a volatile session below. */ }
  const fs = new VirtualFilesystem(storage);
  const sources = await Promise.all(examples.examples.filter(e => /^[\w.-]+\.c$/.test(e.file)).map(async example => {
    const response = await fetch(`./examples/${example.file}`); if (!response.ok) throw new Error(`Could not load ${example.file}: HTTP ${response.status}`);
    return { ...example, source: await response.text() };
  }));
  if (!fs.data.seeded) {
    let legacy; try { legacy = JSON.parse(storage?.getItem('jmc.workspace.v1')); } catch {}
    fs.seed(sources, legacy);
  }
  fs.mountExamples(sources);
  if (!fs.data.session.buildInitialized) {
    if (!fs.exists('/home/user/build.jm')) fs.create('/home/user/build.jm', DEFAULT_BUILD);
    fs.setSession({ buildInitialized: true });
  }
  const ide = new IDE(fs, variants), palette = new CommandPalette();
  const manager = new WindowManager(el('desktop'), {
    storage,
    onChange: layout => { el('focused-window').textContent = layout.focused ? manager.registry.get(layout.focused).title : 'DESKTOP'; },
    onSplit: (id, edge) => palette.open([...manager.registry.values()].filter(tool => tool.id !== id).map(tool => ({
      label: `${tool.title}`, detail: `${edge === 'right' ? 'To the right of' : 'Below'} ${manager.registry.get(id).title}${manager.visible(tool.id) ? ' · move existing window' : ''}`,
      run: () => ide.perform(() => manager.visible(tool.id) ? manager.move(tool.id, id, edge) : manager.open(tool.id, { relativeTo: id, edge })),
    })), { title: 'Split window', label: 'Tool to place in the split', placeholder: 'Find a tool…', verb: 'Place', help: 'workspace' }),
  });
  const editor = editorWindow(ide), files = filesWindow(ide), listener = listenerWindow(ide), documentation = documentationWindow(ide);
  const windows = [files, editor, geometryWindow(ide), debuggerWindow(ide), listener, problemsWindow(ide), traceWindow(ide), imageWindow(ide), buildWindow(ide), packetsWindow(ide), waitingWindow(ide), historyWindow(ide), displayWindow(ide), documentation];
  windows.forEach(tool => manager.register(tool));
  const act = run => () => ide.perform(run);
  const fileEntries = () => fs.files().map(path => ({ label: path, detail: `${ide.openPaths.includes(path) ? 'Open buffer' : 'Visit file'}${fs.stat(path).readOnly ? ' · read only' : ''}`, run: act(() => ide.openFile(path)) }));
  const saveAs = act(() => {
    if (!ide.activePath) throw new Error('Select a buffer first.');
    requestPath({ title: 'Write buffer to pathname', value: ide.uniquePath(`/home/user/${basename(ide.activePath)}`), submit: 'Write file', run: path => ide.saveAs(path) });
  });
  ide.services = {
    openWindow: id => manager.open(id, id === 'documentation' ? { atRoot: true, edge: 'right', ratio: .45 } : id === 'build' && manager.visible('listener') ? { relativeTo: 'listener', edge: 'right' } : undefined), choose: (entries, options) => palette.open(entries, options), saveAs,
    insertListener: (value, replace) => { manager.open('listener'); listener.insert(value, replace); }, selectDirectory: files.selectDirectory,
    findFile: () => palette.open(fileEntries(), { title: 'Open file', label: 'Workspace pathname', placeholder: 'Find a file in this workspace…', verb: 'Open', help: 'files' }),
    openDocumentation: topic => { ide.services.openWindow('documentation'); documentation.open(topic); },
    layout: name => { if (!presets[name]) throw new Error(`Unknown layout: ${name}. Use ${Object.keys(presets).join(', ')}.`); manager.setLayout(presets[name]()); ide.message(`Layout: ${name}`); },
  };
  const registry = new CommandRegistry({ execute: action => ide.perform(action) });
  const register = (id,label,run,keys=[],scope,options={}) => registry.register({id,label,run,keys,scope,state:()=>commandState(ide,id),...options});
  const focused = () => manager.layout.focused;
  const keyScope = () => document.activeElement?.closest?.('[data-window]')?.dataset.window;
  let helpTopic = 'welcome';
  const toolHelp = id => id === 'documentation' ? documentation.topic : id === 'editor' && /\.jm$/.test(ide.activePath ?? '') ? 'build' : CONTEXT_TOPICS[id] ?? 'welcome';
  const trackHelp = event => {
    if (event.target.closest?.('#help-menu,.command-palette,.path-dialog')) return;
    const topic = event.target.closest?.('[data-help]')?.dataset.help, tool = event.target.closest?.('[data-window]')?.dataset.window;
    if (topic || tool) helpTopic = topic ?? toolHelp(tool);
  };
  document.addEventListener('focusin', trackHelp); document.addEventListener('pointerdown', trackHelp);
  palette.onHelp = topic => ide.services.openDocumentation(topic ?? helpTopic);
  const moveWindow = () => { const source = focused(); return palette.open([...manager.registry.values()].filter(tool => tool.id !== source && manager.visible(tool.id)).map(tool => ({
    label: `Beside ${tool.title}`, detail: 'Choose the edge next', run: () => {
      palette.open(['left','right','top','bottom'].map(edge => ({ label: edge, detail: `Move ${source} ${edge} of ${tool.title}`, run: () => manager.move(source,tool.id,edge) })), { title: 'Move window', label: 'Destination edge', placeholder: 'Choose an edge…', verb: 'Move', help: 'workspace' });
    },
  })), { title: 'Move window', label: 'Destination window', placeholder: 'Choose a neighboring window…', verb: 'Choose', help: 'workspace' }); };
  const windowControls = () => {
    const tool = manager.registry.get(focused()); if (!tool) return;
    palette.open([...tool.element.querySelectorAll('button,input:not([hidden]),select,summary')].filter(e => !e.disabled && !e.matches('.packet-row,.event-row,.file-row')).map((control,index) => ({
      label: control.getAttribute('aria-label') || control.title || control.textContent || `Control ${index+1}`,
      detail: `${tool.title} · ${control.tagName.toLowerCase()}`, run: () => { manager.focus(tool.id,false); if(control.matches('button,summary'))control.click();else control.focus(); },
    })), { title: `${tool.title} controls`, label: 'Window control', placeholder: 'Find a control…', verb: 'Activate', help: toolHelp(tool.id) });
  };
  const showCommands = () => palette.open([...registry.entries(focused(), { allScopes: true }), ...fileEntries().map(entry=>({...entry,group:'Files',help:'files'}))], { shortcut: 'M-x', fallback: command => { manager.open('listener'); ide.command(command); } });
  register('commands','Search commands',showCommands,['Alt+x','Mod+Shift+p']);
  register('window-controls','Commands for focused window',windowControls,['Ctrl+Alt+k'],undefined,{enabled:()=>!!focused(),disabledReason:'Open a window first.',help:'keyboard'});
  register('find-file','Find file',ide.services.findFile,['Mod+o']);
  register('new-file','New file',files.createFile);
  register('new-directory','New directory',files.createDirectory);
  register('save','Save buffer',()=>ide.save(),['Mod+s']);
  register('save-as','Save buffer as…',saveAs,['Mod+Shift+s']);
  register('compile','Compile & Load buffer',()=>ide.compile(),['Mod+Enter'],undefined,{help:'editor'});
  register('build','Build project',()=>ide.build(),['Mod+b']);
  register('load-project','Load selected project image',()=>chooseProjectImage(ide));
  register('examples','Browse example programs',()=>palette.open(sources.map(example=>({label:example.title,detail:`${example.nodes} nodes · ${example.blurb}`,run:()=>ide.openFile(`/examples/${example.file}`)})),{title:'Example programs',label:'Example program',placeholder:'Find an example…',verb:'Open',help:'examples'}));
  register('build-graph','Edit build graph',()=>ide.openFile(ide.buildFile));
  register('use-buffer-build','Use buffer as project graph',()=>ide.selectBuildFile(ide.activePath),[],undefined,{help:'build'});
  register('load-built-image','Load built image',()=>palette.open(fs.files().filter(p=>fs.stat(p).metadata?.artifact).map(path=>({label:path,detail:fs.stat(path).metadata.artifact.sourcePath,run:act(()=>ide.loadArtifact(path))})),{title:'Load image',label:'Built image pathname',placeholder:'Find a compiled image…',verb:'Load',help:'build'}));
  register('continue','Run / pause loaded image',()=>ide.execute(),['F5']);
  register('pause','Pause machine',()=>ide.pause());
  register('step-instruction','Step instruction',()=>ide.execute('instruction'),['F10']);
  register('step-source','Step source',()=>ide.execute('source'),['F11']);
  register('step-cycle','Step one cycle',()=>ide.execute('cycles',1));
  register('step-100','Step 100 cycles',()=>ide.execute('cycles',100));
  register('breakpoint','Toggle source breakpoint',()=>ide.toggleBreakpoint(ide.editor.editor.getPosition()?.lineNumber),['F9']);
  register('reset','Reset machine',()=>ide.reset());
  register('restart','Restart loaded image',()=>ide.restart(),['Shift+F5'],undefined,{help:'debugger'});
  register('export-files','Export filesystem',()=>download('j-machine-filesystem.json',ide.exportSnapshot(),'application/json'));
  const layoutAction = group => ({menu:'layout',group,help:'workspace',enabled:()=>!!focused(),disabledReason:'Open a window first.'});
  register('window-zoom','Zoom / restore focused window',()=>manager.zoom(focused()),['Ctrl+Alt+Enter'],undefined,layoutAction('Arrange windows'));
  register('window-close','Close focused window',()=>manager.close(focused()),['Ctrl+Alt+Backspace'],undefined,layoutAction('Arrange windows'));
  register('window-next','Focus next window',()=>manager.cycle(1),['Ctrl+Alt+n'],undefined,layoutAction('Focus'));
  register('window-previous','Focus previous window',()=>manager.cycle(-1),['Ctrl+Alt+p'],undefined,layoutAction('Focus'));
  register('window-move','Move focused window',moveWindow,[],undefined,{...layoutAction('Arrange windows'),enabled:()=>windows.filter(tool=>manager.visible(tool.id)).length>1,disabledReason:'Open a second window to choose a destination.'});
  register('window-split-right','Split window to the right',()=>manager.onSplit(focused(),'right'),[],undefined,layoutAction('Arrange windows'));
  register('window-split-below','Split window below',()=>manager.onSplit(focused(),'bottom'),[],undefined,layoutAction('Arrange windows'));
  for (const [direction,key] of [['left','ArrowLeft'],['right','ArrowRight'],['up','ArrowUp'],['down','ArrowDown']]) {
    register(`focus-${direction}`,`Focus window ${direction}`,()=>manager.focusDirection(direction),[`Ctrl+Alt+${key}`],undefined,layoutAction('Focus'));
    register(`resize-${direction}`,`Resize focused window ${direction}`,()=>manager.resize(['left','right'].includes(direction)?'x':'y',['left','up'].includes(direction)?-.04:.04),[`Ctrl+Alt+Shift+${key}`],undefined,layoutAction('Resize'));
  }
  const windowGroups = { files:'Editing and building',editor:'Editing and building',listener:'Editing and building',build:'Editing and building',problems:'Editing and building',machine:'Debugging',debugger:'Debugging',packets:'Debugging',waiting:'Debugging',history:'Debugging',trace:'Output',image:'Output',display:'Output',documentation:'Documentation' };
  for (const tool of windows) register(`window-${tool.id}`,tool.title,()=>ide.services.openWindow(tool.id),[],undefined,{menu:'windows',group:windowGroups[tool.id],help:toolHelp(tool.id),detail:()=>manager.visible(tool.id)?'Focus window':'Open window'});
  for (const name of Object.keys(presets)) register(`layout-${name}`,`Layout: ${name}`,()=>ide.services.layout(name),[],undefined,{menu:'layout',group:'Presets',help:'workspace',detail:'Arrange tools; keep buffers and machine state'});
  register('listener-help','Listener help',()=>{manager.open('listener');ide.message(LISTENER_HELP);});
  register('documentation','Context help',()=>ide.services.openDocumentation(document.activeElement?.closest?.('[data-window]')?.dataset.window === 'documentation' ? documentation.topic : helpTopic),['F1']);
  register('documentation-topics','Browse documentation topics',()=>palette.open(TOPICS.map(topic=>({label:topic.title,detail:topic.summary,help:topic.id,run:()=>ide.services.openDocumentation(topic.id)})),{title:'Documentation topics',label:'Documentation topic',placeholder:'Find a topic…',verb:'Read',help:'welcome'}));
  register('documentation-search','Search documentation',()=>{ide.services.openWindow('documentation');documentation.search();},['Mod+f'],'documentation');
  register('documentation-back','Documentation: back',()=>{ide.services.openWindow('documentation');documentation.back();},['Alt+ArrowLeft'],'documentation',{enabled:()=>documentation.canBack,disabledReason:'No earlier documentation page.'});
  register('documentation-forward','Documentation: forward',()=>{ide.services.openWindow('documentation');documentation.forward();},['Alt+ArrowRight'],'documentation',{enabled:()=>documentation.canForward,disabledReason:'No later documentation page.'});
  register('editor-commands','Editor commands',()=>{manager.open('editor');ide.editor.editor.getAction('editor.action.quickCommand').run();});
  register('keyboard-help','Keyboard help',()=>{
    const details = registry.entries(keyScope()); palette.open(details.filter(c=>registry.keys(registry.commands.get(c.id)).length),{title:'Keyboard bindings',label:'Command or key binding',placeholder:'Find a command or key…',verb:'Execute',help:'keyboard'});
  },['Ctrl+Alt+h']);
  register('jump-node','Go to node or coordinate',()=>ide.services.jumpNode(),['Ctrl+Alt+g']);
  register('packet-filter','Filter packets',()=>{manager.open('packets');windows.find(w=>w.id==='packets').filter();});
  register('network-breakpoint','Add network breakpoint',()=>{manager.open('packets');windows.find(w=>w.id==='packets').element.querySelector('[aria-label="Network breakpoint type"]').focus();});
  register('trace-save','Save network trace',()=>ide.services.saveTrace());
  register('trace-open','Open network trace',()=>ide.services.openTrace());
  register('trace-live','Return to live trace',()=>{ide.archiveTrace=null;if(ide.debug)ide.debug.network.cursor=null;ide.emit('network');});
  register('trace-previous','Inspect previous trace event',()=>{ide.services.openWindow('history');windows.find(w=>w.id==='history').previous();},['Alt+ArrowLeft'],'history');
  register('trace-next','Inspect next trace event',()=>{ide.services.openWindow('history');windows.find(w=>w.id==='history').next();},['Alt+ArrowRight'],'history');
  register('display-save','Save graphical output as PNG',()=>windows.find(w=>w.id==='display').exportImage());
  register('keymap-edit','Edit keyboard bindings',()=>ide.openFile('/home/user/keymap.json'));
  register('keymap-reload','Reload keyboard bindings',()=>ide.services.reloadKeymap());
  register('keymap-reset','Use default keyboard bindings',()=>{registry.overrides={};ide.message('Default keyboard bindings active.');});
  for (const [topic, ids] of Object.entries({
    files:['find-file','new-file','new-directory','save','save-as','export-files'],
    build:['build','load-project','build-graph','use-buffer-build','load-built-image'],
    editor:['compile','breakpoint','editor-commands'],
    debugger:['continue','pause','step-instruction','step-source','step-cycle','step-100','reset','restart','jump-node'],
    keyboard:['commands','window-controls','keyboard-help','keymap-edit','keymap-reload','keymap-reset'],
    welcome:['documentation','documentation-topics','documentation-search','documentation-back','documentation-forward'],
    listener:['listener-help'],examples:['examples'],packets:['packet-filter','network-breakpoint'],
    history:['trace-save','trace-open','trace-live','trace-previous','trace-next'],display:['display-save'],
  })) for (const id of ids) { const command = registry.commands.get(id); command.help ??= topic; command.group ??= TOPICS.find(item=>item.id===topic).title; }
  const traceImporter = document.createElement('input'); traceImporter.type='file';traceImporter.accept='.json,.jmtrace';traceImporter.hidden=true;document.body.append(traceImporter);
  traceImporter.onchange=()=>ide.perform(async()=>{const file=traceImporter.files[0];if(file){if(file.size>64*1024*1024)throw new Error('Trace exceeds 64 MiB.');ide.openTrace(await file.text());}traceImporter.value='';});
  Object.assign(ide.services,{
    command:id=>registry.run(id),commandList:()=>registry.entries(focused(),{allScopes:true}),commandState:id=>registry.state(id),
    jumpNode:()=>requestPath({title:'Go to node',label:'Flat node number or x,y,z',value:String(ide.selectedNode),submit:'Inspect',run:value=>{
      const t=ide.network;if(!t)throw new Error('Load a machine first.');const node=value.includes(',')?nodeAt(value.split(',').map(s=>Number(s.trim())),t.dims):Number(value);
      if(!Number.isInteger(node)||node<0||node>=t.nodes)throw new Error('Node is outside this mesh.');
      if(ide.archiveTrace){ide.selectedNode=node;ide.emit('network');}else ide.selectNode(node);
    }}),
    saveTrace:async()=>download(`j-machine-${ide.network?.cycle??0}.jmtrace`,await ide.traceText(),'application/json'),
    openTrace:()=>traceImporter.click(),
    reloadKeymap:()=>{registry.loadKeymap(ide.text('/home/user/keymap.json'));ide.message('Keyboard bindings reloaded.');},
  });
  if(!fs.exists('/home/user/build-graphics.jm'))fs.create('/home/user/build-graphics.jm',`# Graphical examples; open Graphical Display after loading an image.
build /build/mandelbrot.image: jmc /examples/distributed_mandelbrot.c
  nodes = 4
build /build/rule110.image: jmc /examples/rule110.c
  nodes = 2
build /build/hotspot.image: jmc /examples/message_hotspot.c
  nodes = 16
build /build/rainbow.image: jmc /examples/mesh_rainbow.c
  nodes = 512
build graphics: phony /build/mandelbrot.image /build/rule110.image /build/hotspot.image /build/rainbow.image
default /build/mandelbrot.image
`);
  if(!fs.exists('/home/user/keymap.json'))fs.create('/home/user/keymap.json',registry.keymap());
  try{registry.loadKeymap(fs.read('/home/user/keymap.json'));}catch(error){ide.message(`Using default keys: ${error.message}`,'error');}
  const toolbarActions={'new-file':'new-file','find-file':'find-file','save-buffer':'save','compile-buffer':'compile','build-project':'build','edit-project':'build-graph','load-project':'load-project','project-targets':'window-build','run-machine':'continue','restart-machine':'restart','command-menu':'commands','help-menu':'documentation'};
  for(const [elementId,command]of Object.entries(toolbarActions))el(elementId).onclick=()=>registry.run(command);
  el('window-menu').onclick=()=>palette.open(registry.entries(undefined,{menu:'windows'}),{title:'Windows',label:'Tool window',placeholder:'Find a tool…',verb:'Open / Focus',help:'workspace'});
  el('layout-menu').onclick=()=>palette.open(registry.entries(undefined,{menu:'layout'}).sort((a,b)=>Number(b.group==='Presets')-Number(a.group==='Presets')),{title:'Layout',label:'Layout or window action',placeholder:'Find a preset, arrangement, focus, or resize action…',verb:'Apply',help:'workspace'});
  el('node-count').replaceChildren(...variants.map(variant => new Option(`${variant.nodes} nodes`, String(variant.nodes))));
  el('node-count').onchange = act(() => ide.setNodes(Number(el('node-count').value)));
  el('project-file').onchange = act(() => ide.selectBuildFile(el('project-file').value));
  el('project-target').onchange = act(() => ide.selectBuildTarget(el('project-target').value));
  const projectControls = observe(ide, ['build', 'files', 'state'], () => {
    const disabled = !ide.builder || ide.busy || !!ide.debug?.running;
    el('project-file').replaceChildren(...projectFiles(ide).map(path => new Option(path.replace(/^\/home\/user\//, ''), path)));
    el('project-file').value = ide.buildFile; el('project-file').title = ide.buildFile;
    el('project-file').disabled = !ide.builder || ide.busy;
    el('project-target').disabled = disabled;
    if (!ide.builder) return;
    try {
      const { graph, target } = projectSelection(ide);
      el('project-target').replaceChildren(new Option(`Defaults: ${graph.defaults.map(path=>graph.targets.get(path).label).join(', ')}`, ''), ...[...graph.targets.values()].map(step => new Option(`${step.label}${step.rule==='jmc' ? ` · ${step.nodes} nodes` : step.rule==='phony' ? ' · group' : ''}`,step.target)));
      el('project-target').value = target ?? ''; el('project-target').title = el('project-target').selectedOptions[0]?.textContent ?? '';
    } catch (error) { el('project-target').replaceChildren(new Option('Invalid graph', '')); el('project-target').title = error.message; el('project-target').disabled = true; }
  }); projectControls();
  const controls = observe(ide, ['state', 'buffers', 'build', 'files'], () => {
    for (const [elementId, command] of Object.entries(toolbarActions)) syncCommandButton(el(elementId),ide,command,{label:['continue','compile'].includes(command)});
    el('build-project').textContent = ide.builder?.running ? 'Building…' : 'Build';
    el('run-machine').classList.toggle('running',!!ide.debug?.running);
    el('node-count').disabled = ide.busy || !ide.ready || !!ide.debug?.running; el('node-count').value = String(ide.nodes);
    el('status-text').textContent = ide.status; el('status-text').title = ide.status;
    el('storage-state').textContent = storage ? 'LOCAL FS' : 'VOLATILE FS';
    if (palette.dialog.open) palette.render();
  }); controls(); manager.restore(presets.development());
  window.addEventListener('resize', () => manager.resized());
  document.addEventListener('visibilitychange', () => { if (document.hidden) ide.pause(); });
  document.addEventListener('keydown', event => {
    if (palette.dialog.open || document.querySelector('.path-dialog[open]')) return;
    if(registry.handle(event,keyScope()))event.stopPropagation();
  }, true);
  const query = new URL(location.href).searchParams, example = query.get('example');
  const requested = query.get('file') ?? (example && /^[\w.-]+\.c$/.test(example) ? fs.exists(`/home/user/${example}`) ? `/home/user/${example}` : `/examples/${example}` : undefined);
  if (!storage) ide.message('Browser storage is unavailable. This session is temporary; export files to keep them.', 'error');
  el('boot-message')?.remove();
  await ide.initialize(editor.editor, requested);
  await ide.initializeBuilder();
  if (query.has('help')) ide.services.openDocumentation(query.get('help') || 'welcome');
}
initialize().catch(error => {
  const status = el('status-text'); status.textContent = error.message;
  const boot = el('boot-message') ?? document.createElement('div'); boot.id = 'boot-message'; boot.className = 'boot-message'; boot.textContent = `Unable to start: ${error.message}`;
  const exportSaved = document.createElement('button'); exportSaved.textContent = 'Export stored filesystem';
  exportSaved.onclick = () => { try { download('j-machine-filesystem.json', localStorage.getItem(FILESYSTEM_KEY) ?? localStorage.getItem('jmc.filesystem.v1') ?? '{}', 'application/json'); } catch { status.textContent = 'Browser storage cannot be accessed.'; } };
  boot.append(exportSaved); el('desktop').replaceChildren(boot);
});
