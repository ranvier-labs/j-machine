import { CompilerWasm } from './runtime.js';
import { LanguageServer } from './language.js';

const engine = fetch(new URL(`./compiler.wasm?v=${globalThis.__JM_BUILD_ID__ ?? 'dev'}`, self.location.href)).then(async response => {
  if (!response.ok) throw new Error(`compiler.wasm: HTTP ${response.status}`);
  const bytes = await response.arrayBuffer();
  const [module, digest] = await Promise.all([WebAssembly.compile(bytes), crypto.subtle.digest('SHA-256', bytes)]);
  return { module, identity: [...new Uint8Array(digest)].map(byte => byte.toString(16).padStart(2, '0')).join('') };
});
// Serialize requests so didChange/compile ordering is identical in both transports.
const server = new LanguageServer({
  // A failed Wasm call can leave its native stack and heap in an unusable
  // state. Each compiler request gets fresh memory; the compiled code is reused.
  compile: async (...args) => (await CompilerWasm.fromBytes((await engine).module)).compile(...args),
  publish: message => self.postMessage(message),
});
let pending = Promise.resolve();
self.onmessage = ({ data }) => {
  pending = pending.then(async () => {
    if (['jmc/compileSource', 'jmc/compilerIdentity'].includes(data.method)) {
      try {
        const { module, identity } = await engine;
        if (data.method === 'jmc/compilerIdentity') { self.postMessage({ jsonrpc: '2.0', id: data.id, result: identity }); return; }
        const { source, nodes, mesh } = data.params ?? {};
        if (typeof source !== 'string' || ![2, 4, 16, 512].includes(nodes) || typeof mesh !== 'string') throw new Error('Invalid build compiler request.');
        const image = (await CompilerWasm.fromBytes(module)).compile(source, nodes, mesh);
        self.postMessage({ jsonrpc: '2.0', id: data.id, result: { image } });
      } catch (error) { self.postMessage({ jsonrpc: '2.0', id: data.id, error: { code: -32603, message: error.message } }); }
      return;
    }
    // Initialization includes engine readiness; failed loading is visible to the client.
    if (data.method === 'initialize') {
      try { await engine; }
      catch (error) {
        self.postMessage({ jsonrpc: '2.0', id: data.id, error: { code: -32603, message: String(error.message ?? error) } });
        return;
      }
    }
    const response = await server.receive(data);
    if (response) self.postMessage(response);
  });
};
