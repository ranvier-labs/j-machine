// Standalone simulator.wasm acceptance test: proves the Verilator/Emscripten
// simulator half of the web workbench without involving compiler.wasm.
//
// The image is a checked-in fixture compiled ahead of time by the native jmc
// (build it with `bazel build //compiler:jmc`, or use the Lake build output
// compiler/.lake/build/bin/jmc directly):
//
//   bazel-bin/compiler/jmc compiler/examples/factorial.c \
//     -o web/tests/fixtures/factorial_2node.image --nodes 2
//
// Run from the repository root:
//
//   node web/tests/simulator_only.mjs

import { readFile } from "node:fs/promises";
import { fileURLToPath } from "node:url";
import createSimulatorModule from "../dist/simulator.js";
import { SimulatorWasm, describeWord } from "../site/runtime.js";

const here = new URL(".", import.meta.url);
const dist = new URL("../dist/", here);

const simulator = await SimulatorWasm.create(createSimulatorModule, {
  wasmBinary: await readFile(new URL("simulator.wasm", dist)),
  locateFile: (path) => fileURLToPath(new URL(path, dist)),
});

const image = await readFile(
  new URL("fixtures/factorial_2node.image", here),
  "utf8",
);
const loaded = simulator.loadImage(image);
if (loaded < 1000) throw new Error(`unexpectedly small image: ${loaded} words`);

let result = simulator.peek(0, 0x300);
for (let elapsed = 0; elapsed < 100000 && result === 0n; elapsed += 1000) {
  simulator.step(1000);
  result = simulator.peek(0, 0x300);
}

const expected = 0x1000002d0n;
if (result !== expected) {
  throw new Error(`factorial result ${describeWord(result)}; expected INT(720)`);
}

const snapshot = simulator.snapshot();
if (snapshot.nodes.some((node) => node.catastrophe)) {
  throw new Error("simulator entered catastrophe state");
}
if (snapshot.nodes[0].retired === 0n) {
  throw new Error("node 0 retired no instructions");
}

console.log(
  `simulator-only passed: image=${loaded} cycle=${snapshot.cycle} ` +
  `retired=${snapshot.nodes[0].retired} result=${describeWord(result)}`,
);

simulator.destroy();
