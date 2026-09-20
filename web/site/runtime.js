const SNAPSHOT_MAGIC = 0x4a4d5331;
const SNAPSHOT_HEADER_WORDS = 4;

function u64(low, high) {
  return (BigInt(high >>> 0) << 32n) | BigInt(low >>> 0);
}

function makeWasiImports(getMemory) {
  const dataView = () => new DataView(getMemory().buffer);
  const bytes = () => new Uint8Array(getMemory().buffer);
  const ok = () => 0;
  const badFile = () => 8;

  if (typeof WebAssembly.Tag !== "function") {
    throw new Error("This browser does not support WebAssembly exception tags.");
  }

  return {
    env: {
      __cpp_exception: new WebAssembly.Tag({ parameters: ["i32"] }),
    },
    wasi_snapshot_preview1: {
      environ_get: ok,
      environ_sizes_get(countPtr, sizePtr) {
        dataView().setUint32(countPtr, 0, true);
        dataView().setUint32(sizePtr, 0, true);
        return 0;
      },
      fd_close: ok,
      fd_fdstat_get: badFile,
      fd_prestat_get: badFile,
      fd_prestat_dir_name: badFile,
      fd_read: badFile,
      fd_seek: badFile,
      fd_write(fd, iovs, count, writtenPtr) {
        const view = dataView();
        let written = 0;
        for (let index = 0; index < count; index += 1) {
          const ptr = view.getUint32(iovs + index * 8, true);
          const length = view.getUint32(iovs + index * 8 + 4, true);
          if ((fd === 1 || fd === 2) && length > 0) {
            const message = new TextDecoder().decode(bytes().subarray(ptr, ptr + length));
            if (message.trim()) console.debug(message.trim());
          }
          written += length;
        }
        view.setUint32(writtenPtr, written, true);
        return 0;
      },
      proc_exit(code) {
        throw new Error(`WASI proc_exit(${code})`);
      },
      random_get(ptr, length) {
        crypto.getRandomValues(bytes().subarray(ptr, ptr + length));
        return 0;
      },
      clock_time_get(_clock, _precision, resultPtr) {
        dataView().setBigUint64(resultPtr, BigInt(Date.now()) * 1000000n, true);
        return 0;
      },
    },
  };
}

export class CompilerWasm {
  constructor(instance, memory) {
    this.instance = instance;
    this.exports = instance.exports;
    this.memory = memory;
  }

  static async fromBytes(moduleBytes) {
    let memory = null;
    const imports = makeWasiImports(() => memory);
    const result = await WebAssembly.instantiate(moduleBytes, imports);
    const instance = result instanceof WebAssembly.Instance ? result : result.instance;
    memory = instance.exports.memory;
    if (!(memory instanceof WebAssembly.Memory)) {
      throw new Error("compiler.wasm does not export linear memory");
    }
    instance.exports._initialize?.();
    for (const name of [
      "jmc_compile",
      "jmc_source_ptr",
      "jmc_source_capacity",
      "jmc_output_status",
      "jmc_output_ptr",
      "jmc_output_len",
    ]) {
      if (typeof instance.exports[name] !== "function") {
        throw new Error(`compiler.wasm is missing ${name}`);
      }
    }
    return new CompilerWasm(instance, memory);
  }

  static async fromUrl(url) {
    const response = await fetch(url);
    if (!response.ok) throw new Error(`failed to fetch compiler.wasm (${response.status})`);
    return CompilerWasm.fromBytes(await response.arrayBuffer());
  }

  compile(source, nodes = 2, mesh = "") {
    const encoded = new TextEncoder().encode(source);
    const capacity = this.exports.jmc_source_capacity() >>> 0;
    if (encoded.length > capacity) {
      throw new Error(`source is ${encoded.length} bytes; compiler limit is ${capacity}`);
    }
    const sourcePtr = this.exports.jmc_source_ptr() >>> 0;
    new Uint8Array(this.memory.buffer, sourcePtr, encoded.length).set(encoded);
    const meshLength = this.writeMesh(mesh);
    if (meshLength > 0) {
      this.exports.jmc_compile(encoded.length, nodes >>> 0, meshLength);
    } else {
      this.exports.jmc_compile(encoded.length, nodes >>> 0);
    }
    const status = this.exports.jmc_output_status() >>> 0;
    const outputPtr = this.exports.jmc_output_ptr() >>> 0;
    const outputLength = this.exports.jmc_output_len() >>> 0;
    if (outputPtr + outputLength > this.memory.buffer.byteLength) {
      throw new Error("compiler returned an out-of-bounds output slice");
    }
    const output = new TextDecoder().decode(
      new Uint8Array(this.memory.buffer, outputPtr, outputLength),
    );
    if (status !== 0) throw Object.assign(new Error(output || "compiler failed"), { name: 'JmcCompileError' });
    return output;
  }

  // Copies the UTF-8 "XxYxZ" topology into the compiler's fixed mesh buffer
  // and returns its byte length for jmc_compile's mesh_len parameter. Returns
  // 0 when no mesh was requested or when the loaded compiler.wasm predates
  // the mesh ABI (no jmc_mesh_ptr/jmc_mesh_capacity exports); compile then
  // uses the two-argument call, which both ABIs treat as default topology.
  writeMesh(mesh) {
    if (typeof mesh !== "string" || mesh.length === 0) return 0;
    const meshPtr = this.exports.jmc_mesh_ptr;
    const meshCapacity = this.exports.jmc_mesh_capacity;
    if (typeof meshPtr !== "function" || typeof meshCapacity !== "function") return 0;
    const encoded = new TextEncoder().encode(mesh);
    const capacity = meshCapacity() >>> 0;
    if (encoded.length > capacity) {
      throw new Error(`mesh is ${encoded.length} bytes; compiler limit is ${capacity}`);
    }
    new Uint8Array(this.memory.buffer, meshPtr() >>> 0, encoded.length).set(encoded);
    return encoded.length;
  }
}

function parseImageRecords(imageText, physicalNodes) {
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
    const node = nodeText === "*" ? null : Number.parseInt(nodeText, 10);
    if (!Number.isInteger(address) || address < 0 || address > 0xfffff) {
      throw new Error(`image line ${index + 1}: address out of range`);
    }
    if (value < 0n || value > 0xfffffffffn) {
      throw new Error(`image line ${index + 1}: word out of range`);
    }
    if (node !== null && (!Number.isInteger(node) || node < 0 || node >= physicalNodes)) {
      throw new Error(`image line ${index + 1}: node out of range`);
    }
    words.push({ node, address, value });
  }
  return words;
}

export function parseImage(imageText, physicalNodes = 2) {
  return parseImageRecords(imageText, physicalNodes).flatMap(word => word.node === null
    ? Array.from({ length: physicalNodes }, (_, node) => ({ ...word, node }))
    : [word]);
}

// Downloads a simulator binary while reporting received bytes, so the desktop
// can distinguish a slow network from a slow compile. Falls back to a plain
// fetch when the response body cannot be streamed.
export async function fetchWithProgress(url, onProgress = () => {}) {
  const response = await fetch(url);
  if (!response.ok) throw new Error(`failed to fetch ${url.pathname ?? url} (${response.status})`);
  const total = Number(response.headers.get("Content-Length")) || null;
  onProgress({ stage: "fetch", loaded: 0, total });
  if (!response.body?.getReader) return new Uint8Array(await response.arrayBuffer());
  const reader = response.body.getReader(), chunks = [];
  let loaded = 0, reported = 0;
  for (;;) {
    const { done, value } = await reader.read();
    if (done) break;
    chunks.push(value); loaded += value.byteLength;
    if (loaded - reported >= 1 << 20 || loaded === total) { reported = loaded; onProgress({ stage: "fetch", loaded, total }); }
  }
  const bytes = new Uint8Array(loaded);
  let offset = 0;
  for (const chunk of chunks) { bytes.set(chunk, offset); offset += chunk.byteLength; }
  onProgress({ stage: "fetch", loaded, total: total ?? loaded });
  return bytes;
}

export class SimulatorWasm {
  constructor(module, nodes = 2) {
    this.module = module;
    this.nodes = nodes;
    this.module._sim_init();
  }

  // `options` is forwarded to the Emscripten factory, except `nodes`, which
  // only describes how many per-node records the snapshot ABI carries.
  static async create(factory, options = {}) {
    const { nodes = 2, ...moduleOptions } = options;
    const module = await factory(moduleOptions);
    for (const name of [
      "_sim_init",
      "_sim_reset",
      "_sim_write_word",
      "_sim_finish_load",
      "_sim_step",
      "_sim_snapshot_ptr",
      "_sim_snapshot_words",
      "_sim_peek",
    ]) {
      if (typeof module[name] !== "function") {
        throw new Error(`simulator module is missing ${name}`);
      }
    }
    return new SimulatorWasm(module, nodes);
  }

  // Loads a per-node-count build listed in variants.json: dynamically imports
  // the variant glue (`simulator_N.js`) next to `baseUrl` and points the
  // glue's locateFile at the variant's wasm (`simulator_N.wasm`).
  static async fromVariant(variant, baseUrl, options = {}) {
    const { onProgress = () => {}, ...moduleOptions } = options;
    const moduleUrl = new URL(variant.js, baseUrl);
    const wasmUrl = variant.wasm ? new URL(variant.wasm, baseUrl) : null;
    const [{ default: factory }, wasmBinary] = await Promise.all([
      import(moduleUrl.href),
      wasmUrl ? fetchWithProgress(wasmUrl, onProgress) : undefined,
    ]);
    onProgress({ stage: "instantiate" });
    return SimulatorWasm.create(factory, {
      locateFile: (path) => new URL(
        path.endsWith(".wasm") && variant.wasm ? variant.wasm : path,
        baseUrl,
      ).href,
      ...(wasmBinary ? { wasmBinary } : {}),
      ...moduleOptions,
      nodes: variant.nodes,
    });
  }

  loadImage(imageText) {
    // Validate the complete image before reset. Keep broadcast records compact
    // instead of allocating a JavaScript object for every replicated word.
    const words = parseImageRecords(imageText, this.nodes);
    this.module._sim_reset();
    let count = 0;
    for (const word of words) {
      const low = Number(word.value & 0xffffffffn) >>> 0;
      const high = Number((word.value >> 32n) & 0xfn) >>> 0;
      const first = word.node ?? 0, end = word.node === null ? this.nodes : word.node + 1;
      for (let node = first; node < end; node++) {
        const status = this.module._sim_write_word(node, word.address, low, high);
        if (status !== 0) {
          throw new Error(`simulator rejected node ${node} address ${word.address.toString(16)}`);
        }
        count++;
      }
    }
    this.module._sim_finish_load();
    return count;
  }

  step(cycles = 1) {
    this.module._sim_step(cycles >>> 0);
    return this.snapshot();
  }

  configureNetworkBreaks(breakpoints) {
    if(!this.module._sim_trace_break_mask)return false;
    const masks={inject:1,deliver:2,link:4,handler:8,stall:16};
    this.module._sim_trace_break_mask([...breakpoints].filter(b=>b.enabled).reduce((mask,b)=>mask|(masks[b.type]??0),0));return true;
  }
  runBatch(cycles = 64) {
    if (!this.module._sim_run) return this.step(1);
    this.module._sim_run(cycles); return this.snapshot();
  }

  traceEnabled(enabled) { this.module._sim_trace_enable?.(Number(enabled)); }
  drainTrace() {
    const m = this.module;
    if (!m._sim_trace_count) return { events: [], dropped: 0, supported: false };
    const count = m._sim_trace_count() >>> 0, dropped = m._sim_trace_dropped() >>> 0;
    const start = m._sim_trace_ptr() >>> 2, words = m.HEAPU32;
    const events = [];
    for (let i = 0; i < count; i++) {
      const p = start + i * 12;
      events.push({ cycle: words[p] + words[p + 1] * 0x100000000, kind: words[p + 2], node: words[p + 3],
        port: words[p + 4], priority: words[p + 5], aux: words[p + 6], value: words[p + 7] + words[p + 8] * 0x100000000,
        flags: words[p + 9], ip: words[p + 10], extra: words[p + 11] });
    }
    m._sim_trace_clear(); return { events, dropped, supported: true };
  }

  snapshot() {
    const ptr = this.module._sim_snapshot_ptr() >>> 2;
    const length = this.module._sim_snapshot_words() >>> 0;
    const words = this.module.HEAPU32.subarray(ptr, ptr + length);
    const nodeWords = words[1] === 2 ? 32 : 16;
    const expected = SNAPSHOT_HEADER_WORDS + this.nodes * nodeWords;
    if (words[0] !== SNAPSHOT_MAGIC || ![1, 2].includes(words[1]) || length < expected) {
      throw new Error("invalid simulator snapshot ABI");
    }
    const nodes = [];
    for (let node = 0; node < this.nodes; node += 1) {
      const offset = SNAPSHOT_HEADER_WORDS + node * nodeWords;
      nodes.push({
        index: node,
        number: words[offset],
        catastrophe: Boolean(words[offset + 1]),
        fault: words[offset + 2],
        retired: u64(words[offset + 3], words[offset + 4]),
        ip: u64(words[offset + 5], words[offset + 6]),
        r0: u64(words[offset + 7], words[offset + 8]),
        background: Boolean(words[offset + 9] & 1),
        atFetch: words[1] === 2 ? Boolean(words[offset + 9] & 2) : undefined,
        registers: words[1] === 2 ? Array.from({ length: 8 }, (_, reg) =>
          u64(words[offset + 16 + reg * 2], words[offset + 17 + reg * 2])) : null,
        priority: words[offset + 10],
        interruptMask: Boolean(words[offset + 11]),
        faultMode: Boolean(words[offset + 12]),
        unchecked: Boolean(words[offset + 13]),
        queuePending: words[offset + 14],
        queueFull: words[offset + 15],
      });
    }
    return { cycle: u64(words[2], words[3]), nodes };
  }

  peek(node, address) {
    const ptr = this.module._sim_peek(node >>> 0, address >>> 0) >>> 2;
    return u64(this.module.HEAPU32[ptr], this.module.HEAPU32[ptr + 1]);
  }

  destroy() {
    this.module._sim_destroy();
  }
}

export function wordHex(value) {
  return `0x${value.toString(16).padStart(9, "0")}`;
}

export function describeWord(value) {
  const tags = ["SYM", "INT", "BOOL", "ADDR", "IP", "MSG", "CFUT", "FUT",
    "TAG8", "TAG9", "TAGA", "TAGB", "INST0", "INST1", "INST2", "INST3"];
  const tag = Number((value >> 32n) & 0xfn);
  const data = Number(value & 0xffffffffn) >>> 0;
  return `${tags[tag] ?? `TAG${tag}`}(${data})`;
}
