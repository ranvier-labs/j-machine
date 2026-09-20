import { dimensions, encodedNode, neighbor, OPPOSITE, PORTS } from './geometry.js';

export const EVENT_NAMES = { 1: 'accept', 2: 'transfer', 3: 'consume header', 4: 'stall', 5: 'producer wait',
  6: 'send word', 7: 'queue admission', 8: 'handler dispatch', 9: 'fault operand', 10: 'future write', 11: 'queue state', 12: 'suspend' };
export const WAIT_REASONS = { 1: 'Downstream backpressure', 2: 'Priority 1 owns this link', 3: 'Output reserved by another input',
  4: 'Another input won arbitration', 5: 'Reservation is waiting for its producer' };
const key = (n, p, v) => `${n}:${p}:${v}`;
const queueKey = (n, v) => `${n}:${v}`;
const tag = word => Math.floor(word / 0x100000000);

// Correlation IDs belong to the observer. The wire format stays unchanged.
// All transfers read pre-edge buffer identities; accepted flits are assigned
// only after every router's departures have been processed. DPI callback order
// across routers therefore cannot create or misattribute packets.
export class NetworkTrace {
  constructor(mesh = '2x1x1', { maxEvents = 50000, maxPackets = 2048 } = {}) {
    this.mesh = mesh; this.dims = dimensions(mesh); this.nodes = this.dims.reduce((a, b) => a * b);
    this.maxEvents = maxEvents; this.maxPackets = maxPackets; this.reset();
  }
  reset() {
    this.events = []; this.packets = new Map(); this.buffers = new Map(); this.reservations = new Map();
    this.waits = new Map(); this.queues = new Map(); this.links = new Map(); this.futureWrites = new Map(); this.futureWaits = new Map();
    this.building = new Map(); this.pending = new Map(); this.injecting = new Map(); this.received = new Map(); this.admissions = new Map(); this.handlers = new Map();
    this.protocolHandlers = new Map(); this.mailboxes = new Map();
    this.nextPacket = 1; this.nextEvent = 1; this.cycle = 0; this.dropped = 0; this.evicted = 0; this.evictedPackets = 0;
    this.selectedPacket = null; this.selectedLink = null; this.selectedEvent = null; this.cursor = null; this.filter = ''; this.generation = 0;
    this.cachedState = null;
    this.breakpoints = new Map(); this.nextBreakpoint = 1; this.lastStop = null;
  }
  setImage(info) {
    for (const word of info.words.values()) {
      const match = word.annotation.match(/message header for (__mdc_[a-z_]+), length/);
      if(match) this.protocolHandlers.set(Number((word.value >> 10n) & 0xfffffn), match[1]);
    }
  }
  decodeMessage(p) {
    p.protocol = this.protocolHandlers.get(p.handler);
    if(p.protocol === '__mdc_spawn' && p.words.length >= 7) {
      p.functionId = p.words[1] & 0xffffffff; p.returnWords = p.words[3] & 0xffffffff;
      p.returnNode = encodedNode(p.words[4] & 65535,this.dims); p.returnAddress = p.words[5] & 0xfffff;
      if(p.returnWords > 0 && p.returnNode !== null) this.mailboxes.set(`${p.returnNode}:${p.returnAddress}`,p.id);
    } else if(['__mdc_set','__mdc_set_aggregate'].includes(p.protocol) && p.words.length >= 3) {
      p.returnAddress = p.words[1] & 0xfffff; p.replyTo = this.mailboxes.get(`${p.destination}:${p.returnAddress}`);
      const request = this.packets.get(p.replyTo);
      if(request) { request.reply = p.id; p.parent ??= request.id; }
    }
  }
  gap(count) {
    this.dropped += count;
    for (const p of this.packets.values()) if (!p.delivered) p.incomplete = true;
    for (const m of [this.buffers, this.reservations, this.waits, this.building, this.pending, this.injecting, this.received, this.admissions, this.handlers, this.mailboxes]) m.clear();
  }
  packet(node, priority, cycle, partial = false) {
    const packet = { id: this.nextPacket++, source: node, priority, sent: cycle, words: [], flits: [], hops: [], incomplete: partial, stalls: 0 };
    this.packets.set(packet.id, packet); return packet;
  }
  add(event, packet) {
    const item = { ...event, id: this.nextEvent++, packet: packet?.id ?? event.packet ?? null };
    this.events.push(item);
    if (packet) packet.lastCycle = event.cycle;
    for (const bp of this.breakpoints.values()) {
      if (!bp.enabled || bp.lastHit === item.cycle || !this.matchesBreakpoint(bp, item, packet)) continue;
      bp.lastHit = item.cycle; this.lastStop ??= { type: 'network', id: bp.id, node: item.node, packet: item.packet, event: item.id,
        message: `Network breakpoint ${bp.id} · ${EVENT_NAMES[item.kind]} · node ${item.node} · cycle ${item.cycle}` };
    }
    return item;
  }
  consume(raw, dropped = 0) {
    this.lastStop = null;

    let start = 0;
    while (start < raw.length) {
      let end = start + 1;
      while (end < raw.length && raw[end].cycle === raw[start].cycle) end++;
      this.edge(raw.slice(start, end)); start = end;
    }
    if (this.events.length > this.maxEvents) { const count = this.events.length - this.maxEvents; this.events.splice(0, count); this.evicted += count; }
    while (this.packets.size > this.maxPackets) {
      const victim = [...this.packets.values()].find(p => p.id !== this.selectedPacket && (p.delivered || p.incomplete));
      const expired = victim ?? this.packets.values().next().value;
      this.packets.delete(expired.id); this.evictedPackets++;
    }
    // These maps retain only bounded addresses seen in this capture window.
    for (const map of [this.futureWrites, this.futureWaits, this.admissions, this.mailboxes]) while (map.size > 8192) map.delete(map.keys().next().value);
    if(dropped) this.gap(dropped);
    this.generation++; return this.lastStop;
  }
  edge(raw) {
    const events = raw.map(e => ({ ...e, node: encodedNode(e.node, this.dims) })).filter(e => e.node !== null && e.node < this.nodes);
    if (!events.length) return;
    this.cycle = events[0].cycle;
    const arrivals = new Map(), changed = new Set();
    for (const e of events.filter(e => e.kind === 6)) {
      const slot = queueKey(e.node, e.priority); let p = this.building.get(slot);
      if (!p) {
        p = this.packet(e.node, e.priority, e.cycle); p.destination = encodedNode(e.value & 65535, this.dims); p.sourceIp = e.ip;
        p.parent = e.flags & 2 ? null : this.handlers.get(queueKey(e.node, (e.flags >>> 2) & 1)) ?? null;
        this.building.set(slot, p);
        if (!this.pending.has(slot)) this.pending.set(slot, []);
        this.pending.get(slot).push(p.id);
      } else {
        if (p.words.length < 2048) p.words.push(e.value); else p.truncated = true;
        if (p.words.length === 1 && tag(e.value) === 5) { p.handler = Math.floor(e.value / 1024) & 0xfffff; p.length = e.value & 1023; }
      }
      this.decodeMessage(p);
      if (e.flags & 1) { p.sendEnd = e.cycle; this.building.delete(slot); }
      this.add(e, p);
    }
    for (const e of events.filter(e => [2, 3, 4, 5].includes(e.kind))) {
      const input = e.kind === 2 ? e.aux & 255 : e.kind === 5 ? e.aux : e.port;
      const inputPriority = e.kind === 2 ? (e.aux >>> 8) & 1 : e.priority;
      const slot = key(e.node, input, inputPriority), token = this.buffers.get(slot);
      const reservation = this.reservations.get(key(e.node, e.port, e.priority));
      const p = this.packets.get(token?.packet ?? reservation?.packet);
      e.sequence = token?.sequence;
      if (e.kind === 2) {
        changed.add(slot); this.waits.delete(slot);
        const out = key(e.node, e.port, e.priority), next = neighbor(e.node, e.port, this.dims);
        if (e.flags & 1) this.reservations.delete(out);
        else this.reservations.set(out, { node: e.node, port: e.port, priority: e.priority, input, packet: p?.id });
        if (e.port) {
          if (next !== null && token) arrivals.set(key(next, OPPOSITE[e.port], e.priority), token);
          const link = this.links.get(out) ?? { node: e.node, port: e.port, priority: e.priority, flits: 0, stalls: 0 };
          link.flits++; this.links.set(out, link);
          if (p && !p.hops.some(h => h.node === e.node && h.port === e.port)) p.hops.push({ node: e.node, port: e.port, next, cycle: e.cycle });
        } else if (p) {
          p.arrived ??= e.cycle;
          // A word reaches the endpoint on its low half. Routing headers were
          // consumed by the router and are never delivered as payload words.
          if (token?.sequence >= 3 && token.sequence % 2 === 0) {
            const slot = queueKey(e.node, e.priority);
            if (!this.received.has(slot)) this.received.set(slot, []);
            this.received.get(slot).push({ packet: p.id, sequence: token.sequence });
          }
          if (e.flags & 1) p.delivered = e.cycle;
        }
      } else if (e.kind === 3) { changed.add(slot); this.waits.delete(slot); }
      else {
        const waitKey = e.kind === 5 ? `producer:${key(e.node, e.port, e.priority)}` : slot;
        const before = this.waits.get(waitKey), port = e.kind === 5 ? e.port : e.aux;
        const wait = { node: e.node, input, port, priority: e.priority, packet: p?.id, reason: e.flags,
          since: before?.packet === p?.id && before?.reason === e.flags ? before.since : e.cycle, cycle: e.cycle };
        wait.duration = e.cycle - wait.since + 1; this.waits.set(waitKey, wait); e.duration = wait.duration;
        if (p) p.stalls++;
        const out = key(e.node, port, e.priority), link = this.links.get(out) ?? { node: e.node, port, priority: e.priority, flits: 0, stalls: 0 };
        link.stalls++; this.links.set(out, link);
      }
      this.add(e, p);
    }
    for (const slot of changed) this.buffers.delete(slot);
    for (const e of events.filter(e => e.kind === 1)) {
      const slot = key(e.node, e.port, e.priority); let token;
      if (e.port === 0) {
        const source = queueKey(e.node, e.priority); let active = this.injecting.get(source);
        if (!active) {
          const id = this.pending.get(source)?.shift(); const p = this.packets.get(id) ?? this.packet(e.node, e.priority, e.cycle, true);
          active = { packet: p.id, sequence: 0 }; this.injecting.set(source, active); p.injected = e.cycle;
        }
        token = { ...active }; active.sequence++;
        const p = this.packets.get(token.packet);
        if (p) {
          if (p.flits.length < 4099) p.flits.push({ value: e.value, tail: !!(e.flags & 1), cycle: e.cycle }); else p.truncated = true;
        }
        if (e.flags & 1) this.injecting.delete(source);
      } else token = arrivals.get(slot);
      if (!token) { const p = this.packet(null, e.priority, e.cycle, true); token = { packet: p.id, sequence: -1 }; }
      this.buffers.set(slot, token); this.waits.delete(slot); e.sequence = token.sequence;
      this.add(e, this.packets.get(token.packet));
    }
    for (const e of events.filter(e => e.kind >= 7)) {
      const slot = queueKey(e.node, e.priority); let p;
      if (e.kind === 7) {
        const token = this.received.get(slot)?.shift(); p = this.packets.get(token?.packet);
        if (p && token.sequence === 4) { this.admissions.set(`${slot}:${e.aux}`, p.id); p.queueAddress = e.aux; p.admitted = e.cycle; }
        if (p && (e.flags & 1)) p.queued = e.cycle;
      } else if (e.kind === 8) {
        p = this.packets.get(this.admissions.get(`${slot}:${e.aux}`));
        if (p) { p.dispatched = e.cycle; this.handlers.set(slot, p.id); }
        else this.handlers.delete(slot);
      } else if (e.kind === 11) {
        this.queues.set(slot, { node: e.node, priority: e.priority, capacity: e.aux, head: Math.floor(e.value / 1024) & 0xfffff,
          occupancy: e.value & 1023, disabled: !!e.flags, cycle: e.cycle });
      } else if (e.kind === 12) {
        p = this.packets.get(this.handlers.get(slot));
        if (p) { p.suspended = e.cycle; p.suspendEarly = !!e.flags; }
        this.handlers.delete(slot);
      } else if (e.kind === 9 && [6, 7].includes(tag(e.value))) {
        this.futureWaits.set(`${e.node}:${e.value}`, { ...e, token: e.value });
        p = this.packets.get(this.handlers.get(slot));
      } else if (e.kind === 10) {
        const before = e.extra + e.flags * 0x100000000;
        p = this.packets.get(this.mailboxes.get(`${e.node}:${e.aux}`));
        if(p && ![6,7].includes(tag(e.value))) { p.resolved = e.cycle; p.result = e.value; }
        this.futureWrites.set(`${e.node}:${e.aux}`, { ...e, before, packet:p?.id });
      }
      this.add(e, p);
    }
    for (const [slot, wait] of this.waits) if (wait.cycle !== this.cycle) this.waits.delete(slot);
  }
  advance(cycle) {
    this.cycle = Number(cycle);
    for (const [slot, wait] of this.waits) if (wait.cycle < this.cycle) this.waits.delete(slot);
  }
  addBreakpoint(spec) {
    if (!['inject', 'deliver', 'link', 'handler', 'stall'].includes(spec.type)) throw new Error('Breakpoint type: inject, deliver, link, handler, or stall.');
    const bp = { ...spec, id: this.nextBreakpoint, enabled: true };
    for (const field of ['node', 'source', 'destination']) if (bp[field] != null && (!Number.isInteger(bp[field]) || bp[field] < 0 || bp[field] >= this.nodes)) throw new Error(`Invalid ${field}.`);
    if (bp.priority != null && ![0, 1].includes(bp.priority)) throw new Error('Priority must be 0 or 1.');
    if (bp.port != null && (!Number.isInteger(bp.port) || bp.port < 0 || bp.port > 6)) throw new Error('Invalid link port.');
    if (bp.handler != null && (!Number.isInteger(bp.handler) || bp.handler < 0 || bp.handler > 0xfffff)) throw new Error('Invalid handler address.');
    if (bp.type === 'stall' && (!Number.isInteger(bp.cycles) || bp.cycles < 1)) throw new Error('A stall breakpoint needs a positive cycle count.');
    this.nextBreakpoint++; this.breakpoints.set(bp.id, bp); return bp.id;
  }
  matchesBreakpoint(bp, e, p) {
    const match = bp.type === 'inject' ? e.kind === 1 && e.port === 0 && e.sequence === 0
      : bp.type === 'deliver' ? e.kind === 2 && e.port === 0 && (e.flags & 1)
      : bp.type === 'handler' ? e.kind === 8
      : bp.type === 'stall' ? [4, 5].includes(e.kind) && e.duration >= bp.cycles
      : e.kind === 2;
    return match && (bp.node == null || bp.node === e.node) && (bp.port == null || bp.port === ([4].includes(e.kind) ? e.aux : e.port))
      && (bp.priority == null || bp.priority === e.priority) && (bp.source == null || bp.source === p?.source)
      && (bp.destination == null || bp.destination === p?.destination) && (bp.handler == null || bp.handler === p?.handler);
  }
  packetAt(id, cycle = this.cursor) {
    const packet = this.packets.get(id); if (!packet || cycle === null) return packet;
    const p = { ...packet, hops:packet.hops.filter(h=>h.cycle<=cycle), flits:packet.flits.filter(f=>f.cycle<=cycle) };
    for(const field of ['injected','arrived','delivered','admitted','queued','dispatched','suspended','resolved','sendEnd']) if(p[field]>cycle) delete p[field];
    if(!p.resolved)delete p.result;
    if(this.packets.get(p.reply)?.sent>cycle)delete p.reply;
    const sends=this.events.filter(e=>e.packet===id&&e.kind===6&&e.cycle<=cycle);
    if(p.sent >= (this.events[0]?.cycle??0))p.words=sends.slice(1).map(e=>e.value);
    return p;
  }
  packetEvents(id = this.selectedPacket) { return this.events.filter(e => e.packet === id && (this.cursor === null || e.cycle <= this.cursor)); }
  visiblePackets(filter = this.filter) {
    const terms = filter.toLowerCase().trim().split(/\s+/);
    return [...this.packets.keys()].map(id=>this.packetAt(id)).filter(p => (this.cursor === null || p.sent <= this.cursor) && terms.every(term => {
      const pair = term.split(':');
      if (pair.length === 2 && ['src', 'dst', 'id', 'priority', 'handler'].includes(pair[0])) return p[{ src: 'source', dst: 'destination', id: 'id', priority: 'priority', handler: 'handler' }[pair[0]]] === Number(pair[1]);
      return `${p.id} ${p.source} ${p.destination} ${p.priority} ${p.handler?.toString(16)} ${p.protocol ?? ''} ${p.delivered ? 'delivered' : 'in flight'} ${p.incomplete ? 'incomplete' : ''}`.includes(term);
    }) && (!this.selectedLink || p.hops.some(h => h.node === this.selectedLink.node && h.port === this.selectedLink.port)));
  }
  stateAt(cycle = this.cursor) {
    if (cycle === null) return { waits: [...this.waits.values()], reservations: [...this.reservations.values()], queues: [...this.queues.values()], links: [...this.links.values()] };
    if (this.cachedState?.cycle === cycle && this.cachedState.generation === this.generation) return this.cachedState.state;
    const waits = new Map(), reservations = new Map(), queues = new Map(), links = new Map();
    for (const e of this.events) {
      if (e.cycle > cycle) continue;
      if (e.kind === 2) {
        const k = key(e.node, e.port, e.priority);
        if (e.flags & 1) reservations.delete(k); else reservations.set(k, { ...e, input: e.aux & 255 });
        const link = links.get(k) ?? { node: e.node, port: e.port, priority: e.priority, flits: 0, stalls: 0 }; link.flits++; links.set(k, link);
      } else if ([4, 5].includes(e.kind) && e.cycle === cycle) waits.set(key(e.node, e.port, e.priority), {
        ...e, input: e.kind === 5 ? e.aux : e.port, port: e.kind === 4 ? e.aux : e.port, reason: e.flags });
      else if (e.kind === 11) queues.set(queueKey(e.node, e.priority), { node: e.node, priority: e.priority, occupancy: e.value & 1023, capacity: e.aux, head: Math.floor(e.value / 1024) & 0xfffff, disabled: !!e.flags });
    }
    const state = { waits: [...waits.values()], reservations: [...reservations.values()], queues: [...queues.values()], links: [...links.values()] };
    this.cachedState = { cycle, generation: this.generation, state }; return state;
  }
  export(metadata = {}) {
    return JSON.stringify({ format: 'j-machine-trace', version: 1, mesh: this.mesh, cycle: this.cycle,
      dropped: this.dropped, evicted: this.evicted, evictedPackets: this.evictedPackets, metadata,
      packets: [...this.packets.values()], events: this.events, state: this.stateAt(null),
      futureWrites: [...this.futureWrites.values()], futureWaits: [...this.futureWaits.values()] });
  }
  static import(text) {
    if (text.length > 64 * 1024 * 1024) throw new Error('Trace exceeds 64 MiB.');
    const data = JSON.parse(text);
    if (!data || data.format !== 'j-machine-trace' || data.version !== 1 || !Array.isArray(data.events) || data.events.length > 100000 || !Array.isArray(data.packets) || data.packets.length > 16384) throw new Error('Invalid trace file.');
    const trace = new NetworkTrace(data.mesh);
    const natural = n => Number.isSafeInteger(n) && n >= 0;
    if (!natural(data.cycle) || ['dropped','evicted','evictedPackets'].some(k => data[k] != null && !natural(data[k]))
      || data.events.some(e => !e || !natural(e.id) || !natural(e.cycle) || !natural(e.node) || e.node >= trace.nodes || !EVENT_NAMES[e.kind] || !natural(e.value) || e.value > 0xfffffffff)
      || data.packets.some(p => !p || !natural(p.id) || !natural(p.sent) || !Array.isArray(p.words) || p.words.length > 2048 || p.words.some(w => !natural(w) || w > 0xfffffffff) || !Array.isArray(p.hops) || p.hops.length > 512 || !Array.isArray(p.flits) || p.flits.length > 4099)) throw new Error('Trace records are invalid.');
    const validNode = n => natural(n) && n < trace.nodes;
    const optionalNode = n => n == null || validNode(n);
    if(new Set(data.packets.map(p=>p.id)).size!==data.packets.length || new Set(data.events.map(e=>e.id)).size!==data.events.length
      || data.events.some(e=>!natural(e.port)||e.port>6||![0,1].includes(e.priority)||!natural(e.aux)||!natural(e.flags)||!natural(e.ip)||e.ip>0xfffff)
      || data.packets.some(p=>!optionalNode(p.source)||!optionalNode(p.destination)||![0,1].includes(p.priority)
        || p.hops.some(h=>!h||!validNode(h.node)||!validNode(h.next)||!natural(h.port)||h.port<1||h.port>6||!natural(h.cycle))
        || p.flits.some(f=>!f||!natural(f.value)||f.value>0x3ffff||!natural(f.cycle)))
      || (data.metadata && (typeof data.metadata!=='object'||Array.isArray(data.metadata)))
      || ['sourcePath','sourceText','image','compiler','imageSHA256'].some(k=>data.metadata?.[k]!=null&&typeof data.metadata[k]!=='string')
      || ['futureWrites','futureWaits'].some(k=>data[k]!=null&&(!Array.isArray(data[k])||data[k].length>8192||data[k].some(e=>!e||!validNode(e.node)||!natural(e.value)||e.value>0xfffffffff||!natural(e.cycle))))) throw new Error('Trace metadata or references are invalid.');
    trace.events = data.events; trace.packets = new Map(data.packets.map(p => [p.id, p])); trace.cycle = data.cycle;
    trace.dropped = data.dropped ?? 0; trace.evicted = data.evicted ?? 0; trace.evictedPackets = data.evictedPackets ?? 0;
    trace.metadata = data.metadata ?? {}; trace.archived = true; trace.cursor = trace.cycle;
    trace.futureWrites = new Map((data.futureWrites ?? []).map(e => [`${e.node}:${e.aux}`, e]));
    trace.futureWaits = new Map((data.futureWaits ?? []).map(e => [`${e.node}:${e.value}`, e]));
    trace.selectedPacket = data.packets[0]?.id ?? null; return trace;
  }
}

export function packetLabel(p) { return `#${p.id} · ${p.source ?? '?'} → ${p.destination ?? '?'} · P${p.priority}`; }
export function linkLabel(link) { return `N${link.node} ${PORTS[link.port]}`; }
