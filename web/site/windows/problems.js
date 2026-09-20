import { element, button, observe } from './common.js';
export function problemsWindow(ide) {
  const root = element('div', 'problems-window');
  const render = observe(ide, ['diagnostics', 'buffers'], () => {
    root.replaceChildren();
    for (const [file, items] of ide.diagnostics) for (const item of items) {
      const line = item.range.start.line + 1, column = item.range.start.character + 1;
      const row = button('', `Open ${file} at line ${line}`, () => ide.perform(() => ide.reveal(file, line, column)), 'problem-row');
      row.append(element('span', 'problem-location', `${file}:${line}:${column}`), element('span', '', item.message)); root.append(row);
    }
    if (!root.children.length) root.append(element('p', 'empty-state', ide.ready ? 'No problems in open buffers.' : 'Waiting for the language server.'));
  }); render(); return { id: 'problems', title: 'PROBLEMS', element: root };
}
export function imageWindow(ide) {
  const root = element('div', 'image-window'), bar = element('div', 'tool-strip'), path = element('span'), open = button('Visit file', 'Open generated image in the editor', () => ide.perform(() => ide.openFile(ide.imagePath)));
  const text = element('pre', 'image-output', 'Compile a buffer to inspect its tagged words and source map.'); bar.append(path, open); root.append(bar, text);
  const render = observe(ide, ['image'], () => { path.textContent = ide.imagePath ?? '/build'; open.disabled = !ide.imagePath; text.textContent = ide.image ?? 'Compile a buffer to inspect its tagged words and source map.'; }); render();
  return { id: 'image', title: 'COMPILED IMAGE', element: root };
}
