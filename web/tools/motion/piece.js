// A short film about the J-Machine in three acts, rendered frame by frame.
// Act I states the problem with a published measurement: the cost of one
// message on the multicomputers of 1993 (Noakes, Wallach and Dally, "The
// J-Machine Multicomputer: An Architectural Evaluation", ISCA 1993, Table 1).
// Act II shows how the J-Machine removes that cost, with cycles measured on
// the RTL simulator: routing, hardware dispatch, tagged futures, and two
// programs checked against host models. Act III shows what the viewer can do
// with it: the workbench, the language and its compiler, the address.
// Imagery comes from captured machine data (capture.mjs) and workbench
// screenshots (ide_stills.mjs); the HUD layer is DOM. Cuts sit on bars of
// the 128 BPM soundtrack (music.py): drops at bars 9 and 27, break at 21.
const W = 1920, H = 1080, BAR = 60 / 128 * 4;
const rnd = seed => () => { seed |= 0; seed = seed + 0x6d2b79f5 | 0; let x = Math.imul(seed ^ seed >>> 15, 1 | seed); x = x + Math.imul(x ^ x >>> 7, 61 | x) ^ x; return ((x ^ x >>> 14) >>> 0) / 4294967296; };
const clamp = (v, a = 0, b = 1) => Math.min(b, Math.max(a, v));
const ease = v => { v = clamp(v); return v * v * (3 - 2 * v); };
const pad = (n, w = 2) => String(n).padStart(w, '0');
const fmt = n => Number(n).toLocaleString('en-US');
const esc = s => String(s).replace(/[&<>]/g, c => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;' })[c]);
const FLAP_CHARS = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789#*+-';
// Noakes, Wallach and Dally, ISCA 1993, Table 1: one-way message overhead,
// the sum of the fixed costs of send and receive, in processor cycles.
const OVERHEAD = [
  { machine: 'nCUBE/2', software: 'VENDOR LIBRARY', cycles: 3200, us: 160 },
  { machine: 'Intel Delta', software: 'VENDOR LIBRARY', cycles: 2880, us: 72 },
  { machine: 'CM-5', software: 'VENDOR LIBRARY', cycles: 2838, us: 86 },
  { machine: 'nCUBE/2', software: 'ACTIVE MESSAGES', cycles: 460, us: 23 },
  { machine: 'CM-5', software: 'ACTIVE MESSAGES', cycles: 109, us: 3.3 },
  { machine: 'J-Machine', software: 'HARDWARE', cycles: 11, us: .9 },
];
// Measured with the IDE's packet tracer (site/network/trace.js) on
// mesh_rainbow.c, packet 4: node 0 calls node 511, 9 words, 21 hops.
const CORNER = { send: 4999, injected: 5068, arrived: 5096, dispatched: 5114, tail: 5166, hops: 21, words: 9 };
// remote_call.c: remote_add(20, 22)@1 returns 20 + 22 + 100; its future is
// resolved at cycle 5,222. Tag codes from site/runtime.js: INT 1, FUT 7.
const FUTURE = { value: 142, resolved: 5222, tagFut: 7, tagInt: 1 };
export function build(data) {
  const stage = document.getElementById('stage'), hud = document.getElementById('hud'), ctx = document.getElementById('art').getContext('2d');
  const music = data.music ?? { rms: [], fps: 30 };
  const stills = Object.fromEntries(Object.entries(data.stills ?? {}).map(([name, still]) => [name, { ...still, image: Object.assign(new Image(), { src: still.data }) }]));
  const box = (name, id) => stills[name]?.windows?.[id];
  const decoded = new Map();
  const pixels = frame => { if (!decoded.has(frame)) { const bin = atob(frame.rgb), out = new Uint8ClampedArray(bin.length); for (let i = 0; i < bin.length; i++) out[i] = bin.charCodeAt(i); decoded.set(frame, out); } return decoded.get(frame); };
  const totals = name => data[name]?.totals ?? { sends: 0, retired: 0, dispatches: 0 };
  const boardAt = (name, f) => { const p = data[name]; if (!p) return []; const c = f * p.cycles, latest = new Map(); for (const fr of p.frames) { if (fr.frame > 0 && fr.cycle <= c) latest.set(fr.node, fr); } return [...latest.values()]; };
  const sampleAt = (name, f) => { const p = data[name]; if (!p?.samples.length) return null; return p.samples[Math.min(p.samples.length - 1, Math.floor(f * p.samples.length))]; };
  const meshName = data.rainbow ? 'rainbow' : 'mesh512';

  // ---- imagery ----------------------------------------------------------
  const clear = (color = '#050505') => { ctx.setTransform(1, 0, 0, 1, 0, 0); ctx.fillStyle = color; ctx.fillRect(0, 0, W, H); };
  const camera = (u, dur, from = 1, to = 1.07, dx = 0, dy = 0) => { const s = from + (to - from) * (u / dur); ctx.setTransform(s, 0, 0, s, W / 2 - s * (W / 2 + dx * u / dur), H / 2 - s * (H / 2 + dy * u / dur)); };
  const dotField = (u, seed = 1, color = '#ffffff') => { const r = rnd(seed); ctx.fillStyle = color; for (let i = 0; i < 260; i++) { const x = r() * W, y = r() * H, a = .04 + .08 * (.5 + .5 * Math.sin(u * 1.7 + i)); ctx.globalAlpha = a; ctx.fillRect(x, y, 2, 2); } ctx.globalAlpha = 1; };
  const mono = (size, weight = 500) => `${weight} ${size}px Berkeley Mono, Menlo, monospace`;
  const tiles = (frames, tilesAcross, tileW, tileH, cell, ox, oy, colorOf = (r, g, b) => `rgb(${r},${g},${b})`) => {
    for (const fr of frames) { const px = pixels(fr), tx = fr.node % tilesAcross, ty = Math.floor(fr.node / tilesAcross);
      for (let i = 0; i < fr.width * fr.height; i++) { const x = tx * tileW + i % fr.width, y = ty * tileH + Math.floor(i / fr.width); ctx.fillStyle = colorOf(px[i * 4], px[i * 4 + 1], px[i * 4 + 2]); ctx.fillRect(ox + x * cell, oy + y * cell, cell - 2, cell - 2); } }
  };
  const gridLines = (cols, rows, cell, ox, oy, color = '#ffffff12') => { ctx.strokeStyle = color; ctx.lineWidth = 1; for (let x = 0; x <= cols; x++) { ctx.beginPath(); ctx.moveTo(ox + x * cell - 1, oy); ctx.lineTo(ox + x * cell - 1, oy + rows * cell); ctx.stroke(); } for (let y = 0; y <= rows; y++) { ctx.beginPath(); ctx.moveTo(ox, oy + y * cell - 1); ctx.lineTo(ox + cols * cell, oy + y * cell - 1); ctx.stroke(); } };

  const artDark = u => { clear('#050505'); dotField(u); };
  const artLight = u => { clear('#ece9e2'); dotField(u, 9, '#000000'); };
  // Act I: the published cost of one message, drawn to scale.
  const COST_REVEAL = 5.6;
  const artCost = (u, dur) => {
    clear('#070707'); camera(u, dur, 1, 1.03); const x0 = 520, len = 1180, y0 = 420, row = 76, max = OVERHEAD[0].cycles;
    for (const [i, r] of OVERHEAD.entries()) {
      const last = i === OVERHEAD.length - 1, at = last ? COST_REVEAL : .9 + i * .45; if (u < at) continue;
      const grow = ease((u - at) / .8), w = Math.max(3, r.cycles / max * len * grow), y = y0 + i * row;
      ctx.textAlign = 'left'; ctx.fillStyle = last ? '#ff5a2d' : '#e8e4dc'; ctx.font = '700 30px Helvetica Neue, Helvetica, Arial, sans-serif'; ctx.fillText(r.machine, 100, y + 30);
      ctx.fillStyle = '#8f8c84'; ctx.font = mono(13); ctx.fillText(r.software, 100, y + 52);
      ctx.fillStyle = last ? '#ff5a2d' : i < 3 ? '#8a8577' : '#5f5b52'; ctx.fillRect(x0, y + 8, w, 40);
      ctx.fillStyle = last ? '#ff5a2d' : '#e8e4dc'; ctx.font = mono(26, 600); ctx.fillText(fmt(Math.round(r.cycles * grow)), x0 + w + 18, y + 38);
      ctx.fillStyle = '#8f8c84'; ctx.font = mono(13); ctx.fillText(`${r.us} µs`, x0 + w + 18, y + 58);
    }
  };
  // Act II: one message's measured timeline, node 0 above, node 511 below.
  const artArrival = (u, dur) => {
    clear('#070707'); const C = CORNER, c0 = C.send - 10, c1 = C.tail + 14, x0 = 160, len = 1600, X = c => x0 + (c - c0) / (c1 - c0) * len;
    const now = c0 + ease(u / (dur * .72)) * (c1 - c0), lane0 = 560, lane1 = 700;
    ctx.font = mono(14); ctx.textAlign = 'left'; ctx.fillStyle = '#8f8c84'; ctx.fillText('NODE 0', x0, lane0 - 16); ctx.fillText('NODE 511 · 21 HOPS AWAY', x0, lane1 - 16);
    ctx.fillStyle = '#1c1c19'; ctx.fillRect(x0, lane0, len, 44); ctx.fillRect(x0, lane1, len, 44);
    const span = (lane, a, b, color) => { if (now <= a) return; ctx.fillStyle = color; ctx.fillRect(X(a), lane, X(Math.min(b, now)) - X(a), 44); };
    span(lane0, C.send, C.injected, '#5f5b52');                 // the runtime formats the message
    span(lane1, C.arrived, C.tail, '#d7ae68');                  // words arriving
    span(lane1 + 50, C.dispatched, C.tail + 14, '#ff5a2d');    // handler running
    if (now > C.injected) { ctx.strokeStyle = '#d7ae68'; ctx.lineWidth = 2; ctx.beginPath(); ctx.moveTo(X(C.injected), lane0 + 44); ctx.lineTo(X(Math.min(now, C.arrived)), lane0 + 44 + (lane1 - lane0 - 44) * clamp((now - C.injected) / (C.arrived - C.injected))); ctx.stroke(); }
    const marks = [[C.send, 'SEND STARTS', lane0, -1], [C.injected, 'FIRST WORD LEAVES', lane0, -1], [C.arrived, 'FIRST WORD ARRIVES', lane1, 1], [C.tail, 'LAST WORD ARRIVES', lane1, 1]];
    for (const [c, text, lane, side] of marks) { if (now < c) continue; const x = X(c); ctx.fillStyle = c === C.dispatched ? '#ff5a2d' : '#e8e4dc'; ctx.fillRect(x - 1, lane - 8, 2, 60);
      ctx.font = mono(13, 600); ctx.textAlign = 'left'; const ty = side < 0 ? lane - 40 : lane + (lane === lane1 + 50 ? 76 : 138); ctx.fillText(text, x + 6, ty); ctx.fillStyle = '#8f8c84'; ctx.font = mono(13); ctx.fillText(`CYCLE ${fmt(c)}`, x + 6, ty + 18); }
    if (now >= C.dispatched) { ctx.fillStyle = '#000'; ctx.font = mono(14, 700); ctx.textAlign = 'left'; ctx.fillText(`HANDLER RUNS · CYCLE ${fmt(C.dispatched)}`, X(C.dispatched) + 10, lane1 + 78); }
    ctx.fillStyle = '#ff5a2d'; ctx.fillRect(X(Math.min(now, c1)), lane0 - 10, 2, lane1 - lane0 + 110);
  };
  // Act II: a future. The word is FUT until the reply writes INT 142.
  const FUTURE_REPLY = 4.2;
  const artFuture = (u, dur) => {
    clear('#070707'); camera(u, dur, 1, 1.04); const cell = 44, ox = (W - 36 * cell - 24) / 2, oy = 640, resolved = u >= FUTURE_REPLY;
    const tag = resolved ? FUTURE.tagInt : FUTURE.tagFut;
    for (let i = 0; i < 36; i++) { const bit = 35 - i, isTag = bit >= 32, x = ox + i * cell + (isTag ? 0 : 24);
      const on = isTag ? (tag >> (bit - 32)) & 1 : resolved ? (FUTURE.value >> bit) & 1 : 0, known = isTag || resolved;
      ctx.fillStyle = isTag ? (on ? '#ff5a2d' : '#5a2418') : !known ? '#141412' : on ? '#d7ae68' : '#2a2a26'; ctx.fillRect(x, oy, cell - 6, 90);
      ctx.strokeStyle = isTag ? '#ff5a2d88' : '#8f8c8488'; ctx.lineWidth = 1; ctx.strokeRect(x + .5, oy + .5, cell - 7, 89);
      if (known) { ctx.fillStyle = on ? '#000' : '#8f8c84'; ctx.font = mono(20); ctx.textAlign = 'center'; ctx.fillText(on ? '1' : '0', x + (cell - 6) / 2, oy + 56); } }
    ctx.textAlign = 'left'; ctx.fillStyle = '#8f8c84'; ctx.font = mono(13); ctx.fillText('TAG · BITS 35–32', ox, oy - 18); ctx.fillText('DATA · BITS 31–0', ox + 4 * cell + 24, oy - 18);
    ctx.fillStyle = '#ff5a2d'; ctx.font = mono(24, 600); ctx.fillText(resolved ? 'INT' : 'FUT', ox, oy + 128);
    ctx.fillStyle = resolved ? '#d7ae68' : '#8f8c84'; ctx.fillText(resolved ? '142' : 'NOT YET COMPUTED', ox + 4 * cell + 24, oy + 128);
  };

  const artMesh = (u, dur) => {
    clear('#040406'); const a = .55 + u * .07, cs = Math.cos(a), sn = Math.sin(a);
    const P = data[meshName], index = P ? Math.min(P.samples.length - 1, Math.floor(clamp(u / dur) * P.samples.length)) : 0, glow = new Float32Array(512), sent = new Uint8Array(512);
    for (let k = 0; k < 30 && P && index - k >= 0; k++) { const smp = P.samples[index - k], sorted = [...smp.retired].sort((p, q) => p - q), base = sorted[256], max = Math.max(base + 1, sorted[511]); for (let n = 0; n < 512; n++) { const g = clamp((smp.retired[n] - base) / (max - base)) * (1 - k / 30); if (g > glow[n]) glow[n] = g; if (k < 6 && smp.sends[n] > 0) sent[n] = 1; } }
    const pts = [];
    for (let n = 0; n < 512; n++) { const x = n % 8 - 3.5, y = Math.floor(n / 8) % 8 - 3.5, z = Math.floor(n / 64) - 3.5; const xr = x * cs - y * sn, yr = x * sn + y * cs; pts.push({ n, sx: W / 2 + 60 + xr * 96, sy: H / 2 + 40 + yr * 40 - z * 76, depth: yr, act: glow[n], sending: Boolean(sent[n]) }); }
    pts.sort((p, q) => p.depth - q.depth); const at = n => pts.find(k => k.n === n);
    ctx.lineWidth = 1; ctx.strokeStyle = '#ffffff12';
    for (const p of pts) { const n = p.n; for (const m of [n % 8 < 7 ? n + 1 : -1, Math.floor(n / 8) % 8 < 7 ? n + 8 : -1, n < 448 ? n + 64 : -1]) { if (m < 0) continue; const q = at(m); ctx.beginPath(); ctx.moveTo(p.sx, p.sy); ctx.lineTo(q.sx, q.sy); ctx.stroke(); } }
    for (const p of pts) { const size = 2.5 + (p.depth + 5) * .35; ctx.beginPath(); ctx.arc(p.sx, p.sy, size + p.act * 8, 0, Math.PI * 2); ctx.fillStyle = p.act > .1 ? `rgba(215,174,104,${.3 + p.act * .7})` : 'rgba(110,108,100,.5)'; ctx.fill();
      if (p.sending) { ctx.beginPath(); ctx.arc(p.sx, p.sy, size + 14, 0, Math.PI * 2); ctx.strokeStyle = '#ff5a2d'; ctx.lineWidth = 2; ctx.stroke(); ctx.lineWidth = 1; ctx.strokeStyle = '#ffffff12'; } }
  };
  const artBoard = (name, u, dur, cell, cols, tileW, colorOf) => { clear('#050505'); camera(u, dur, 1, 1.09, 40, -20); const ox = W / 2 - cols * cell / 2 + 140, oy = H / 2 - cols * cell / 2 + 10; gridLines(cols, cols, cell, ox, oy, '#ffffff0c'); tiles(boardAt(name, u / dur), 4, tileW, tileW, cell, ox, oy, colorOf); };
  const artLife = (u, dur) => artBoard('life16', u, dur, 46, 16, 4, r => r > 100 ? '#d7ae68' : '#141412');
  const artHeat = (u, dur) => artBoard('heat16', u, dur, 46, 16, 4, (r, g, b) => `rgb(${Math.min(255, r * 1.1 + 12)},${g * .55 + 8},${b * .4 + 6})`);
  // A workbench still with a slow push toward one window (or the frame centre).
  const cameraFor = (name, u, dur, focusId, zoomTo) => { const f = focusId ? box(name, focusId) : null; const cx = f ? f.x + f.w / 2 : W / 2, cy = f ? f.y + f.h / 2 : H / 2; const s = 1.02 + (zoomTo - 1.02) * ease(u / dur); return { s, tx: clamp(W / 2 - s * cx, W - s * W, 0), ty: clamp(H / 2 - s * cy, H - s * H, 0) }; };
  const artStill = (name, u, dur, focusId = null, zoomTo = 1.08) => {
    clear('#050505'); const still = stills[name]; if (!still?.image.complete || !still.image.naturalWidth) { dotField(u, 3); return; }
    const { s, tx, ty } = cameraFor(name, u, dur, focusId, zoomTo);
    ctx.setTransform(s, 0, 0, s, tx, ty); ctx.drawImage(still.image, 0, 0, W, H); ctx.setTransform(1, 0, 0, 1, 0, 0); ctx.fillStyle = 'rgba(0,0,0,.22)'; ctx.fillRect(0, 0, W, H);
    const top = ctx.createLinearGradient(0, 0, 0, 150); top.addColorStop(0, 'rgba(0,0,0,.85)'); top.addColorStop(1, 'rgba(0,0,0,0)'); ctx.fillStyle = top; ctx.fillRect(0, 0, W, 150);
    const bottom = ctx.createLinearGradient(0, H - 220, 0, H); bottom.addColorStop(0, 'rgba(0,0,0,0)'); bottom.addColorStop(1, 'rgba(0,0,0,.9)'); ctx.fillStyle = bottom; ctx.fillRect(0, H - 220, W, 220);
  };
  // Screen rectangle of a window box under the same camera, for the HUD brackets.
  const framed = (name, id, u, dur, focusId = null, zoomTo = 1.08) => { const b = box(name, id); if (!b) return null; const { s, tx, ty } = cameraFor(name, u, dur, focusId, zoomTo); return { x: b.x * s + tx, y: b.y * s + ty, w: b.w * s, h: b.h * s }; };

  // ---- HUD --------------------------------------------------------------
  const el = (cls, style, html = '') => `<div class="${cls}" style="${style}">${html}</div>`;
  const bracket = (x, y, w, h, label, score) => el('bracket', `left:${x}px;top:${y}px;width:${w}px;height:${h}px`, '<i></i>') + (label ? el('label', `left:${x}px;top:${y - 30}px`, `${label}${score ? `<span style="margin-left:26px;color:var(--dim)">${score}</span>` : ''}`) : '');
  const label = (x, y, text, red = false) => el(`label${red ? ' red' : ''}`, `left:${x}px;top:${y}px`, text);
  const dot = (x, y) => el('dot', `left:${x}px;top:${y}px`);
  const words = (text, u, at, rate = .11) => { if (u < at) return ''; const n = Math.floor((u - at) / rate) + 1; return text.split(' ').slice(0, n).map(w => /^\d[\d,.%]*$/.test(w) ? `<em>${w}</em>` : esc(w)).join(' '); };
  const flap = (x, y, lines, u, at, seed = 3) => { const r = rnd(seed); let html = '', i = 0; for (const [row, line] of lines.entries()) { for (const [col, ch] of [...line].entries()) { const settle = at + .3 + i * .045 + r() * .5; const shown = ch === ' ' ? ' ' : u < at ? ' ' : u < settle ? FLAP_CHARS[Math.floor(u * 22 + i * 7) % FLAP_CHARS.length] : ch; const orange = u >= settle && /\d/.test(ch); html += `<b class="${ch === ' ' ? 'blank' : ''}${orange ? ' orange' : ''}" style="grid-row:${row + 1};grid-column:${col + 1}">${shown === ' ' ? '' : esc(shown)}</b>`; i++; } } return el('flap', `left:${x}px;top:${y}px`, html); };
  const wave = t => { const i = Math.floor(t * (music.fps ?? 30)); let bars = ''; for (let k = 0; k < 28; k++) { const v = music.rms[Math.max(0, i - 27 + k)] ?? 0; bars += `<i style="height:${Math.max(2, v * 22)}px"></i>`; } return `<div class="wave">${bars}</div>`; };
  const common = (t, look) => el('tl', '', look.act ?? 'J-MACHINE') + el('tr', '', 'J-MACHINE.PAGES.DEV') + wave(t);
  const clock = (x, y, value, sub) => el('clock', `left:${x}px;top:${y}px;bottom:auto`, `${typeof value === 'number' ? fmt(value) : value}<small>${sub}</small>`);
  const caption = (u, lines) => { const html = lines.map(l => words(l.text, u, l.at)).filter(Boolean).join('<br>'); return html ? el('caption', '', html) : ''; };
  const big = (u, at, text, cls = '', style = '') => u >= at ? el(`big ${cls}`, style, text) : '';
  const two = (u, at1, t1, at2, t2, first = '', second = 'orange', top = 340) => big(u, at1, t1, first) + big(u, at2, t2, second, `top:${top}px;font-size:88px`);
  const winBracket = (name, id, u, dur, label, score, focusId = null, zoomTo = 1.08) => { const b = framed(name, id, u, dur, focusId, zoomTo); if (!b) return ''; const x = Math.round(b.x) + 6, y = Math.round(b.y) + 6, w = Math.round(b.w) - 12, h = Math.round(b.h) - 12; return bracket(x, y, w, h) + (label ? el('label', `left:${x + 12}px;top:${y < 90 ? y + 12 : y - 30}px`, `${label}${score ? `<span style="margin-left:26px;color:var(--dim)">${score}</span>` : ''}`) : ''); };
  const card = (u, roman, title) => el('big', 'top:380px;left:64px;font-size:64px;letter-spacing:.02em;font-weight:500', `ACT ${roman}`) + (u > .35 ? el('big orange', 'top:470px;left:64px;font-size:150px', title) : '');

  const FEATURES = [
    { title: 'Workbench.', sub: 'EDITOR · FILES · BUILD GRAPH · LISTENER', still: 'workbench', focus: 'editor', zoom: 1.12, label: 'DEVELOPMENT LAYOUT' },
    { title: 'Integrated debugger.', sub: 'BREAKPOINTS · STEPPING · REGISTERS · MEMORY OF ANY NODE', still: 'debugger', focus: 'debugger', zoom: 1.45, label: 'STOPPED AT LINE 6' },
    { title: 'Packet inspector.', sub: 'INJECTION · ROUTE · DELIVERY · HANDLER · REPLY', still: 'packets', focus: 'packets', zoom: 1.3, label: 'FIRST PACKET SELECTED' },
    { title: 'Network monitor.', sub: 'LINK TRAFFIC · BLOCKED INPUTS · WHY A NODE STALLS', still: 'contention', focus: 'geometry', zoom: 1.35, label: 'SIXTEEN NODES · PAUSED MID-RUN' },
    { title: 'Graphical display.', sub: 'A FRAMEBUFFER PER NODE · WATCH A PIXEL', still: 'graphics', focus: 'display', zoom: 1.35, label: 'MANDELBROT · FOUR NODES' },
  ];
  // ---- timeline: bars → looks ------------------------------------------------
  const ACT1 = 'ACT I · THE COST', ACT2 = 'ACT II · HOW IT WORKS', ACT3 = 'ACT III · RUN IT';
  const looks = [
    { name: 'TITLE', bars: 3, art: artDark, hud: u => {
      const tag = `<div class="tag" style="left:1180px;top:250px;transform:rotate(-2deg)"><h1>J-MACHINE</h1>MIT ARTIFICIAL INTELLIGENCE LABORATORY<table><tr><td>PROCESSOR</td><td>MDP · MESSAGE-DRIVEN PROCESSOR</td></tr><tr><td>WORD</td><td>36 BITS · 32 DATA + 4 TAG</td></tr><tr><td>ONE CHIP</td><td>PROCESSOR, ROUTER, 4K WORDS OF MEMORY</td></tr><tr><td>NODES</td><td>512 IN AN 8×8×8 MESH</td></tr><tr><td>CLOCK</td><td>12.5 MHZ</td></tr><tr><td>SOURCE</td><td>NOAKES, WALLACH & DALLY, ISCA 1993</td></tr></table></div>`;
      return big(u, .3, 'J-MACHINE.', '', 'top:230px') + big(u, 1.2, 'A computer built so that<br>sending a message<br>costs almost nothing.', 'orange', 'top:360px;font-size:76px') + (u > 2 ? tag : '')
        + caption(u, [{ at: .3, text: 'The J-Machine was built at MIT between 1988 and 1993.' }, { at: 2.4, text: 'It was designed for programs made of many small threads that message each other constantly.' }]); } },
    { name: 'ACT I', bars: 1, act: ACT1, art: artDark, hud: u => card(u, 'I', 'The cost.') },
    { name: 'COST', bars: 5, act: ACT1, art: artCost, hud: u => big(u, .2, 'One message cost<br>thousands of cycles.', '', 'top:150px;font-size:84px')
      + label(100, 372, 'ONE-WAY MESSAGE OVERHEAD · PROCESSOR CYCLES TO SEND AND RECEIVE') + label(1340, 372, 'NOAKES, WALLACH & DALLY · ISCA 1993 · TABLE 1', true)
      + caption(u, [{ at: .3, text: 'In 1993, sending one message cost thousands of processor cycles with the vendors\' libraries.' }, { at: 2.9, text: 'Tuned software brought it to a few hundred.' }, { at: COST_REVEAL + .2, text: 'On the J-Machine it cost 11.' }]) },
    { name: 'ACT II', bars: 1, act: ACT2, art: artDark, hud: u => card(u, 'II', 'How it works.') },
    { name: 'THE MESH', bars: 3, act: ACT2, art: artMesh, hud: (u, t, dur) => { const s = sampleAt(meshName, clamp(u / dur)); return bracket(620, 150, 1100, 800) + label(632, 162, 'MESH_RAINBOW.C · 512 NODES') + label(1560, 960, '8 × 8 × 8', true) + label(1470, 190, 'ROUTING · X, THEN Y, THEN Z')
      + two(u, .3, '512 nodes.', 1.6, 'One chip each:<br>processor, router,<br>memory.', 'orange', '', 330) + clock(96, 740, s?.cycle ?? 0, 'CYCLE · RINGS MARK ROUTERS CARRYING A MESSAGE')
      + caption(u, [{ at: .3, text: 'Node 0 calls the four far corners of an 8×8×8 cube.' }, { at: 2.6, text: 'Each message goes along x, then y, then z, one cycle per hop.' }]); } },
    { name: 'ARRIVAL', bars: 4, act: ACT2, art: artArrival, hud: (u, t, dur) => big(u, .3, 'The handler starts', '', 'top:150px;font-size:96px') + big(u, 2.2, 'before the message has finished arriving.', 'orange', 'top:250px;font-size:72px;max-width:1800px')
      + label(160, 890, 'MEASURED ON THE RTL · MESH_RAINBOW.C · PACKET 4 · NODE 0 → 511 · 9 WORDS', true)
      + caption(u, [{ at: .3, text: `The first word crosses ${CORNER.hops} hops in ${CORNER.arrived - CORNER.injected} cycles.` }, { at: 3.2, text: `The hardware queues it and starts the handler ${CORNER.dispatched - CORNER.arrived} cycles later, while the rest is still arriving. Nobody polls.` }]) },
    { name: 'FUTURE', bars: 4, act: ACT2, art: artFuture, hud: u => two(u, .3, 'A future is a tagged word.', FUTURE_REPLY - 1.6, 'Read it too early<br>and the thread sleeps.', '', 'orange', 330)
      + label(96, 860, `REMOTE_CALL.C · RESOLVED AT CYCLE ${fmt(FUTURE.resolved)}`, true) + (u >= FUTURE_REPLY ? label(1100, 860, 'REPLY WRITES INT 142 · THREAD WAKES') : label(1100, 860, 'READING FAULTS · THREAD SUSPENDED'))
      + caption(u, [{ at: .3, text: 'remote_add(20, 22)@1 returns at once with a word tagged FUT.' }, { at: 2.6, text: 'Reading it before the reply faults and suspends the thread. The reply writes INT 142 and wakes it.' }]) },
    { name: 'LIFE', bars: 3, act: ACT2, art: artLife, hud: (u, t, dur) => { const b = boardAt('life16', u / dur); const gen = b.length ? Math.max(...b.map(f => f.frame)) : 0; const alive = b.reduce((a, f) => { const px = pixels(f); let n = 0; for (let i = 0; i < 16; i++) if (px[i * 4] > 100) n++; return a + n; }, 0);
      return bracket(720, 160, 760, 760) + label(1500, 900, '16 × 16 · TORUS') + label(720, 118, `GENERATION ${pad(gen)} / 16`, true) + dot(1470, 200) + two(u, .3, 'Game of Life.', 1.8, '16 nodes,<br>one tile each.', '', 'orange')
      + clock(96, 720, alive, 'CELLS ALIVE · ONE TILE PER NODE') + caption(u, [{ at: .3, text: 'Each node owns a 4×4 tile. Node 15 collects the edges and sends every tile its border.' }, { at: 2.8, text: 'After 16 generations 14 cells are alive, the same as a simulation on the host.' }]); } },
    { name: 'HEAT', bars: 3, act: ACT2, art: artHeat, hud: (u, t, dur) => { const b = boardAt('heat16', u / dur); const sweep = b.length ? Math.max(...b.map(f => f.frame)) : 0; const s = sampleAt('heat16', clamp(u / dur));
      return bracket(720, 160, 760, 760) + label(1500, 900, '8-BIT TEMPERATURE') + label(720, 118, `SWEEP ${pad(sweep)} / 24`, true) + dot(760, 210) + two(u, .3, 'Heat equation.', 1.8, 'Jacobi relaxation,<br>24 sweeps.', '', 'orange')
      + clock(96, 720, s?.cycle ?? 0, 'CYCLE · JACOBI RELAXATION') + caption(u, [{ at: .3, text: 'Two spots held hot, two corners held cold. Each sweep sets every cell to the mean of its neighbours.' }, { at: 2.8, text: 'The last sweep changes the plate by 196 in total, the same as a model on the host.' }]); } },
    { name: 'ACT III', bars: 1, act: ACT3, art: artDark, hud: u => card(u, 'III', 'Run it.') },
    { name: 'THE WORKBENCH', bars: 6, act: ACT3, art: (u, dur) => { const each = dur / FEATURES.length, i = Math.min(FEATURES.length - 1, Math.floor(u / each)), f = FEATURES[i]; artStill(f.still, u - i * each, each, f.focus, f.zoom); },
      hud: (u, t, dur) => { const each = dur / FEATURES.length, i = Math.min(FEATURES.length - 1, Math.floor(u / each)), f = FEATURES[i];
        let list = ''; for (const [k, feat] of FEATURES.entries()) { if (u < k * each + .3) break; list += `<div style="margin-bottom:22px;opacity:${k === i ? 1 : .55}"><div style="font:700 56px/1 var(--display);letter-spacing:-.03em">${feat.title}</div><div style="font-size:16px;color:var(--dim);margin-top:6px;letter-spacing:.08em">${feat.sub}</div></div>`; }
        return winBracket(f.still, f.focus, u - i * each, each, f.label, null, f.focus, f.zoom) + (list ? el('div', 'left:64px;top:150px;width:760px;white-space:normal;padding:26px 30px 8px;background:rgba(5,5,5,.72);border:1px solid #ffffff22', list) : '') + label(1560, 150, 'j-machine.pages.dev', true)
          + caption(u, [{ at: .3, text: 'The MDP and its router, compiled from the RTL by Verilator, run cycle for cycle in a browser tab.' }, { at: 5.6, text: 'Around them, the tools to see what every node and every message is doing. Nothing to install.' }]); } },
    { name: 'THE CALL', bars: 3, act: ACT3, light: true, art: u => artLight(u), hud: u => { const src = (data.life16?.source ?? 'int main(void) { return 0; }').split('\n'); const start = Math.max(0, src.findIndex(l => /@/.test(l)) - 6); const lines = src.slice(start, start + 20); const chars = Math.floor(u * 140); let acc = 0, html = '';
      for (const line of lines) { if (acc >= chars) break; const part = line.slice(0, chars - acc); acc += line.length + 1; html += esc(part).replace(/(\w+\([^)]*\))@(\w+(?:\([^)]*\))?)/g, '<b>$1</b><em>@$2</em>') + '\n'; }
      return big(u, .3, 'Message-Driven C.', '', 'top:190px;font-size:104px') + big(u, 1.4, 'f()@node', 'mono orange', 'top:330px;font-size:120px')
        + big(u, 2.2, 'C plus one operator.<br>Compiled in the tab by a compiler<br>written in Lean 4, running as WebAssembly.', '', 'top:520px;font-size:44px;line-height:1.15;font-weight:500;letter-spacing:-.01em;max-width:1000px')
        + el('code', 'left:1040px;top:190px;font-size:21px;line-height:1.45', html) + bracket(1010, 170, 860, 700) + label(1022, 150, 'LIFE16.C · SIXTEEN NODES') + label(1560, 880, 'COMPILER · LEAN 4 → WASM', true) + dot(1850, 200)
        + caption(u, [{ at: .3, text: 'Message-Driven C is C plus one operator: a call suffixed with @node runs on that node.' }, { at: 2.8, text: 'The compiler is written in Lean 4 and runs in the tab as WebAssembly. No toolchain to install.' }]); } },
    { name: 'END', bars: 4, light: true, art: u => artLight(u), hud: u => big(u, .2, 'j-machine.pages.dev', 'orange', 'top:300px;font-size:132px;letter-spacing:-.03em;max-width:1800px')
      + big(u, 1.2, 'Open source · Apache 2.0<br>github.com/ranvier-labs/j-machine', '', 'top:520px;font-size:48px;font-weight:500;letter-spacing:-.01em;max-width:1800px') + (u > 1.8 ? label(96, 700, 'RANVIER LABS') : '')
      + caption(u, [{ at: .3, text: 'Start at j-machine.pages.dev.' }, { at: 2.6, text: '1993 figures: Noakes, Wallach and Dally, ISCA 1993. All other numbers were measured on the simulator.' }]) },
  ];
  let start = 0; for (const look of looks) { look.start = start; look.dur = look.bars * BAR; start += look.dur; }
  const duration = start;

  function seek(t) {
    t = clamp(t, 0, duration - 1 / 60);
    const look = looks.find(l => t < l.start + l.dur) ?? looks[looks.length - 1];
    const u = t - look.start;
    stage.classList.toggle('light', Boolean(look.light));
    look.art(u, look.dur);
    if (u < .1 && look !== looks[0]) { ctx.setTransform(1, 0, 0, 1, 0, 0); ctx.fillStyle = `rgba(255,255,255,${.35 * (1 - u / .1)})`; ctx.fillRect(0, 0, W, H); }
    hud.innerHTML = common(t, look) + look.hud(u, t, look.dur);
  }
  return { duration, seek, looks };
}
