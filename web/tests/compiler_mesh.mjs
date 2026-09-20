import { readFile } from "node:fs/promises";
import { CompilerWasm, parseImage } from "../site/runtime.js";

const here = new URL(".", import.meta.url);
const dist = new URL("../dist/", here);
const root = new URL("../../", here);

const compiler = await CompilerWasm.fromBytes(
  await readFile(new URL("compiler.wasm", dist)),
);

// Exercise the 3-argument jmc_compile ABI directly as well as its JavaScript
// wrapper: mesh bytes go to jmc_mesh_ptr and
// mesh_len is the third argument (mesh_len 0 selects the default topology).
const exports = compiler.exports;
for (const name of ["jmc_mesh_ptr", "jmc_mesh_capacity"]) {
  if (typeof exports[name] !== "function") {
    throw new Error(`compiler.wasm is missing ${name}`);
  }
}
const meshCapacity = exports.jmc_mesh_capacity() >>> 0;
if (meshCapacity !== 256) {
  throw new Error(`expected a 256-byte mesh buffer, got ${meshCapacity}`);
}

function compileWithMesh(source, nodes, mesh) {
  const encoded = new TextEncoder().encode(source);
  const sourceCapacity = exports.jmc_source_capacity() >>> 0;
  if (encoded.length > sourceCapacity) {
    throw new Error(`source is ${encoded.length} bytes; limit is ${sourceCapacity}`);
  }
  new Uint8Array(compiler.memory.buffer, exports.jmc_source_ptr() >>> 0, encoded.length)
    .set(encoded);
  const meshBytes = new TextEncoder().encode(mesh);
  if (meshBytes.length > meshCapacity) {
    throw new Error(`mesh is ${meshBytes.length} bytes; limit is ${meshCapacity}`);
  }
  new Uint8Array(compiler.memory.buffer, exports.jmc_mesh_ptr() >>> 0, meshBytes.length)
    .set(meshBytes);
  exports.jmc_compile(encoded.length, nodes >>> 0, meshBytes.length >>> 0);
  const status = exports.jmc_output_status() >>> 0;
  const outputPtr = exports.jmc_output_ptr() >>> 0;
  const outputLength = exports.jmc_output_len() >>> 0;
  if (outputPtr + outputLength > compiler.memory.buffer.byteLength) {
    throw new Error("compiler returned an out-of-bounds output slice");
  }
  const output = new TextDecoder().decode(
    new Uint8Array(compiler.memory.buffer, outputPtr, outputLength),
  );
  if (status !== 0) throw new Error(output || "compiler failed");
  return output;
}

function expectDiagnostic(source, nodes, mesh, fragment) {
  try {
    compileWithMesh(source, nodes, mesh);
  } catch (error) {
    if (String(error.message || error).includes(fragment)) return;
    throw new Error(`diagnostic did not mention "${fragment}": ${error.message || error}`);
  }
  throw new Error(`compile(${nodes} nodes, mesh "${mesh}") unexpectedly succeeded`);
}

// Word counts recorded from native jmc with the same options:
//   jmc factorial.c -o ... --nodes 2                     -> 2790
//   jmc factorial.c -o ... --nodes 4 --mesh 2x2x1        -> 5580
//   jmc factorial.c -o ... --nodes 5                     -> 6975
//   jmc mesh512.c  -o ... --nodes 512 --mesh 8x8x8       -> 1097216
const factorialSource = await readFile(
  new URL("compiler/examples/factorial.c", root),
  "utf8",
);
const mesh512Source = await readFile(
  new URL("compiler/examples/mesh512.c", root),
  "utf8",
);

const defaultTwo = compileWithMesh(factorialSource, 2, "");
const defaultTwoWords = parseImage(defaultTwo, 2);
if (defaultTwoWords.length !== 2790) {
  throw new Error(`2-node default-topology image: ${defaultTwoWords.length} words, expected 2790`);
}

const legacyTwo = compiler.compile(factorialSource, 2);
if (legacyTwo !== defaultTwo) {
  throw new Error("2-argument jmc_compile call no longer matches mesh_len 0");
}

const four = compileWithMesh(factorialSource, 4, "2x2x1");
const fourWords = parseImage(four, 4);
if (fourWords.length !== 5580) {
  throw new Error(`4-node 2x2x1 image: ${fourWords.length} words, expected 5580`);
}
if (!fourWords.some((word) => word.node === 3)) {
  throw new Error("4-node 2x2x1 image has no words for node 3");
}

const five = compileWithMesh(factorialSource, 5, "");
const fiveWords = parseImage(five, 5);
if (fiveWords.length !== 6975) {
  throw new Error(`5-node default-topology image: ${fiveWords.length} words, expected 6975`);
}

const mesh512 = compileWithMesh(mesh512Source, 512, "8x8x8");
const mesh512Words = parseImage(mesh512, 512);
if (mesh512Words.length !== 1097216) {
  throw new Error(`512-node 8x8x8 image: ${mesh512Words.length} words, expected 1097216`);
}
if (!mesh512Words.some((word) => word.node === 511)) {
  throw new Error("512-node 8x8x8 image has no words for node 511");
}

expectDiagnostic(factorialSource, 4, "2x2", "invalid mesh topology");
expectDiagnostic(factorialSource, 4, "banana", "invalid mesh topology");
expectDiagnostic(factorialSource, 5, "2x2x1", "does not contain 5 nodes");
expectDiagnostic(factorialSource, 33, "", "require an explicit --mesh");

console.log(
  `compiler-mesh passed: 2-node=${defaultTwoWords.length} words, ` +
  `4-node/2x2x1=${fourWords.length} words, 5-node=${fiveWords.length} words, ` +
  `512-node/8x8x8=${mesh512Words.length} words, ` +
  `invalid meshes diagnosed, legacy 2-argument call unchanged`,
);
