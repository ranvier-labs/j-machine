// Per-variant simulator.wasm acceptance test: verifies every simulator
// variant listed in web/dist/variants.json standalone, without runtime.js
// or compiler.wasm. Each image is compiled on the fly by the native jmc
// (compiler/.lake/build/bin/jmc) with a --mesh topology matching the
// variant's geometry, then run until node 0's main-result mailbox at
// 0x300 holds INT(720).
//
// Run from the repository root:
//
//   node web/tests/simulator_variants.mjs

import { execFileSync } from "node:child_process";
import { mkdtemp, readFile, rm } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { fileURLToPath, pathToFileURL } from "node:url";

const here = new URL(".", import.meta.url);
const dist = new URL("../dist/", here);
const root = new URL("../../", here);
const distPath = fileURLToPath(dist);
const jmc = fileURLToPath(new URL("compiler/.lake/build/bin/jmc", root));
const factorialSource = fileURLToPath(
  new URL("compiler/examples/factorial.c", root),
);

// Mesh geometry per variant, mirroring web/build_simulator.sh.
const MESH_DIMS = new Map([
  [2, "2x1x1"],
  [4, "2x2x1"],
  [16, "4x4x1"],
  [512, "8x8x8"],
]);

const SNAPSHOT_MAGIC = 0x4a4d5331;
const SNAPSHOT_HEADER_WORDS = 4;
const SNAPSHOT_NODE_WORDS = 32;
const RESULT_ADDRESS = 0x300;
const EXPECTED_RESULT = 0x1000002d0n; // INT(720)

function parseImage(imageText, physicalNodes) {
  const words = [];
  for (const [index, original] of imageText.split(/\r?\n/).entries()) {
    const line = original.split("#", 1)[0].trim();
    if (!line) continue;
    const fields = line.split(/\s+/);
    if (fields.length !== 3) {
      throw new Error(`image line ${index + 1}: expected NODE ADDRESS WORD`);
    }
    const [nodeText, addressText, valueText] = fields;
    const address = Number.parseInt(addressText, 16);
    const value = BigInt(`0x${valueText}`);
    const nodes = nodeText === "*"
      ? Array.from({ length: physicalNodes }, (_, node) => node)
      : [Number.parseInt(nodeText, 10)];
    for (const node of nodes) {
      if (!Number.isInteger(node) || node < 0 || node >= physicalNodes) {
        throw new Error(`image line ${index + 1}: node out of range`);
      }
      words.push({ node, address, value });
    }
  }
  return words;
}

const { variants } = JSON.parse(
  await readFile(new URL("variants.json", dist), "utf8"),
);
if (!Array.isArray(variants) || variants.length === 0) {
  throw new Error("dist/variants.json lists no simulator variants");
}

const scratch = await mkdtemp(join(tmpdir(), "jmc-variant-images-"));
try {
  for (const variant of variants) {
    const nodes = variant.nodes;
    const mesh = MESH_DIMS.get(nodes);
    if (!mesh) throw new Error(`no mesh geometry known for ${nodes} nodes`);

    const imagePath = join(scratch, `factorial_${nodes}.image`);
    execFileSync(jmc, [
      factorialSource,
      "-o", imagePath,
      "--nodes", String(nodes),
      "--mesh", mesh,
    ]);
    const words = parseImage(await readFile(imagePath, "utf8"), nodes);

    const createModule = (
      await import(pathToFileURL(join(distPath, variant.js)).href)
    ).default;
    const module = await createModule({
      wasmBinary: await readFile(new URL(variant.wasm, dist)),
      locateFile: (path) => fileURLToPath(new URL(path, dist)),
    });
    for (const name of [
      "_sim_init",
      "_sim_destroy",
      "_sim_reset",
      "_sim_write_word",
      "_sim_finish_load",
      "_sim_set_running",
      "_sim_step",
      "_sim_snapshot_ptr",
      "_sim_snapshot_words",
      "_sim_peek",
    ]) {
      if (typeof module[name] !== "function") {
        throw new Error(`${variant.js} is missing ${name}`);
      }
    }

    const peek = (node, address) => {
      const ptr = module._sim_peek(node >>> 0, address >>> 0) >>> 2;
      return (BigInt(module.HEAPU32[ptr + 1]) << 32n)
        | BigInt(module.HEAPU32[ptr]);
    };

    module._sim_init();
    module._sim_reset();
    for (const word of words) {
      const low = Number(word.value & 0xffffffffn) >>> 0;
      const high = Number((word.value >> 32n) & 0xfn) >>> 0;
      if (module._sim_write_word(word.node, word.address, low, high) !== 0) {
        throw new Error(
          `${nodes}-node variant rejected node ${word.node} ` +
          `address ${word.address.toString(16)}`,
        );
      }
    }
    module._sim_finish_load();

    let result = peek(0, RESULT_ADDRESS);
    let elapsed = 0;
    while (elapsed < 200000 && result === 0n) {
      module._sim_step(1000);
      elapsed += 1000;
      result = peek(0, RESULT_ADDRESS);
    }
    if (result !== EXPECTED_RESULT) {
      throw new Error(
        `${nodes}-node variant: node 0 result 0x${result.toString(16)}; ` +
        "expected INT(720)",
      );
    }

    const snapshotWords = module._sim_snapshot_words() >>> 0;
    const expectedWords = SNAPSHOT_HEADER_WORDS + nodes * SNAPSHOT_NODE_WORDS;
    if (snapshotWords !== expectedWords) {
      throw new Error(
        `${nodes}-node variant: snapshot has ${snapshotWords} words; ` +
        `expected ${expectedWords}`,
      );
    }
    const ptr = module._sim_snapshot_ptr() >>> 2;
    const snapshot = module.HEAPU32.subarray(ptr, ptr + snapshotWords);
    if (snapshot[0] !== SNAPSHOT_MAGIC || snapshot[1] !== 2) {
      throw new Error(`${nodes}-node variant: invalid snapshot ABI`);
    }
    for (let node = 0; node < nodes; node += 1) {
      const offset = SNAPSHOT_HEADER_WORDS + node * SNAPSHOT_NODE_WORDS;
      if (snapshot[offset + 7] !== snapshot[offset + 16] || snapshot[offset + 8] !== snapshot[offset + 17]) {
        throw new Error(`${nodes}-node variant: packed R0 does not match the architectural R0`);
      }
      if (snapshot[offset + 1] !== 0) {
        throw new Error(
          `${nodes}-node variant: node ${node} catastrophe ` +
          `(fault 0x${snapshot[offset + 2].toString(16)})`,
        );
      }
    }
    const retired = (BigInt(snapshot[SNAPSHOT_HEADER_WORDS + 4]) << 32n)
      | BigInt(snapshot[SNAPSHOT_HEADER_WORDS + 3]);
    if (retired === 0n) {
      throw new Error(`${nodes}-node variant: node 0 retired no instructions`);
    }

    module._sim_destroy();
    console.log(
      `variant ${nodes} (${mesh}) passed: image=${words.length} ` +
      `cycle=${elapsed} retired=${retired} result=INT(720)`,
    );
  }
} finally {
  await rm(scratch, { recursive: true, force: true });
}

console.log(`all ${variants.length} simulator variants passed`);
