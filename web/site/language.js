// A small, transport-independent LSP 3.17 server. Lean remains the authority
// for diagnostics; this lexical index supplies navigation while code is edited.
export const KEYWORDS = (`auto break case char const continue default do else enum extern for goto if
inline int long register restrict return short signed sizeof static struct switch typedef union
unsigned void volatile while _Alignas _Alignof _Atomic _Bool _Generic _Noreturn _Static_assert
_Thread_local`).split(/\s+/);
const TYPES = new Set('void char short int long signed unsigned _Bool _Atomic struct union enum'.split(' '));
const QUALIFIERS = new Set('const volatile restrict static extern register auto inline _Noreturn _Thread_local typedef'.split(' '));
export const BUILTINS = [
  { name: 'computer', signature: 'int computer(void)', detail: 'The current physical node number.' },
  { name: 'computers', signature: 'int computers(void)', detail: 'The number of nodes in the selected machine.' },
];
const REMOTE_HELP = 'function(arguments)@node sends a Message-Driven C call to that node. A value-returning call produces a future; reading the value waits for its result. A void call sends a one-way message.';
const point = (line = 0, character = 0) => ({ line, character });

export function positionAt(text, offset) {
  const lines = text.slice(0, offset).split(/\r\n|\r|\n/);
  return point(lines.length - 1, lines.at(-1).length);
}

export function offsetAt(text, position) {
  const lines = text.split(/\r\n|\r|\n/);
  let offset = 0;
  for (let i = 0; i < Math.min(position.line, lines.length - 1); i++) {
    offset += lines[i].length;
    offset += text.slice(offset, offset + 2) === '\r\n' ? 2 : 1;
  }
  return Math.min(text.length, offset + Math.min(position.character, lines[Math.min(position.line, lines.length - 1)].length));
}

export function indexDocument(text) {
  const tokens = [];
  const pattern = /\/\*[\s\S]*?(?:\*\/|$)|\/\/[^\r\n]*|(?:u8|[LuU])?"(?:\\[\s\S]|[^"\\])*"|'(?:\\[\s\S]|[^'\\])*'|^[ \t]*#[^\r\n]*|[A-Za-z_]\w*|\d+(?:\.\d+)?|->|[^\s]/gm;
  for (const match of text.matchAll(pattern)) {
    if (/^(\/\/|\/\*|[ \t]*#|(?:u8|[LuU])?"|')/.test(match[0])) continue;
    tokens.push({ text: match[0], start: match.index, end: match.index + match[0].length });
  }
  const root = { start: 0, end: text.length, depth: 0 };
  const stack = [root], pairs = new Map(), openings = [];
  tokens.forEach((token, i) => {
    token.scope = stack.at(-1);
    if ('({['.includes(token.text)) {
      openings.push(i);
      if (token.text === '{') {
        token.body = { start: token.start, end: text.length, depth: stack.length };
        stack.push(token.body);
      }
    } else if (')}]'.includes(token.text)) {
      const start = openings.at(-1);
      if (start !== undefined && '({['.indexOf(tokens[start].text) === ')}]'.indexOf(token.text)) {
        openings.pop(); pairs.set(start, i); pairs.set(i, start);
      }
      if (token.text === '}' && stack.length > 1) stack.pop().end = token.end;
    }
  });
  const symbols = [];
  const names = new Set([...TYPES, ...QUALIFIERS]);
  const makeSymbol = (token, kind, detail, scope = token.scope, end = token.end) => {
    const symbol = { name: token.text, kind, detail, start: token.start, end, scope,
      selectionRange: { start: positionAt(text, token.start), end: positionAt(text, token.end) },
      range: { start: positionAt(text, token.start), end: positionAt(text, end) } };
    symbols.push(symbol);
    return symbol;
  };
  // Identify declarations by a type/specifier prefix, never by call syntax
  // alone. Brace scopes keep local shadowing out of other functions/blocks.
  for (let i = 0; i < tokens.length; i++) {
    const token = tokens[i];
    if (!names.has(token.text) || names.has(tokens[i - 1]?.text)) continue;
    if (['sizeof', '_Alignof'].includes(tokens[i - 2]?.text)) continue;
    let j = i, isType = false, isTypedef = false;
    while (j < tokens.length && names.has(tokens[j].text)) {
      isType ||= TYPES.has(tokens[j].text) || !QUALIFIERS.has(tokens[j].text);
      isTypedef ||= tokens[j].text === 'typedef';
      const aggregate = ['struct', 'union', 'enum'].includes(tokens[j].text);
      j++;
      if (aggregate && /^[A-Za-z_]\w*$/.test(tokens[j]?.text ?? '')) {
        if (tokens[j + 1]?.text === '{') {
          makeSymbol(tokens[j], 23, text.slice(token.start, tokens[j].end));
          break;
        }
        j++;
      }
    }
    if (!isType) continue;
    while (tokens[j]?.text === '*' || QUALIFIERS.has(tokens[j]?.text)) j++;
    const name = tokens[j];
    if (!name || !/^[A-Za-z_]\w*$/.test(name.text) || KEYWORDS.includes(name.text)) continue;
    if (tokens[j + 1]?.text === '(') {
      const close = pairs.get(j + 1), after = tokens[(close ?? j) + 1];
      if (close !== undefined && ['{', ';'].includes(after?.text)) {
        const end = after.text === '{' ? tokens[pairs.get(close + 1)]?.end ?? after.end : after.end;
        makeSymbol(name, 12, text.slice(token.start, tokens[close].end).replace(/\s+/g, ' '), root, end);
        if (after.body) for (let k = j + 2; k < close; k++) tokens[k].scope = after.body;
      }
    } else {
      const type = text.slice(token.start, name.start).trim();
      makeSymbol(name, isTypedef ? 5 : 13, `${type} ${name.text}`);
      if (isTypedef) names.add(name.text);
      // More declarators in the same statement, skipping initializers and
      // balanced calls/arrays. Parameters are indexed by their own type.
      for (let k = j + 1; k < tokens.length; k++) {
        if ([';', ')', '{', '}'].includes(tokens[k].text)) break;
        if (['(', '['].includes(tokens[k].text) && pairs.has(k)) { k = pairs.get(k); continue; }
        if (tokens[k].text === ',') {
          let next = k + 1;
          while (tokens[next]?.text === '*') next++;
          if (names.has(tokens[next]?.text)) break;
          if (/^[A-Za-z_]\w*$/.test(tokens[next]?.text ?? '')) makeSymbol(tokens[next], 13, `${type} ${tokens[next].text}`);
        }
      }
    }
  }
  const unique = [...new Map(symbols.map(symbol => [symbol.start, symbol])).values()];
  const tokenAt = offset => tokens.find(token => token.start <= offset && offset < token.end)
    ?? tokens.find(token => token.end === offset);
  const visible = offset => unique.filter(s => s.scope.start <= offset && offset <= s.scope.end
    && (s.kind === 12 || s.scope.depth === 0 || s.start <= offset));
  const resolve = (name, offset) => unique.find(s => s.name === name && s.start === offset)
    ?? visible(offset).filter(s => s.name === name)
    .sort((a, b) => b.scope.depth - a.scope.depth || (b.end - b.start) - (a.end - a.start) || b.start - a.start)[0];
  return { tokens, symbols: unique, tokenAt, visible, resolve };
}

export function compilerDiagnostic(text, error) {
  const message = String(error.message ?? error);
  const match = message.match(/(?:^|\n)[^\n]*?:(\d+):(\d+):\s*(?:error:\s*)?([\s\S]*)/);
  let start = point();
  if (match) {
    const lines = text.split(/\r\n|\r|\n/);
    const line = Math.max(0, Math.min(lines.length - 1, Number(match[1]) - 1));
    // Lean counts Unicode scalars; LSP positions use UTF-16 code units.
    start = point(line, [...lines[line]].slice(0, Math.max(0, Number(match[2]) - 1)).join('').length);
  }
  const rest = text.slice(offsetAt(text, start));
  const length = rest.match(/^[A-Za-z_]\w*/)?.[0].length ?? (rest.length ? 1 : 0);
  return { range: { start, end: point(start.line, start.character + length) },
    severity: 1, source: 'jmc', message: match ? match[3] : message };
}

export class LanguageServer {
  constructor({ compile, publish = () => {}, debounce = 350 }) {
    this.compile = compile; this.publish = publish; this.debounce = debounce;
    this.documents = new Map(); this.initialized = false; this.shutdown = false;
    this.options = { nodes: 2, mesh: '2x1x1' };
  }

  notify(method, params) { this.publish({ jsonrpc: '2.0', method, params }); }

  async validate(uri) {
    const doc = this.documents.get(uri);
    if (!doc) return;
    clearTimeout(doc.timer);
    const config = JSON.stringify(this.options);
    try {
      const image = doc.compilation?.config === config ? doc.compilation.image
        : await this.compile(doc.text, this.options.nodes, this.options.mesh);
      if (this.documents.get(uri) !== doc || JSON.stringify(this.options) !== config) return;
      doc.compilation = { config, image };
      this.notify('textDocument/publishDiagnostics', { uri, version: doc.version, diagnostics: [] });
      return image;
    } catch (error) {
      if (this.documents.get(uri) === doc) {
        this.notify('textDocument/publishDiagnostics', {
          uri, version: doc.version, diagnostics: error.name === 'JmcCompileError' ? [compilerDiagnostic(doc.text, error)] : [],
        });
        if (error.name !== 'JmcCompileError') this.notify('window/showMessage', { type: 1, message: `Compiler engine failed: ${error.message}` });
      }
      throw error;
    }
  }

  schedule(uri) {
    const doc = this.documents.get(uri);
    clearTimeout(doc.timer);
    doc.timer = setTimeout(() => { this.validate(uri).catch(() => {}); }, this.debounce);
  }

  async receive(message) {
    if (!message || message.jsonrpc !== '2.0' || typeof message.method !== 'string') {
      return { jsonrpc: '2.0', id: message?.id ?? null, error: { code: -32600, message: 'Invalid Request' } };
    }
    const isRequest = Object.hasOwn(message, 'id');
    try {
      const result = await this.dispatch(message.method, message.params ?? {});
      if (isRequest) return { jsonrpc: '2.0', id: message.id, result: result ?? null };
    } catch (error) {
      if (isRequest) return { jsonrpc: '2.0', id: message.id, error: {
        code: error.code ?? -32603, message: String(error.message ?? error),
      } };
    }
  }

  async dispatch(method, params) {
    const fail = (code, message) => { throw Object.assign(new Error(message), { code }); };
    if (method === 'initialize') {
      this.initialized = true;
      this.options = { ...this.options, ...params.initializationOptions };
      return { serverInfo: { name: 'jmc-language-server', version: '1.0.0' }, capabilities: {
        positionEncoding: 'utf-16', textDocumentSync: { openClose: true, change: 1 },
        completionProvider: { triggerCharacters: ['@'] }, hoverProvider: true,
        definitionProvider: true, referencesProvider: true, documentSymbolProvider: true,
      } };
    }
    if (method === 'exit') { this.dispose(); return; }
    if (!this.initialized) fail(-32002, 'Server not initialized');
    if (this.shutdown) fail(-32600, 'Server has shut down');
    if (method === 'shutdown') { this.shutdown = true; this.dispose(); return null; }
    if (['initialized', '$/cancelRequest', 'textDocument/didSave'].includes(method)) return;
    if (method === 'workspace/didChangeConfiguration') {
      this.options = { ...this.options, ...params.settings?.jmc };
      for (const uri of this.documents.keys()) this.schedule(uri);
      return;
    }
    const uri = params.textDocument?.uri;
    if (method === 'textDocument/didOpen' || method === 'textDocument/didChange') {
      const previous = this.documents.get(uri);
      const version = params.textDocument.version;
      if (previous && version <= previous.version) return;
      if (method.endsWith('didChange') && !previous) fail(-32602, 'Document is not open');
      let text = params.textDocument.text ?? previous?.text ?? '';
      for (const change of params.contentChanges ?? []) {
        text = change.range ? text.slice(0, offsetAt(text, change.range.start)) + change.text
          + text.slice(offsetAt(text, change.range.end)) : change.text;
      }
      clearTimeout(previous?.timer);
      this.documents.set(uri, { text, version, index: indexDocument(text) });
      this.schedule(uri); return;
    }
    if (method === 'textDocument/didClose') {
      clearTimeout(this.documents.get(uri)?.timer); this.documents.delete(uri);
      this.notify('textDocument/publishDiagnostics', { uri, diagnostics: [] }); return;
    }
    const supported = ['textDocument/completion', 'textDocument/hover', 'textDocument/definition',
      'textDocument/references', 'textDocument/documentSymbol', 'jmc/compile'];
    if (!supported.includes(method)) fail(-32601, `Method not found: ${method}`);
    const doc = this.documents.get(uri);
    if (!doc) fail(-32602, 'Document is not open');
    if (method === 'jmc/compile') {
      if (params.version !== undefined && params.version !== doc.version) fail(-32801, 'Document changed');
      const image = await this.validate(uri);
      if (!image || this.documents.get(uri) !== doc) fail(-32801, 'Document changed');
      return { image, version: doc.version, uri };
    }
    const index = doc.index;
    const offset = offsetAt(doc.text, params.position ?? point());
    const token = index.tokenAt(offset);
    const symbol = token && index.resolve(token.text, offset);
    const builtin = token && BUILTINS.find(b => b.name === token.text);
    const location = s => ({ uri, range: s.selectionRange });
    switch (method) {
      case 'textDocument/completion': {
        if (doc.text[offset - 1] === '@') return { isIncomplete: false, items: Array.from({ length: this.options.nodes }, (_, node) => ({
          label: String(node), kind: 12, detail: `Physical node ${node}`, insertText: String(node),
        })) };
        const items = new Map();
        for (const label of KEYWORDS) items.set(label, { label, kind: 14, detail: 'Message-Driven C keyword' });
        for (const b of BUILTINS) items.set(b.name, { label: b.name, kind: 3, detail: b.signature, documentation: b.detail });
        for (const s of index.visible(offset)) {
          const resolved = index.resolve(s.name, offset);
          items.set(s.name, { label: s.name, kind: resolved.kind === 12 ? 3 : 6, detail: resolved.detail });
        }
        return { isIncomplete: false, items: [...items.values()] };
      }
      case 'textDocument/hover': {
        const value = token?.text === '@' ? REMOTE_HELP : builtin
          ? `\`\`\`c\n${builtin.signature}\n\`\`\`\n${builtin.detail}` : symbol
          ? `\`\`\`c\n${symbol.detail}\n\`\`\`` : null;
        return value ? { contents: { kind: 'markdown', value }, range: {
          start: positionAt(doc.text, token.start), end: positionAt(doc.text, token.end),
        } } : null;
      }
      case 'textDocument/definition': return symbol ? location(symbol) : null;
      case 'textDocument/references': return symbol ? index.tokens.filter(t => t.text === symbol.name
        && index.resolve(t.text, t.start) === symbol && (params.context?.includeDeclaration || t.start !== symbol.start))
        .map(t => ({ uri, range: { start: positionAt(doc.text, t.start), end: positionAt(doc.text, t.end) } })) : [];
      case 'textDocument/documentSymbol': return index.symbols.filter(s => s.scope.depth === 0).map(s => ({
        name: s.name, detail: s.detail, kind: s.kind, range: s.range, selectionRange: s.selectionRange,
      }));
    }
  }

  dispose() { for (const doc of this.documents.values()) clearTimeout(doc.timer); this.documents.clear(); }
}
