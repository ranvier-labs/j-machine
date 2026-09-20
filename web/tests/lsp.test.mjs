import test from 'node:test';
import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import { spawn } from 'node:child_process';
import { CompilerWasm } from '../site/runtime.js';
import { LanguageServer, positionAt, offsetAt, compilerDiagnostic } from '../site/language.js';

const bytes = await readFile(new URL('../dist/compiler.wasm', import.meta.url));
const module = await WebAssembly.compile(bytes);
const uri = 'file:///workspace/test.c';
const source = 'int total;\nint work(int value) {\n int total = value;\n { int value = 1; total += value; }\n return total;\n}\nint main(void) { return work(1); }\n';
function setup(t) {
  const notifications = [];
  const server = new LanguageServer({ debounce: 100000, publish: message => notifications.push(message),
    compile: async (...args) => (await CompilerWasm.fromBytes(module)).compile(...args) });
  t.after(() => server.dispose());
  let id = 0;
  const request = (method, params) => server.receive({ jsonrpc: '2.0', id: ++id, method, params });
  const notify = (method, params) => server.receive({ jsonrpc: '2.0', method, params });
  const open = (text, version = 1) => notify('textDocument/didOpen', { textDocument: { uri, languageId: 'mdc', text, version } });
  const at = (fragment, occurrence = 0) => {
    let offset = -1;
    for (let i = 0; i <= occurrence; i++) offset = source.indexOf(fragment, offset + 1);
    return { textDocument: { uri }, position: positionAt(source, offset) };
  };
  return { server, notifications, request, notify, open, at };
}

test('LSP lifecycle, lexical scope, definition, references and dialect completions', async t => {
  const { request, notify, open, at } = setup(t);
  assert.equal((await request('textDocument/hover', {})).error.code, -32002);
  const initialized = await request('initialize', { initializationOptions: { nodes: 4, mesh: '2x2x1' } });
  assert.equal(initialized.result.capabilities.positionEncoding, 'utf-16');
  await open(source);
  const completion = (await request('textDocument/completion', at('return total'))).result;
  assert.ok(completion.items.some(item => item.label === 'computer' && item.detail === 'int computer(void)'));
  assert.ok(completion.items.some(item => item.label === 'value'));
  const inner = (await request('textDocument/definition', at('value; }'))).result;
  assert.equal(inner.range.start.line, 3);
  const parameter = (await request('textDocument/definition', at('value;', 0))).result;
  assert.equal(parameter.range.start.line, 1);
  const refs = (await request('textDocument/references', { ...at('value;', 0), context: { includeDeclaration: true } })).result;
  assert.equal(refs.length, 2, 'inner-block value must not bind to the parameter');
  assert.equal((await request('textDocument/definition', at('work(1)'))).result.range.start.line, 1);
  assert.equal((await request('textDocument/documentSymbol', { textDocument: { uri } })).result.filter(s => s.kind === 12).length, 2);
  await notify('textDocument/didChange', { textDocument: { uri, version: 2 }, contentChanges: [{ text: 'int main(void) {return computer()@' }] });
  const nodes = (await request('textDocument/completion', { textDocument: { uri }, position: { line: 0, character: 'int main(void) {return computer()@'.length } })).result;
  assert.deepEqual(nodes.items.map(item => item.label), ['0', '1', '2', '3']);
  assert.equal((await request('no/such/method', {})).error.code, -32601);
  await request('shutdown');
  assert.equal((await request('textDocument/completion', at('return total'))).error.code, -32600);
});

test('compiler diagnostics recover after invalid edits and reject stale compile requests', async t => {
  const { request, notify, notifications, open } = setup(t);
  await request('initialize', {});
  await open('int main(void) {\n  return missing;\n}\n');
  assert.match((await request('jmc/compile', { textDocument: { uri }, version: 1 })).error.message, /undeclared/);
  const error = notifications.at(-1).params.diagnostics[0];
  assert.equal(error.range.start.line, 1);
  assert.equal(error.range.start.character, 9);
  await notify('textDocument/didChange', { textDocument: { uri, version: 2 }, contentChanges: [{ text: 'int main(void) {return 42;}' }] });
  assert.equal((await request('jmc/compile', { textDocument: { uri }, version: 1 })).error.code, -32801);
  const valid = await request('jmc/compile', { textDocument: { uri }, version: 2 });
  assert.ok(valid.result.image.includes('@source'));
  assert.deepEqual(notifications.at(-1).params.diagnostics, []);
  await notify('textDocument/didClose', { textDocument: { uri } });
  assert.equal((await request('textDocument/hover', { textDocument: { uri }, position: { line: 0, character: 1 } })).error.code, -32602);
});

test('UTF-16 positions cover CRLF and Unicode scalar compiler columns', () => {
  const text = '// 😀\r\nint main(void) { return 0; }';
  for (const offset of [0, 3, 5, 8, text.length]) assert.equal(offsetAt(text, positionAt(text, offset)), offset);
  const error = compilerDiagnostic('/* 😀 */ missing', new Error('<browser>:1:9: unknown'));
  assert.equal(error.range.start.character, 9);
});

test('stdio LSP accepts split UTF-8 Content-Length frames and shuts down', async t => {
  const child = spawn(process.execPath, [new URL('../lsp/stdio.mjs', import.meta.url).pathname], { stdio: ['pipe', 'pipe', 'pipe'] });
  t.after(() => child.kill());
  let buffer = Buffer.alloc(0), pending = new Map(), stderr = '';
  child.stderr.on('data', data => { stderr += data; });
  child.stdout.on('data', data => {
    buffer = Buffer.concat([buffer, data]);
    while (true) {
      const boundary = buffer.indexOf('\r\n\r\n'); if (boundary < 0) return;
      const length = Number(buffer.subarray(0, boundary).toString().match(/Content-Length: (\d+)/)[1]);
      if (buffer.length < boundary + 4 + length) return;
      const message = JSON.parse(buffer.subarray(boundary + 4, boundary + 4 + length));
      buffer = buffer.subarray(boundary + 4 + length);
      if (pending.has(message.id)) { pending.get(message.id)(message); pending.delete(message.id); }
    }
  });
  function send(message) {
    const payload = JSON.stringify({ jsonrpc: '2.0', ...message });
    const frame = Buffer.from(`Content-Length: ${Buffer.byteLength(payload)}\r\n\r\n${payload}`);
    const response = message.id ? new Promise((resolve, reject) => {
      pending.set(message.id, resolve); const timeout = setTimeout(() => reject(new Error(`LSP timeout ${stderr}`)), 10000); timeout.unref();
    }) : null;
    child.stdin.write(frame.subarray(0, frame.length - 2)); child.stdin.write(frame.subarray(frame.length - 2));
    return response;
  }
  assert.equal((await send({ id: 1, method: 'initialize', params: {} })).result.serverInfo.name, 'jmc-language-server');
  send({ method: 'textDocument/didOpen', params: { textDocument: { uri, version: 1, text: '// 😀\nint main(void) {return computer();}' } } });
  const hover = await send({ id: 2, method: 'textDocument/hover', params: { textDocument: { uri }, position: { line: 1, character: 24 } } });
  assert.match(hover.result.contents.value, /physical node/);
  await send({ id: 3, method: 'shutdown' });
  const exited = new Promise(resolve => child.once('exit', resolve));
  send({ method: 'exit' });
  assert.equal(await exited, 0);
});
