import { readFile } from "node:fs/promises";
import { CompilerWasm, parseImage } from "../site/runtime.js";

const here = new URL(".", import.meta.url);
const dist = new URL("../dist/", here);
const root = new URL("../../", here);

const compiler = await CompilerWasm.fromBytes(
  await readFile(new URL("compiler.wasm", dist)),
);

const factorialSource = await readFile(
  new URL("compiler/examples/factorial.c", root),
  "utf8",
);
const image = compiler.compile(factorialSource, 2);
const words = parseImage(image, 2);
if (words.length < 1000) {
  throw new Error(`unexpectedly small image: ${words.length} words`);
}

let rejected = false;
try {
  compiler.compile("int main(void) { return missing; }", 2);
} catch (error) {
  rejected = String(error.message || error).includes("undeclared");
}
if (!rejected) throw new Error("compiler did not return a source diagnostic");

console.log(
  `compiler-only passed: image=${words.length} words, ` +
  `diagnostics reject undeclared identifiers`,
);
