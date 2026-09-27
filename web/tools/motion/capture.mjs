// Records what the machine does while it runs the example programs, so the
// motion piece can draw real node activity, packet counts, and framebuffers.
// Output: out/motion/data/<name>.json. Usage: node tools/motion/capture.mjs [names...]
import { mkdir, readFile, writeFile } from 'node:fs/promises';
import { CompilerWasm, SimulatorWasm } from '../../site/runtime.js';
import { debugImage } from '../../site/debugger.js';
import { readFramebuffer } from '../../site/graphics/framebuffer.js';
import { dimensions, encodedNode } from '../../site/network/geometry.js';

const root = new URL('../../../', import.meta.url), dist = new URL('../../dist/', import.meta.url);
const variants = JSON.parse(await readFile(new URL('variants.json', dist), 'utf8')).variants;
const compiled = await WebAssembly.compile(await readFile(new URL('compiler.wasm', dist)));
// sample: cycles between activity samples; frames: cycles between framebuffer
// reads; budget: wall-clock seconds; limit: cycle cap.
const programs = {
  life16: { file: 'life16.c', nodes: 16, sample: 4000, frames: 20000, budget: 240, limit: 6_500_000 },
  heat16: { file: 'heat16.c', nodes: 16, sample: 4000, frames: 20000, budget: 300, limit: 11_500_000 },
  hotspot: { file: 'message_hotspot.c', nodes: 16, sample: 200, frames: 0, budget: 120, limit: 2_000_000 },
  mandelbrot: { file: 'distributed_mandelbrot.c', nodes: 4, sample: 2000, frames: 20000, budget: 240, limit: 12_000_000 },
  mesh512: { file: 'mesh512.c', nodes: 512, sample: 100, frames: 0, budget: 420, limit: 3_000_000 },
  rainbow: { file: 'mesh_rainbow.c', nodes: 512, sample: 100, frames: 2000, budget: 240, limit: 400_000 },
};
const requested = process.argv.slice(2).length ? process.argv.slice(2) : Object.keys(programs);
await mkdir('out/motion/data', { recursive: true });
for (const name of requested) {
  const p = programs[name]; if (!p) throw new Error(`unknown program ${name}`);
  const variant = variants.find(v => v.nodes === Math.max(2, p.nodes));
  const compiler = await CompilerWasm.fromBytes(compiled);
  const source = await readFile(new URL(`compiler/examples/${p.file}`, root), 'utf8');
  const image = compiler.compile(source, variant.nodes, variant.mesh);
  const info = debugImage(image), dims = dimensions(variant.mesh);
  const factory = (await import(new URL(variant.js, dist).href)).default;
  const simulator = await SimulatorWasm.create(factory, { nodes: variant.nodes, wasmBinary: await readFile(new URL(variant.wasm, dist)) });
  const started = Date.now();
  try {
    simulator.loadImage(image); simulator.traceEnabled(true);
    let last = simulator.snapshot().nodes.map(n => n.retired), cycle = 0, nextFrame = 0, frameSeen = new Map();
    const samples = [], frames = [];
    let lastLog = 0;
    while (cycle < p.limit && simulator.peek(0, 0x300) === 0n && (Date.now() - started) / 1000 < p.budget) {
      const snap = simulator.runBatch(Math.min(1024, p.sample - (cycle % p.sample) || p.sample));
      cycle = Number(snap.cycle);
      if (cycle % p.sample === 0 || cycle >= p.limit) {
        const trace = simulator.drainTrace();
        const sends = new Array(p.nodes).fill(0), dispatches = new Array(p.nodes).fill(0);
        for (const e of trace.events) { const node = encodedNode(e.node, dims); if (node === null || node >= p.nodes) continue; if (e.kind === 1) sends[node]++; else if (e.kind === 8) dispatches[node]++; }
        const retired = snap.nodes.map(n => n.retired), delta = retired.map((r, i) => Number(r - last[i])); last = retired;
        samples.push({ cycle, retired: delta, sends, dispatches, pending: snap.nodes.map(n => n.queuePending) });
      }
      if (p.frames && (cycle >= nextFrame || simulator.peek(0, 0x300) !== 0n)) {
        nextFrame = cycle + p.frames;
        for (let node = 0; node < p.nodes; node++) {
          const fb = readFramebuffer(info, simulator, node); if (!fb || fb.frame === null) continue;
          if (frameSeen.get(node) === fb.frame) continue; frameSeen.set(node, fb.frame);
          frames.push({ cycle, node, frame: fb.frame, width: fb.width, height: fb.height, rgb: Buffer.from(fb.pixels).toString('base64') });
        }
      }
      if (Date.now() - lastLog > 10000) { lastLog = Date.now(); console.log(`${name}: cycle ${cycle.toLocaleString()} · ${samples.length} samples · ${frames.length} frames · ${((Date.now() - started) / 1000).toFixed(0)}s`); }
    }
    const result = simulator.peek(0, 0x300), done = result !== 0n;
    const totals = samples.reduce((t, s) => ({ retired: t.retired + s.retired.reduce((a, b) => a + b, 0), sends: t.sends + s.sends.reduce((a, b) => a + b, 0), dispatches: t.dispatches + s.dispatches.reduce((a, b) => a + b, 0) }), { retired: 0, sends: 0, dispatches: 0 });
    const out = { name, file: p.file, nodes: p.nodes, mesh: variant.mesh, cycles: cycle, done, result: done ? Number(result & 0xffffffffn) : null, sample: p.sample, totals, samples, frames, source, seconds: (Date.now() - started) / 1000 };
    await writeFile(`out/motion/data/${name}.json`, JSON.stringify(out));
    console.log(`${name}: ${p.nodes} nodes · ${cycle.toLocaleString()} cycles · done=${done} result=${out.result} · ${samples.length} samples · ${frames.length} frames · retired ${totals.retired.toLocaleString()} · sends ${totals.sends.toLocaleString()} · ${out.seconds.toFixed(0)}s`);
  } finally { simulator.destroy(); }
}
