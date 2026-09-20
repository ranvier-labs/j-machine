// Regenerate documentation images from the actual compiler and RTL simulator.
import { readFile, writeFile, mkdir } from 'node:fs/promises';
import { deflateSync } from 'node:zlib';
import { CompilerWasm, SimulatorWasm } from './site/runtime.js';
import { debugImage } from './site/debugger.js';
import { readFramebuffer } from './site/graphics/framebuffer.js';

function png(width, height, rgba) {
  const chunk = (type, data) => {
    const body = Buffer.concat([Buffer.from(type), data]);
    let crc = 0xffffffff;
    for (const byte of body) {
      crc ^= byte;
      for (let bit = 0; bit < 8; bit++) crc = (crc >>> 1) ^ ((crc & 1) ? 0xedb88320 : 0);
    }
    const result = Buffer.alloc(body.length + 8);
    result.writeUInt32BE(data.length); body.copy(result, 4);
    result.writeUInt32BE((crc ^ 0xffffffff) >>> 0, body.length + 4);
    return result;
  };
  const header = Buffer.alloc(13);
  header.writeUInt32BE(width); header.writeUInt32BE(height, 4);
  header[8] = 8; header[9] = 6;
  const rows = Buffer.alloc(height * (1 + width * 4));
  for (let y = 0; y < height; y++) rgba.copy(rows, y * (width * 4 + 1) + 1, y * width * 4, (y + 1) * width * 4);
  return Buffer.concat([Buffer.from([137,80,78,71,13,10,26,10]), chunk('IHDR', header), chunk('IDAT', deflateSync(rows)), chunk('IEND', Buffer.alloc(0))]);
}

const compiled = await WebAssembly.compile(await readFile(new URL('./dist/compiler.wasm', import.meta.url)));
const output = new URL('./docs/images/', import.meta.url);
await mkdir(output, { recursive: true });
for (const [name, nodes, mesh, selected, columns, expected] of [
  ['distributed_mandelbrot', 4, '2x2x1', [0,1,2,3], 2, 1024],
  ['rule110', 2, '2x1x1', [0], 1, 24],
  ['message_hotspot', 16, '4x4x1', [5], 1, 32],
]) {
  const compiler = await CompilerWasm.fromBytes(compiled);
  const image = compiler.compile(await readFile(new URL(`../compiler/examples/${name}.c`, import.meta.url), 'utf8'), nodes, mesh);
  const factory = (await import(`./dist/simulator_${nodes}.js`)).default;
  const sim = await SimulatorWasm.create(factory, { nodes, wasmBinary: await readFile(new URL(`./dist/simulator_${nodes}.wasm`, import.meta.url)) });
  try {
    sim.traceEnabled(false); sim.loadImage(image);
    for (let cycle = 0; cycle < 6000000 && sim.peek(0, 0x300) === 0n; cycle += 1000) sim.step(1000);
    if (sim.peek(0, 0x300) !== 0x100000000n + BigInt(expected)) throw new Error(`${name} did not finish.`);
    const info = debugImage(image), frames = selected.map(node => readFramebuffer(info, sim, node));
    if (frames.some(frame => !frame)) throw new Error(`${name} has no framebuffer.`);
    const scale = 8, tileWidth = frames[0].width, tileHeight = frames[0].height;
    const width = tileWidth * columns * scale, height = tileHeight * Math.ceil(frames.length / columns) * scale;
    const pixels = Buffer.alloc(width * height * 4);
    frames.forEach((frame, index) => {
      for (let y = 0; y < frame.height; y++) for (let x = 0; x < frame.width; x++) {
        const color = frame.pixels.subarray((y * frame.width + x) * 4, (y * frame.width + x + 1) * 4);
        for (let dy = 0; dy < scale; dy++) for (let dx = 0; dx < scale; dx++) {
          const px = ((index % columns) * tileWidth + x) * scale + dx;
          const py = (Math.floor(index / columns) * tileHeight + y) * scale + dy;
          pixels.set(color, (py * width + px) * 4);
        }
      }
    });
    await writeFile(new URL(`${name}.png`, output), png(width, height, pixels));
    console.log(`${name}: rendered nodes ${selected.join(', ')} to ${width}x${height} PNG`);
  } finally { sim.destroy(); }
}
