import * as monaco from 'monaco-editor/editor/editor.api.js';
import 'monaco-editor/editor/browser/coreCommands.js';
import 'monaco-editor/editor/contrib/suggest/browser/suggestController.js';
import 'monaco-editor/editor/contrib/hover/browser/hoverContribution.js';
import 'monaco-editor/editor/contrib/gotoSymbol/browser/goToCommands.js';
import 'monaco-editor/editor/contrib/gotoError/browser/gotoError.js';
import 'monaco-editor/editor/contrib/find/browser/findController.js';
import 'monaco-editor/editor/contrib/folding/browser/folding.js';
import 'monaco-editor/editor/contrib/bracketMatching/browser/bracketMatching.js';
import 'monaco-editor/editor/contrib/clipboard/browser/clipboard.js';
import 'monaco-editor/editor/contrib/contextmenu/browser/contextmenu.js';
import 'monaco-editor/editor/contrib/wordOperations/browser/wordOperations.js';
import 'monaco-editor/editor/contrib/linesOperations/browser/linesOperations.js';
import 'monaco-editor/editor/contrib/parameterHints/browser/parameterHints.js';
import { KEYWORDS, BUILTINS } from './language.js';

globalThis.MonacoEnvironment = { getWorker: () => new Worker(new URL('./editor.worker.js', window.location.href), { type: 'module' }) };
const toRange = range => new monaco.Range(range.start.line + 1, range.start.character + 1, range.end.line + 1, range.end.character + 1);
const toPosition = position => ({ line: position.lineNumber - 1, character: position.column - 1 });
const location = item => ({ uri: monaco.Uri.parse(item.uri), range: toRange(item.range) });

class LanguageClient {
  constructor(onDiagnostics, onFailure) {
    this.worker = new Worker(new URL('./language.worker.js', window.location.href), { type: 'module' });
    this.pending = new Map(); this.nextId = 1;
    this.worker.onmessage = ({ data }) => {
      if (data.method === 'textDocument/publishDiagnostics') { onDiagnostics(data.params); return; }
      if (data.method === 'window/showMessage') { onFailure(data.params.message); return; }
      const waiter = this.pending.get(data.id);
      if (!waiter) return;
      this.pending.delete(data.id); clearTimeout(waiter.timer);
      if (data.error) waiter.reject(new Error(data.error.message)); else waiter.resolve(data.result);
    };
    this.worker.onerror = event => {
      this.error = new Error(event.message || 'Language worker failed.');
      for (const waiter of this.pending.values()) { clearTimeout(waiter.timer); waiter.reject(this.error); }
      this.pending.clear();
      onFailure(this.error.message);
    };
  }
  notify(method, params) { this.worker.postMessage({ jsonrpc: '2.0', method, params }); }
  request(method, params = {}) {
    if (this.error) return Promise.reject(this.error);
    const id = this.nextId++;
    return new Promise((resolve, reject) => {
      const timer = setTimeout(() => { this.pending.delete(id); reject(new Error(`${method} timed out.`)); }, 120000);
      this.pending.set(id, { resolve, reject, timer });
      this.worker.postMessage({ jsonrpc: '2.0', id, method, params });
    });
  }
}

export class WorkbenchEditor {
  constructor(element, { onChange, onDiagnostics, onBreakpoint, onCursor, onFailure, commands }) {
    this.onBreakpoint = onBreakpoint; this.onDiagnostics = onDiagnostics;
    this.models = new Map(); this.onChange = onChange;
    this.client = new LanguageClient(params => {
      const entry = [...this.models.values()].find(entry => entry.model.uri.toString() === params.uri);
      if (!entry || (params.version !== undefined && params.version !== entry.model.getVersionId())) return;
      const diagnostics = params.diagnostics;
      monaco.editor.setModelMarkers(entry.model, 'jmc', diagnostics.map(d => ({
        ...toRange(d.range), message: d.message, severity: monaco.MarkerSeverity.Error, source: d.source,
      })));
      onDiagnostics(diagnostics, entry.path);
    }, onFailure);
    monaco.languages.register({ id: 'mdc', extensions: ['.c'], aliases: ['Message-Driven C', 'mdc'] });
    monaco.languages.setLanguageConfiguration('mdc', {
      comments: { lineComment: '//', blockComment: ['/*', '*/'] },
      brackets: [['{', '}'], ['[', ']'], ['(', ')']],
      autoClosingPairs: [{ open: '{', close: '}' }, { open: '[', close: ']' }, { open: '(', close: ')' }, { open: '"', close: '"' }],
    });
    monaco.languages.setMonarchTokensProvider('mdc', {
      keywords: KEYWORDS, builtins: BUILTINS.map(b => b.name),
      tokenizer: { root: [
        [/\/\*/, 'comment', '@comment'], [/\/\/.*$/, 'comment'], [/"([^"\\]|\\.)*"/, 'string'], [/'([^'\\]|\\.)*'/, 'string'],
        [/^\s*#\s*\w+/, 'keyword'], [/[a-zA-Z_]\w*/, { cases: { '@keywords': 'keyword', '@builtins': 'predefined', '@default': 'identifier' } }],
        [/0[xX][0-9a-fA-F]+|\d+[uUlL]*/, 'number'], [/@/, 'operator.remote'], [/[{}()[\]]/, '@brackets'], [/[-+*/%=!<>|&^~?:]+/, 'operator'],
      ], comment: [[/[^/*]+/, 'comment'], [/\*\//, 'comment', '@pop'], [/[/*]/, 'comment']] },
    });
    monaco.editor.defineTheme('j-machine', {
      base: 'vs-dark', inherit: true,
      rules: [
        { token: '', foreground: 'D6D6CE' }, { token: 'comment', foreground: '85857F', fontStyle: 'italic' },
        { token: 'keyword', foreground: 'F0F0E9', fontStyle: 'bold' }, { token: 'number', foreground: 'C6C6BF' },
        { token: 'string', foreground: 'B6B6AE' }, { token: 'operator.remote', foreground: 'D7AE68', fontStyle: 'bold' },
        { token: 'predefined', foreground: 'E2E2DA' },
      ],
      colors: {
        'editor.background': '#101010', 'editor.foreground': '#D6D6CE', 'editorLineNumber.foreground': '#71716B',
        'editorLineNumber.activeForeground': '#ECECE5', 'editorCursor.foreground': '#D7AE68',
        'editor.selectionBackground': '#40403A', 'editor.inactiveSelectionBackground': '#30302D',
        'editor.lineHighlightBackground': '#1B1B19', 'editorIndentGuide.background1': '#282825',
        'editorGutter.background': '#101010', 'editorWidget.background': '#1C1C1A',
        'editorWidget.border': '#65655E', 'editorSuggestWidget.selectedBackground': '#3B3B35',
        'editorError.foreground': '#D88373', 'editorOverviewRuler.border': '#101010',
        'focusBorder': '#D7AE68', 'scrollbarSlider.background': '#77777055',
      },
    });
    this.editor = monaco.editor.create(element, {
      theme: 'j-machine', language: 'mdc', automaticLayout: true,
      fontFamily: 'Menlo, "DejaVu Sans Mono", Consolas, monospace', fontSize: 13, lineHeight: 21,
      glyphMargin: true, lineNumbersMinChars: 3, scrollBeyondLastLine: false,
      minimap: { enabled: false }, renderLineHighlight: 'line', cursorStyle: 'block',
      cursorBlinking: 'solid', smoothScrolling: false, padding: { top: 14, bottom: 14 },
      tabSize: 2, insertSpaces: true, folding: true, stickyScroll: { enabled: false },
      bracketPairColorization: { enabled: false }, overviewRulerLanes: 0,
      ariaLabel: 'Message-Driven C source editor', quickSuggestions: true,
      model: null,
    });
    this.breakpointDecorations = this.editor.createDecorationsCollection();
    this.executionDecorations = this.editor.createDecorationsCollection();
    this.editor.onDidChangeCursorPosition(event => onCursor(event.position));
    this.editor.onMouseDown(event => {
      if (event.target.type === monaco.editor.MouseTargetType.GUTTER_GLYPH_MARGIN && event.target.position) onBreakpoint(event.target.position.lineNumber);
    });
    const bindings = [
      ['compile', 'Compile and load', monaco.KeyMod.CtrlCmd | monaco.KeyCode.Enter],
      ['continue', 'Run / pause loaded image', monaco.KeyCode.F5],
      ['instruction', 'Step one instruction', monaco.KeyCode.F10],
      ['source', 'Step to next source line', monaco.KeyCode.F11],
      ['breakpoint', 'Toggle source breakpoint', monaco.KeyCode.F9],
      ['save', 'Save buffer', monaco.KeyMod.CtrlCmd | monaco.KeyCode.KeyS],
      ['saveAs', 'Write buffer to pathname', monaco.KeyMod.CtrlCmd | monaco.KeyMod.Shift | monaco.KeyCode.KeyS],
      ['open', 'Find file', monaco.KeyMod.CtrlCmd | monaco.KeyCode.KeyO],
    ];
    for (const [id, label, key] of bindings) this.editor.addAction({ id: `jmc.${id}`, label, keybindings: [],
      run: () => id === 'breakpoint' ? onBreakpoint(this.editor.getPosition()?.lineNumber) : commands[id]() });
    this.registerProviders();
    monaco.languages.register({ id: 'jmc-build', extensions: ['.jm'] });
    monaco.languages.setMonarchTokensProvider('jmc-build', { tokenizer: { root: [
      [/^\s*#.*$/, 'comment'], [/\b(build|default|nodes)\b/, 'keyword'], [/\b(jmc|copy|phony)\b/, 'type'],
      [/"([^"\\]|\\.)*"/, 'string'], [/\b\d+\b/, 'number'], [/[:=]/, 'delimiter'],
    ] } });
    monaco.languages.setLanguageConfiguration('jmc-build', { comments: { lineComment: '#' } });
  }

  async initialize(options) {
    await this.client.request('initialize', { processId: null, rootUri: null, capabilities: {
      general: { positionEncodings: ['utf-16'] }, textDocument: { publishDiagnostics: { versionSupport: true } },
    }, initializationOptions: options });
    this.client.notify('initialized', {});
  }
  document(version = false, model = this.model) { return { uri: model.uri.toString(), ...(version ? { version: model.getVersionId() } : {}) }; }
  get value() { return this.model?.getValue() ?? ''; }
  setSource(text, file, { readOnly = false } = {}) {
    this.replacing = true;
    if (this.activePath && this.models.has(this.activePath)) this.models.get(this.activePath).viewState = this.editor.saveViewState();
    let entry = this.models.get(file);
    if (!entry) {
      const language = /\.[ch]$/.test(file) ? 'mdc' : /\.jm$/.test(file) ? 'jmc-build' : 'plaintext';
      const model = monaco.editor.createModel(text, language, monaco.Uri.file(file));
      entry = { path: file, model }; this.models.set(file, entry);
      if (language === 'mdc') this.client.notify('textDocument/didOpen', { textDocument: { ...this.document(true, model), languageId: 'mdc', text } });
      entry.listener = model.onDidChangeContent(() => {
        if (this.replacing) return;
        if (language === 'mdc') this.client.notify('textDocument/didChange', { textDocument: this.document(true, model), contentChanges: [{ text: model.getValue() }] });
        if (model === this.model) this.executionDecorations.clear();
        this.onChange(file, model.getValue());
      });
    }
    this.model = entry.model; this.activePath = file;
    this.editor.setModel(this.model); this.breakpointDecorations.clear(); this.executionDecorations.clear();
    this.editor.updateOptions({ readOnly });
    if (entry.viewState) this.editor.restoreViewState(entry.viewState);
    this.replacing = false;
  }
  syncSource(file, text) {
    const model = this.models.get(file)?.model;
    if (!model || model.getValue() === text) return;
    this.replacing = true; model.setValue(text); this.replacing = false;
    if (model.getLanguageId() === 'mdc') this.client.notify('textDocument/didChange', { textDocument: this.document(true, model), contentChanges: [{ text }] });
  }
  close(file) {
    const entry = this.models.get(file); if (!entry) return;
    if (entry.model.getLanguageId() === 'mdc') this.client.notify('textDocument/didClose', { textDocument: this.document(false, entry.model) });
    if (this.activePath === file) { this.editor.setModel(null); this.activePath = null; this.model = null; }
    entry.listener.dispose(); entry.model.dispose(); this.models.delete(file);
  }
  getText(file) { return this.models.get(file)?.model.getValue(); }
  getVersion(file = this.activePath) { return this.models.get(file)?.model.getVersionId(); }
  focus() { this.editor.focus(); }
  layout() { this.editor.layout(); }
  configure(options) { this.client.notify('workspace/didChangeConfiguration', { settings: { jmc: options } }); }
  compile() { return this.client.request('jmc/compile', { textDocument: this.document(), version: this.model.getVersionId() }); }
  compileSource(source, nodes, mesh) { return this.client.request('jmc/compileSource', { source, nodes, mesh }); }
  compilerIdentity() { return this.client.request('jmc/compilerIdentity'); }
  reveal(line, column = 1) { this.editor.setPosition({ lineNumber: line, column }); this.editor.revealLineInCenterIfOutsideViewport(line); this.editor.focus(); }
  setBreakpoints(breakpoints, info, stale) {
    this.breakpointDecorations.set(breakpoints.filter(bp => bp.line).map(bp => ({
      range: new monaco.Range(bp.line, 1, bp.line, 1), options: {
        glyphMarginClassName: !stale && info.entries.has(bp.line) ? 'breakpoint-glyph' : 'breakpoint-pending-glyph',
        glyphMarginHoverMessage: { value: !stale && info.entries.has(bp.line) ? 'Source breakpoint · F9 to remove' : 'Pending breakpoint · compile an executable source line' },
        stickiness: monaco.editor.TrackedRangeStickiness.NeverGrowsWhenTypingAtEdges,
      },
    })));
  }
  showExecution(line) {
    this.executionDecorations.set(line ? [{ range: new monaco.Range(line, 1, line, 1), options: {
      isWholeLine: true, className: 'execution-line', linesDecorationsClassName: 'execution-arrow',
    } }] : []);
    if (line) this.editor.revealLineInCenterIfOutsideViewport(line);
  }
  registerProviders() {
    const request = (method, model, pos, extra = {}) => this.client.request(method, {
      textDocument: { uri: model.uri.toString() }, ...(pos ? { position: toPosition(pos) } : {}), ...extra,
    });
    monaco.languages.registerCompletionItemProvider('mdc', {
      triggerCharacters: ['@'], provideCompletionItems: async (model, position) => {
        const result = await request('textDocument/completion', model, position);
        const word = model.getWordUntilPosition(position);
        return { suggestions: result.items.map(item => ({ ...item,
          kind: item.kind === 3 ? monaco.languages.CompletionItemKind.Function : item.kind === 14
            ? monaco.languages.CompletionItemKind.Keyword : monaco.languages.CompletionItemKind.Variable,
          insertText: item.insertText ?? item.label,
          range: new monaco.Range(position.lineNumber, word.startColumn, position.lineNumber, word.endColumn),
        })) };
      },
    });
    monaco.languages.registerHoverProvider('mdc', { provideHover: async (model, position) => {
      const result = await request('textDocument/hover', model, position);
      return result ? { range: toRange(result.range), contents: [{ value: result.contents.value }] } : null;
    } });
    monaco.languages.registerDefinitionProvider('mdc', { provideDefinition: async (model, position) => {
      const result = await request('textDocument/definition', model, position); return result ? location(result) : null;
    } });
    monaco.languages.registerReferenceProvider('mdc', { provideReferences: async (model, position, context) =>
      (await request('textDocument/references', model, position, { context })).map(location) });
    monaco.languages.registerDocumentSymbolProvider('mdc', { provideDocumentSymbols: async model =>
      (await request('textDocument/documentSymbol', model)).map(s => ({ ...s, tags: [], kind: s.kind - 1,
        range: toRange(s.range), selectionRange: toRange(s.selectionRange) })) });
  }
}
