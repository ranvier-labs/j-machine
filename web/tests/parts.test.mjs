import test from 'node:test';
import assert from 'node:assert/strict';
import { fetchWithProgress } from '../site/runtime.js';

// A host with a per-file size limit serves `<name>.parts.json` and the parts;
// the runtime reassembles them and reports progress against the full size.
test('a missing binary falls back to its parts listing and reports total progress', async () => {
  const files = new Map([
    ['/simulator_512.wasm.parts.json', JSON.stringify({ size: 5, parts: ['simulator_512.wasm.part0', 'simulator_512.wasm.part1'] })],
    ['/simulator_512.wasm.part0', new Uint8Array([1, 2, 3])], ['/simulator_512.wasm.part1', new Uint8Array([4, 5])],
  ]);
  const requested = [];
  const original = globalThis.fetch;
  globalThis.fetch = async url => {
    const target = new URL(url); requested.push(target.pathname + target.search);
    const body = files.get(target.pathname);
    // Like Cloudflare Pages: a missing path answers with the index page.
    return body === undefined ? new Response('<!doctype html><title>index</title>', { status: 200, headers: { 'content-type': 'text/html; charset=utf-8' } })
      : new Response(body, { status: 200, headers: { 'content-type': target.pathname.endsWith('.json') ? 'application/json' : 'application/octet-stream' } });
  };
  try {
    const events = [];
    const bytes = await fetchWithProgress(new URL('https://example.test/simulator_512.wasm?v=abc'), event => events.push(event));
    assert.deepEqual([...bytes], [1, 2, 3, 4, 5]);
    assert.deepEqual(requested, ['/simulator_512.wasm?v=abc', '/simulator_512.wasm.parts.json?v=abc', '/simulator_512.wasm.part0?v=abc', '/simulator_512.wasm.part1?v=abc']);
    assert.equal(events.at(-1).loaded, 5); assert.equal(events.at(-1).total, 5);
    await assert.rejects(fetchWithProgress(new URL('https://example.test/missing.wasm')), /failed to fetch \/missing\.wasm \(not found\)/);
  } finally { globalThis.fetch = original; }
});
