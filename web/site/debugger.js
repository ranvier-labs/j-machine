import { NetworkTrace } from './network/trace.js';
import { wordHex, describeWord } from './runtime.js';

export const ipAddress = ip => Number((ip >> 10n) & 0xfffffn);
export const ipPhase = ip => Number((ip >> 9n) & 1n);

export function debugImage(image) {
  const locations = new Map(), lines = new Map(), words = new Map(), globals = [];
  // Code is replicated at the same address on all nodes. Keep node 0 once.
  for (const row of image.split(/\r?\n/)) {
    const match = row.match(/^\s*(0|\*)\s+([0-9a-f]+)\s+([0-9a-f]+)\s*(?:#\s*(.*))?$/i);
    if (!match) continue;
    const address = parseInt(match[2], 16), value = BigInt(`0x${match[3]}`), annotation = match[4] ?? '';
    const source = annotation.match(/\| @source (\d+):(\d+)$/);
    const entry = { address, value, annotation: annotation.replace(/\s*\| @source .*$/, '') };
    if (source) {
      entry.line = Number(source[1]); entry.column = Number(source[2]);
      locations.set(address, entry);
      if (!lines.has(entry.line)) lines.set(entry.line, []);
      lines.get(entry.line).push(address);
    }
    words.set(address, entry);
    const global = annotation.match(/^global (.+)\[(\d+)\]$/);
    if (global) globals.push({ name: `${global[1]}[${global[2]}]`, address });
  }
  // A source breakpoint stops at the start of each contiguous region for its
  // line, including a leading literal load. It does not fire at every opcode.
  const entries = new Map();
  const ordered = [...locations.values()].sort((a, b) => a.address - b.address);
  let previous;
  for (const entry of ordered) {
    if (!previous || previous.line !== entry.line || previous.address + 1 !== entry.address) {
      if (!entries.has(entry.line)) entries.set(entry.line, []);
      entries.get(entry.line).push(entry.address);
    }
    previous = entry;
  }
  return { locations, lines, entries, words, globals };
}

export class DebuggerController {
  constructor(simulator, { onUpdate = () => {}, onStop = () => {}, yieldFrame, batchCycles } = {}) {
    this.simulator = simulator; this.onUpdate = onUpdate; this.onStop = onStop;
    this.yieldFrame = yieldFrame ?? (() => new Promise(resolve => setTimeout(resolve, 0)));
    this.breakpoints = new Map(); this.watchpoints = new Map(); this.nextId = 1;
    this.running = false; this.stopRequested = false; this.selectedNode = 0;
    this.breakOnFault = false; this.image = ''; this.info = debugImage('');
    this.stopReason = { type: 'empty', message: 'Compile a program to begin.' };
    this.maxCycles = 10000000;
    // The full hierarchical mesh is expensive per clock. Keep foreground
    // batches short; headless callers can request larger batches explicitly.
    this.batchCycles = batchCycles ?? (simulator.nodes >= 512 ? 8 : 64);
    if (!Number.isInteger(this.batchCycles) || this.batchCycles < 1 || this.batchCycles > 1024) throw new Error('Batch size must be between 1 and 1024 cycles.');
    this.network = new NetworkTrace(simulator.mesh ?? ({2:'2x1x1',4:'2x2x1',16:'4x4x1',512:'8x8x8'})[simulator.nodes]);
  }

  load(image) {
    if (this.running) throw new Error('Pause execution before loading an image.');
    // loadImage validates before reset; avoid expanding broadcasts twice here.
    const count = this.simulator.loadImage(image);
    const networkBreakpoints = [...this.network.breakpoints.values()];
    this.network.reset(); for (const bp of networkBreakpoints) this.network.addBreakpoint(bp);
    this.image = image; this.info = debugImage(image); this.network.setImage(this.info); this.snapshot = this.simulator.snapshot();
    this.initialResult = this.simulator.peek(0, 0x300);
    this.completed = false; this.suppressed = null;
    for (const watch of this.watchpoints.values()) watch.value = this.simulator.peek(watch.node, watch.address);
    this.stop({ type: 'loaded', message: 'Image loaded. Ready at cycle 0.' });
    return count;
  }

  addBreakpoint({ node = null, address, line, phase = 0 }) {
    if (line !== undefined && (!Number.isInteger(line) || line < 1)) throw new Error('Invalid source line.');
    if (address !== undefined && (!Number.isInteger(address) || address < 0 || address > 0xfffff)) throw new Error('Invalid breakpoint address.');
    if (line === undefined && address === undefined) throw new Error('A breakpoint needs a source line or address.');
    this.checkNode(node, true);
    const id = this.nextId++;
    this.breakpoints.set(id, { id, node, address, line, phase, enabled: true });
    return id;
  }

  checkNode(node, all = false) {
    if (node === null && all) return;
    if (!Number.isInteger(node) || node < 0 || node >= this.simulator.nodes) throw new Error('Node is outside the active machine.');
  }

  addWatchpoint(node, address) {
    this.checkNode(node);
    if (!Number.isInteger(address) || address < 0 || address > 0xfffff) throw new Error('Invalid watch address.');
    const id = this.nextId++;
    this.watchpoints.set(id, { id, node, address, value: this.simulator.peek(node, address) });
    return id;
  }

  sourceLocation(node = this.selectedNode) {
    const state = this.snapshot?.nodes[node];
    return state?.atFetch ? this.info.locations.get(ipAddress(state.ip)) : undefined;
  }

  breakpointAt(snapshot) {
    for (const node of snapshot.nodes) {
      if (!node.atFetch) continue;
      const key = `${node.index}:${node.ip}:${node.retired}`;
      if (this.suppressed === key) continue;
      for (const bp of this.breakpoints.values()) {
        if (!bp.enabled || (bp.node !== null && bp.node !== node.index) || bp.phase !== ipPhase(node.ip)) continue;
        const addresses = bp.line === undefined ? [bp.address] : this.info.entries.get(bp.line) ?? [];
        if (addresses.includes(ipAddress(node.ip))) return { type: 'breakpoint', id: bp.id, node: node.index, key,
          message: `Breakpoint · node ${node.index} · ${bp.line ? `line ${bp.line}` : `0x${ipAddress(node.ip).toString(16).padStart(5, '0')}`}` };
      }
    }
    return null;
  }

  checkStops(previous) {
    const snapshot = this.snapshot;
    const fatal = snapshot.nodes.find(node => node.catastrophe);
    if (fatal) return { type: 'fault', node: fatal.index, message: `Catastrophe · node ${fatal.index}` };
    if (this.breakOnFault) {
      const fault = snapshot.nodes.find((node, i) => (node.faultMode && !previous.nodes[i].faultMode)
        || node.fault !== previous.nodes[i].fault);
      if (fault) return { type: 'fault', node: fault.index, message: `Fault ${fault.fault} · node ${fault.index}` };
    }
    for (const watch of this.watchpoints.values()) {
      const value = this.simulator.peek(watch.node, watch.address);
      if (value !== watch.value) {
        const before = watch.value; watch.value = value;
        return { type: 'watchpoint', node: watch.node, id: watch.id,
          message: `Watch · node ${watch.node} · 0x${watch.address.toString(16).padStart(5, '0')} · ${describeWord(before)} → ${describeWord(value)}` };
      }
    }
    const result = this.simulator.peek(0, 0x300);
    if (!this.completed && result !== this.initialResult) {
      this.completed = true;
      return { type: 'result', node: 0, message: `Main returned ${describeWord(result)}` };
    }
    return this.breakpointAt(snapshot);
  }

  pause() { this.stopRequested = true; }

  stop(reason) {
    this.running = false; this.stopReason = reason;
    if (reason.node !== undefined) this.selectedNode = reason.node;
    this.onUpdate(this.snapshot); this.onStop(reason);
    return reason;
  }

  async execute(mode = 'continue', cycles = 1) {
    if (this.running || !this.image) return;
    this.checkNode(this.selectedNode);
    if (!Number.isInteger(cycles) || cycles < 1) throw new Error('Cycle count must be positive.');
    if (['source', 'continue'].includes(mode) && this.snapshot.nodes.some(node => node.atFetch === undefined)) {
      throw new Error('Rebuild simulator.wasm for source debugging (snapshot ABI 2).');
    }
    this.running = true; this.stopRequested = false;
    this.suppressed = this.stopReason.type === 'breakpoint' ? this.stopReason.key : null;
    const first = this.snapshot;
    const startLine = this.sourceLocation()?.line;
    let elapsed = 0;
    const limit = mode === 'cycles' ? cycles : this.maxCycles;
    try {
      const initialBreakpoint = this.breakpointAt(this.snapshot);
      if (initialBreakpoint && mode === 'continue') return this.stop(initialBreakpoint);
      while (elapsed < limit) {
        const traceBatch = this.simulator.configureNetworkBreaks?.(this.network.breakpoints.values());
        // Bound work by wall time, including on a 512-node machine, so Pause
        // remains responsive. Every RTL cycle is checked for stop conditions.
        const until = performance.now() + 12;
        do {
          if (this.stopRequested) return this.stop({ type: 'paused', message: 'Execution paused.' });
          const previous = this.snapshot;
          const batch = mode === 'continue' && !this.breakpoints.size && !this.watchpoints.size
            && !this.breakOnFault && (traceBatch || ![...this.network.breakpoints.values()].some(bp => bp.enabled));
          this.snapshot = batch && this.simulator.runBatch ? this.simulator.runBatch(Math.min(this.batchCycles,limit-elapsed)) : this.simulator.step(1);
          elapsed += Number(this.snapshot.cycle - previous.cycle);
          const capture = this.simulator.drainTrace?.();
          const networkStop = capture ? this.network.consume(capture.events, capture.dropped) : null;
          this.network.advance(this.snapshot.cycle);
          const stop = networkStop ?? this.checkStops(previous);
          if (networkStop) { this.network.selectedPacket = networkStop.packet; this.network.selectedEvent = networkStop.event; }
          if (stop) return this.stop(stop);
          const node = this.snapshot.nodes[this.selectedNode];
          if (mode === 'instruction' && node.retired > first.nodes[this.selectedNode].retired) {
            return this.stop({ type: 'instruction', message: `Instruction retired · node ${this.selectedNode}` });
          }
          if (mode === 'source' && this.sourceLocation()?.line !== undefined
            && this.sourceLocation().line !== startLine) {
            return this.stop({ type: 'source', message: `Source step · node ${this.selectedNode} · line ${this.sourceLocation().line}` });
          }
        } while (elapsed < limit && performance.now() < until);
        this.onUpdate(this.snapshot);
        if (elapsed < limit) await this.yieldFrame();
      }
      return this.stop({ type: mode === 'cycles' ? 'cycles' : 'limit',
        message: mode === 'cycles' ? `Advanced ${elapsed} cycle${elapsed === 1 ? '' : 's'}.`
          : `Paused at the ${limit.toLocaleString()}-cycle limit.` });
    } catch (error) {
      return this.stop({ type: 'error', message: String(error.message ?? error) });
    }
  }
}
