import { basename, dirname } from '../core/filesystem.js';
import { requestPath, download } from '../shell/dialogs.js';
import { element, button, observe } from './common.js';

export function filesWindow(ide) {
  const root = element('div', 'files-window'), toolbar = element('div', 'file-actions'), tree = element('div', 'file-tree');
  tree.ariaLabel = 'Virtual filesystem'; tree.setAttribute('role','tree');
  const details = element('div', 'file-details'), selection = element('div', 'file-selection'), metadata = element('p');
  const operations = element('div', 'file-actions'), trash = element('details', 'trash'), summary = element('summary'), trashList = element('div');
  trash.append(summary, trashList); details.append(selection, metadata, operations, trash);
  let selected = '/home/user'; const expanded = new Set(['/home/user', '/examples']);
  const selectedEntry = () => ide.fs.exists(selected) ? ide.fs.stat(selected) : ide.fs.stat('/home/user');
  const writableDirectory = () => {
    const entry = selectedEntry(), path = entry.kind === 'directory' ? entry.path : dirname(entry.path);
    return path.startsWith('/examples') || path.startsWith('/build') ? '/home/user' : path;
  };
  const ask = (title, value, submit, run) => requestPath({ title, value, submit, run: async path => { ide.flush(); await run(path); } });
  const createFile = () => ask('Create file', ide.uniquePath(`${writableDirectory()}/untitled.c`), 'Create', path => { expanded.add(dirname(path)); ide.newFile(path); selected = ide.activePath; render(); });
  const createDirectory = () => ask('Create directory', `${writableDirectory()}/untitled`, 'Create', path => { ide.fs.mkdir(path); expanded.add(dirname(path)); expanded.add(path); selected = path; render(); });
  const importer = element('input'); importer.type = 'file'; importer.multiple = true; importer.hidden = true;
  importer.onchange = () => ide.perform(async () => {
    ide.flush(); const directory = writableDirectory(); expanded.add(directory);
    for (const file of importer.files) {
      if (file.size > 1024 * 1024) throw new Error(`${file.name} exceeds the 1 MiB source limit.`);
      const path = ide.uniquePath(`${directory}/${file.name.replace(/[/\\\0-\x1f]/g, '_')}`);
      ide.fs.create(path, await file.text(), { nodes: ide.nodes }); ide.openFile(path); selected = path;
    }
    importer.value = ''; render();
  });
  toolbar.append(button('+ File', 'Create a file', createFile), button('+ Dir', 'Create a directory', createDirectory), button('Import', 'Import files from this computer', () => importer.click()));
  const rename = button('Rename', 'Rename or move selected path', () => ask('Rename or move', selected, 'Move', path => { const old = selected; ide.fs.move(old, path); selected = path; expanded.add(dirname(path)); render(); }));
  const copy = button('Copy', 'Copy selected path into your workspace', () => ask('Copy pathname', ide.uniquePath(`/home/user/${basename(selected)}`), 'Copy', path => {
    ide.fs.copy(selected, path); selected = path; expanded.add(dirname(path)); if (ide.fs.stat(path).kind === 'file') ide.openFile(path); render();
  }));
  const remove = button('Trash', 'Move selected path to recoverable trash', () => ide.perform(() => { ide.flush(); const path = selected; ide.fs.remove(path); selected = dirname(path); ide.message(`Moved ${path} to trash.`); render(); }));
  const exportFile = button('Export', 'Download the selected file or a filesystem backup', () => ide.perform(() => {
    const entry = selectedEntry();
    if (entry.kind === 'file') download(entry.name, ide.text(entry.path));
    else download('j-machine-filesystem.json', ide.exportSnapshot(), 'application/json');
    ide.message(entry.kind === 'file' ? `Exported ${entry.path}` : 'Exported the filesystem, including drafts and saved versions.');
  }));
  const versions = button('Versions', 'Recover an earlier saved version as a new file', () => {
    const entry = selectedEntry();
    ide.services.choose(entry.history.map(version => ({ label: `Version ${version.revision}`, detail: `${entry.path} · ${new Date(version.modified).toLocaleString()}`,
      run: () => ide.perform(() => {
        const path = ide.uniquePath(`${dirname(entry.path)}/${basename(entry.path).replace(/(\.[^.]*)?$/, `-v${version.revision}$1`)}`);
        ide.fs.create(path, version.content, entry.metadata); ide.openFile(path); selected = path; render();
      }),
    })), { title: 'Recover file version', label: 'Saved version', placeholder: 'Find a saved version…', verb: 'Recover copy', help: 'files' });
  });
  operations.append(rename, copy, remove, exportFile, versions); root.append(toolbar, tree, details, importer);
  tree.addEventListener('keydown', event => {
    const current = event.target.closest('[data-path]'); if (!current) return;
    const rows = [...tree.querySelectorAll('[data-path]')], index = rows.indexOf(current), path = current.dataset.path;
    if (['ArrowUp','ArrowDown','Home','End'].includes(event.key)) {
      event.preventDefault(); const next = event.key === 'Home' ? 0 : event.key === 'End' ? rows.length - 1 : Math.max(0,Math.min(rows.length - 1,index + (event.key === 'ArrowDown' ? 1 : -1)));
      selected = rows[next].dataset.path; rows[next].focus(); render();
    } else if (event.key === 'ArrowLeft' || event.key === 'ArrowRight') {
      event.preventDefault();
      if (ide.fs.stat(path).kind === 'directory' && (event.key === 'ArrowRight' || expanded.has(path))) {
        if(event.key === 'ArrowRight')expanded.add(path);else expanded.delete(path);render();
      } else if(event.key === 'ArrowLeft') { const parent = rows.find(row => row.dataset.path === dirname(path)); if(parent){selected=parent.dataset.path;parent.focus();render();} }
    }
  });
  const render = observe(ide, ['files', 'buffers'], () => {
    if (!ide.fs.exists(selected)) selected = '/home/user';
    tree.replaceChildren();
    const visit = (entry, depth) => {
      const directory = entry.kind === 'directory', isOpen = expanded.has(entry.path);
      const row = button('', `${directory ? 'Directory' : 'Open'} ${entry.path}`, () => ide.perform(() => {
        selected = entry.path;
        if (directory) { if (expanded.has(entry.path)) expanded.delete(entry.path); else expanded.add(entry.path); }
        else ide.openFile(entry.path);
        render();
      }), `file-row${entry.path === selected ? ' selected' : ''}${entry.path === ide.activePath ? ' active' : ''}`);
      row.setAttribute('role','treeitem'); row.setAttribute('aria-level',String(depth+1)); row.setAttribute('aria-selected',String(entry.path===selected)); row.tabIndex=entry.path===selected?0:-1;
      row.dataset.path = entry.path; row.dataset.focusKey = `file-${entry.path}`;
      row.style.paddingLeft = `${10 + depth * 14}px`;
      row.append(element('span', 'file-icon', directory ? isOpen ? '▾' : '▸' : '·'), element('span', 'file-name', depth === 0 ? `${entry.path}/` : entry.name + (directory ? '/' : '')));
      const modified = !directory && ide.dirty(entry.path);
      row.append(element('span', 'file-mark', modified ? '●' : entry.readOnly ? 'R' : entry.generated ? 'G' : ''));
      if (directory) row.setAttribute('aria-expanded', String(isOpen)); tree.append(row);
      if (directory && isOpen) for (const child of ide.fs.list(entry.path)) visit(child, depth + 1);
    };
    const roots = ['/home/user', '/examples', '/build'];
    for (const entry of [...ide.fs.list('/'), ...ide.fs.list('/home')]) if (entry.path !== '/home' && !roots.includes(entry.path)) roots.push(entry.path);
    for (const path of roots) visit(ide.fs.stat(path), 0);
    const entry = selectedEntry(), protectedPath = ['/home/user', '/examples', '/build'].includes(entry.path);
    selection.textContent = entry.path; selection.title = entry.path;
    metadata.textContent = entry.kind === 'directory' ? `${ide.fs.list(entry.path).length} entries${entry.readOnly ? ' · read only' : ''}` : `${new TextEncoder().encode(ide.fs.read(entry.path)).length.toLocaleString()} bytes · v${entry.revision}${entry.readOnly ? ' · read only' : ''}`;
    rename.disabled = remove.disabled = protectedPath || !!entry.readOnly;
    copy.disabled = protectedPath; versions.disabled = entry.kind !== 'file' || !entry.history?.length;
    for (const control of [rename, copy, remove, versions]) control.hidden = control.disabled;
    summary.textContent = `Trash (${ide.fs.data.trash.length})`;
    trashList.replaceChildren(...ide.fs.data.trash.map(item => {
      const row = element('div', 'trash-row'); row.append(element('span', '', item.path), button('Restore', `Restore ${item.path}`, () => ide.perform(() => { ide.fs.restore(item.id); ide.message(`Restored ${item.path}`); }))); return row;
    }));
    if (!trashList.children.length) trashList.append(element('p', 'empty-state', 'Trash is empty.'));
  }); render();
  const operation = (control, name) => () => { if (control.disabled) throw new Error(`${name} does not apply to ${selected}.`); control.click(); };
  return { id: 'files', title: 'FILES', element: root, onFocus: () => (tree.querySelector('[aria-selected=true]') ?? tree.querySelector('button'))?.focus(), createFile, createDirectory,
    rename: operation(rename, 'Rename'), copy: operation(copy, 'Copy'), trash: operation(remove, 'Trash'), versions: operation(versions, 'Versions'),
    selectDirectory: path => { selected = path; for (let current = path; current !== '/'; current = dirname(current)) expanded.add(current); render(); },
  };
}
