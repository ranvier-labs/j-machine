import { WorkbenchEditor } from '../editor.js';
import { basename } from '../core/filesystem.js';
import { element, button, observe, syncCommandButton } from './common.js';

export function editorWindow(ide) {
  const root = element('div', 'editor-window'), tabs = element('div', 'buffer-tabs'); tabs.setAttribute('role', 'tablist'); tabs.ariaLabel = 'Open buffers';
  const pathname = element('div', 'buffer-path'), path = element('span'), state = element('span');
  const useGraph = button('Use graph', 'Use this buffer as the project build graph', () => ide.services.command('use-buffer-build'));
  pathname.append(path, useGraph, state);
  const host = element('div', 'source-editor'), modeline = element('div', 'editor-modeline');
  const position = element('span', '', 'Ln 1, Col 1'), language = element('span', '', 'MDC'), info = element('button', 'text-button', 'Starting compiler…');
  info.onclick = () => ide.services.openWindow('problems'); modeline.append(position, language, info);
  root.append(tabs, pathname, host, modeline);
  const editor = new WorkbenchEditor(host, {
    onChange: (file, text) => ide.edited(file, text), onDiagnostics: (items, file) => ide.setDiagnostics(items, file),
    onBreakpoint: line => ide.perform(() => ide.toggleBreakpoint(line)),
    onCursor: value => { position.textContent = `Ln ${value.lineNumber}, Col ${value.column}`; },
    onFailure: message => ide.message(message, 'error'),
    commands: {
      compile: () => ide.perform(() => ide.compile()), continue: () => ide.perform(() => ide.execute()),
      instruction: () => ide.perform(() => ide.execute('instruction')), source: () => ide.perform(() => ide.execute('source')),
      save: () => ide.perform(() => ide.save()), saveAs: () => ide.services.saveAs(), open: () => ide.services.findFile(),
    },
  });
  tabs.addEventListener('keydown', event => {
    if(!['ArrowLeft','ArrowRight','Home','End'].includes(event.key)||!event.target.matches('[role=tab]'))return;
    const paths=ide.openPaths,index=paths.indexOf(ide.activePath),next=event.key==='Home'?0:event.key==='End'?paths.length-1:(index+(event.key==='ArrowRight'?1:-1)+paths.length)%paths.length;
    event.preventDefault();ide.perform(()=>ide.openFile(paths[next],{focus:false}));tabs.querySelectorAll('[role=tab]')[next]?.focus();
  });
  const render = observe(ide, ['buffers', 'state', 'diagnostics', 'build'], () => {
    tabs.replaceChildren(...ide.openPaths.map(file => {
      const tab = element('div', `buffer-tab${file === ide.activePath ? ' active' : ''}`);
      const open = button(`${ide.dirty(file) ? '● ' : ''}${basename(file)}`, `Switch to ${file}`, () => ide.perform(() => ide.openFile(file)));
      open.setAttribute('role', 'tab'); open.tabIndex=file===ide.activePath?0:-1; open.dataset.focusKey=`tab-${file}`; open.setAttribute('aria-selected', String(file === ide.activePath));
      tab.append(open, button('×', `Close buffer ${file}`, () => ide.perform(() => ide.closeFile(file)), 'close-buffer')); return tab;
    }));
    const active = ide.active();
    path.textContent = ide.activePath ?? 'No buffer selected'; path.title = path.textContent;
    useGraph.hidden = !/\.jm$/.test(ide.activePath ?? '');
    useGraph.textContent = ide.activePath === ide.buildFile ? 'Active graph' : 'Use graph';
    syncCommandButton(useGraph,ide,'use-buffer-build');
    state.textContent = !active ? '' : active.readOnly ? 'READ ONLY · Save as to edit' : active.generated ? 'GENERATED' : ide.dirty(ide.activePath) ? 'MODIFIED · draft retained' : `SAVED · v${active.revision}`;
    state.classList.toggle('modified', !!active && ide.dirty(ide.activePath));
    language.textContent = /\.[ch]$/.test(ide.activePath ?? '') ? 'Message-Driven C' : /\.jm$/.test(ide.activePath ?? '') ? 'JMC Build' : 'Text';
    const count = [...ide.diagnostics.values()].reduce((n, items) => n + items.length, 0);
    info.textContent = ide.ready ? count ? `${count} problem${count === 1 ? '' : 's'}` : 'JMC / ready' : 'Starting compiler…';
    info.classList.toggle('error-text', count > 0);
  }); render();
  return { id: 'editor', title: 'EDITOR', element: root, editor, onFocus: () => editor.focus(), onResize: () => editor.layout() };
}
