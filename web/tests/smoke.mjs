import { readFile } from "node:fs/promises";
import { fileURLToPath } from "node:url";
import createSimulatorModule from "../dist/simulator.js";
import { CompilerWasm, SimulatorWasm, describeWord } from "../dist/runtime.js";

const here = new URL(".", import.meta.url);
const dist = new URL("../dist/", here);
const root = new URL("../../", here);

const compiler = await CompilerWasm.fromBytes(
  await readFile(new URL("compiler.wasm", dist)),
);

const simulator = await SimulatorWasm.create(createSimulatorModule, {
  wasmBinary: await readFile(new URL("simulator.wasm", dist)),
  locateFile: (path) => fileURLToPath(new URL(path, dist)),
});

const factorialSource = await readFile(
  new URL("compiler/examples/factorial.c", root),
  "utf8",
);
const image = compiler.compile(factorialSource, 2);
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

let rejected = false;
try {
  compiler.compile("int main(void) { return missing; }", 2);
} catch (error) {
  rejected = String(error.message || error).includes("undeclared");
}
if (!rejected) throw new Error("compiler did not return a source diagnostic");

console.log(
  `web smoke passed: image=${loaded} cycle=${snapshot.cycle} ` +
  `retired=${snapshot.nodes[0].retired} result=${describeWord(result)}`,
);

simulator.destroy();
