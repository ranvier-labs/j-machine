export const textOf = parts => parts.map(part => typeof part === 'string' ? part : part.text).join('');
export const quoteArgument = value => /[\s"\\]/.test(String(value)) ? `"${String(value).replace(/\\/g, '\\\\').replace(/"/g, '\\"')}"` : String(value);

// Presentation values retain object identity. The listener renders them as
// buttons; it never reconstructs an action from rendered HTML.
export function presentText(text, paths = [], sourcePath) {
  const matches = [];
  for (const path of paths) {
    if (path === '/') continue;
    let start = text.indexOf(path);
    while (start !== -1) {
      const end = start + path.length;
      if (!/[\w./-]/.test(text[end] ?? '') && (start === 0 || !/[\w./-]/.test(text[start - 1]))) {
        const location = text.slice(end).match(/^:(\d+)(?::(\d+))?/);
        matches.push({ start, end: end + (location?.[0].length ?? 0), type: location ? 'source' : 'path', path,
          ...(location ? { line: Number(location[1]), column: Number(location[2] ?? 1) } : {}) });
      }
      start = text.indexOf(path, end);
    }
  }
  for (const match of text.matchAll(/\bnode (\d+)\b/gi)) matches.push({ start: match.index, end: match.index + match[0].length, type: 'node', node: Number(match[1]) });
  if (sourcePath) for (const match of text.matchAll(/\bline (\d+)\b/gi)) matches.push({ start: match.index, end: match.index + match[0].length, type: 'source', path: sourcePath, line: Number(match[1]), column: 1 });
  matches.sort((a, b) => a.start - b.start || b.end - a.end);
  const parts = []; let cursor = 0;
  for (const match of matches) {
    if (match.start < cursor) continue;
    if (match.start > cursor) parts.push(text.slice(cursor, match.start));
    const { start, end, ...value } = match; parts.push({ ...value, text: text.slice(start, end) }); cursor = end;
  }
  if (cursor < text.length) parts.push(text.slice(cursor));
  return parts;
}
export function presentationValue(value) {
  if (value.type === 'command') return value.command;
  if (value.type === 'node') return String(value.node);
  if (value.type === 'packet') return String(value.packet);
  if (value.type === 'documentation') return value.topic;
  return value.path ?? value.target ?? value.text;
}
export function presentationHelp(value) {
  const action = { command: 'Recall command', path: 'Visit pathname', source: 'Visit source location', node: 'Inspect node', target: 'Inspect build target', packet: 'Inspect packet', documentation: 'Read documentation' }[value.type] ?? 'Select value';
  return `${action}: ${presentationValue(value)} · Enter visits; Shift+Enter or Shift-click inserts into the listener`;
}
