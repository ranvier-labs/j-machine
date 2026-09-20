// Content-Length framed JSON-RPC transport for editors outside the browser.
import { readFile } from 'node:fs/promises';
import { CompilerWasm } from '../site/runtime.js';
import { LanguageServer } from '../site/language.js';

console.debug = (...args) => console.error(...args);
const compilerModule = await WebAssembly.compile(await readFile(new URL('../dist/compiler.wasm', import.meta.url)));
function send(message) {
  const json = JSON.stringify(message);
  process.stdout.write(`Content-Length: ${Buffer.byteLength(json)}\r\n\r\n${json}`);
}
const server = new LanguageServer({ compile: async (...args) => (await CompilerWasm.fromBytes(compilerModule)).compile(...args), publish: send });
let buffer = Buffer.alloc(0), pending = Promise.resolve();
process.stdin.on('data', chunk => {
  buffer = Buffer.concat([buffer, chunk]);
  while (true) {
    const boundary = buffer.indexOf('\r\n\r\n');
    if (boundary < 0) break;
    const length = buffer.subarray(0, boundary).toString().match(/(?:^|\r\n)Content-Length:\s*(\d+)/i);
    if (!length || Number(length[1]) > 8 * 1024 * 1024) { console.error('Invalid LSP frame'); process.exit(1); }
    const end = boundary + 4 + Number(length[1]);
    if (buffer.length < end) break;
    const payload = buffer.subarray(boundary + 4, end).toString();
    buffer = buffer.subarray(end);
    pending = pending.then(async () => {
      let message;
      try { message = JSON.parse(payload); }
      catch { send({ jsonrpc: '2.0', id: null, error: { code: -32700, message: 'Parse error' } }); return; }
      const response = await server.receive(message);
      if (response) send(response);
      if (message.method === 'exit') process.exit(server.shutdown ? 0 : 1);
    });
  }
});
process.stdin.on('end', () => pending.finally(() => server.dispose()));
