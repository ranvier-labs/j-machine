// The lookbook in three acts. Act I states the cost of communication on the
// machines of 1988; Act II shows how the J-Machine answers it, with numbers
// measured on the simulator; Act III is the value proposition: the machine,
// gate for gate, open source, in a browser tab. Everything is drawn
// deterministically from the time t; imagery comes from captured machine data
// (tools/motion/capture.mjs) and the HUD layer is DOM. Cuts sit on bars of the
// 128 BPM soundtrack: the drops at bars 12 and 36, the break at bar 28.
const W = 1920, H = 1080, BAR = 60 / 128 * 4;
const rnd = seed => () => { seed |= 0; seed = seed + 0x6d2b79f5 | 0; let x = Math.imul(seed ^ seed >>> 15, 1 | seed); x = x + Math.imul(x ^ x >>> 7, 61 | x) ^ x; return ((x ^ x >>> 14) >>> 0) / 4294967296; };
const clamp = (v, a = 0, b = 1) => Math.min(b, Math.max(a, v));
const ease = v => { v = clamp(v); return v * v * (3 - 2 * v); };
const pad = (n, w = 2) => String(n).padStart(w, '0');
const fmt = n => Number(n).toLocaleString('en-US');
const esc = s => String(s).replace(/[&<>]/g, c => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;' })[c]);
const FLAP_CHARS = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789#*+-';
// Measured on the simulator (scratchpad latency probe, 2026-09-27): mesh512.c's
// first message, node 0 to node 511, 8 words, first word sent at cycle 1513,
// last at 1623, handler dispatched at 1628. remote_call.c: 6 words, one hop,
// dispatch 16 cycles after the last word.
const FIRST_MESSAGE = { firstWord: 1513, lastWord: 1623, dispatch: 1628, words: 8, hops: 21 };

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
  // Act I: a processor's timeline while software sends one message. Each tick
  // is an instruction; the message needs hundreds of them, and the processor
  // does nothing else meanwhile.
  const artCost = (u, dur) => {
    clear('#070707'); camera(u, dur, 1, 1.05); const ox = 160, oy = 640, len = 1600; const progress = ease(u / (dur * .85));
    ctx.fillStyle = '#8f8c84'; ctx.font = mono(13); ctx.textAlign = 'left'; ctx.fillText('PROCESSOR · 1988 · ONE MESSAGE SEND IN SOFTWARE', ox, oy - 60);
    ctx.fillStyle = '#1c1c19'; ctx.fillRect(ox, oy, len, 56);
    const ticks = 400, shown = Math.floor(progress * ticks);
    for (let i = 0; i < shown; i++) { const x = ox + i * (len / ticks); ctx.fillStyle = i % 25 === 0 ? '#ff5a2d' : '#6b6960'; ctx.fillRect(x, oy + 12, 2, 32); }
    ctx.fillStyle = '#ff5a2d'; ctx.fillRect(ox + shown * (len / ticks), oy, 3, 56);
    ctx.fillStyle = '#8f8c84'; ctx.font = mono(13); ctx.fillText('WAITING', ox, oy + 90); ctx.textAlign = 'right'; ctx.fillText(`${fmt(shown)} INSTRUCTIONS`, ox + len, oy + 90); ctx.textAlign = 'left';
    ctx.fillStyle = '#3a3a34'; ctx.fillRect(ox, oy + 130, len, 1); ctx.fillStyle = '#8f8c84'; ctx.fillText('USEFUL WORK', ox, oy + 160); ctx.fillStyle = '#d7ae68'; ctx.fillRect(ox, oy + 175, 0, 8);
  };
  const artWord = (u, dur) => {
    clear('#070707'); camera(u, dur, 1, 1.06); const r = rnd(7); const cell = 46, ox = (W - 36 * cell) / 2 + 20, oy = 640;
    const tags = ['INT', 'BOOL', 'ADDR', 'CFUT', 'FUT', 'MSG', 'IP', 'SYM'], tagIndex = Math.floor(u / 1.1) % tags.length;
    const sample = sampleAt('hotspot', clamp(u / dur)); const bitsSrc = sample ? sample.retired.reduce((a, b) => a * 31 + b, 17) : 0;
    for (let b = 0; b < 36; b++) { const tag = b >= 32; const on = tag ? (tagIndex >> (b - 32)) & 1 : ((bitsSrc >>> (b % 30)) ^ Math.floor(u * 6 + r() * 4)) & 1;
      ctx.fillStyle = tag ? (on ? '#ff5a2d' : '#3a1a12') : on ? '#d7ae68' : '#181815'; ctx.fillRect(ox + b * cell + (tag ? 24 : 0), oy, cell - 6, 90);
      ctx.fillStyle = '#000'; ctx.font = mono(20); ctx.textAlign = 'center'; ctx.fillText(on ? '1' : '0', ox + b * cell + (tag ? 24 : 0) + (cell - 6) / 2, oy + 56); }
    ctx.fillStyle = '#8f8c84'; ctx.font = mono(13); ctx.textAlign = 'left'; ctx.fillText('DATA · 32 BITS', ox, oy - 18); ctx.fillText('TAG · 4 BITS', ox + 32 * cell + 24, oy - 18);
    ctx.fillStyle = '#ff5a2d'; ctx.font = mono(22, 600); ctx.fillText(tags[tagIndex], ox + 32 * cell + 24, oy + 122);
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
  // Act II payoff: the same timeline as Act I, with the measured cycles of the
  // first message of mesh512.c: eight words leave node 0, the handler runs on
  // node 511 five cycles after the last one.
  const artDispatch = (u, dur) => {
    clear('#070707'); camera(u, dur, 1, 1.05); const ox = 160, oy = 560, len = 1600; const M = FIRST_MESSAGE; const span = M.dispatch - M.firstWord + 20; const X = c => ox + (c - M.firstWord) / span * len;
    const progress = ease(u / (dur * .7)), now = M.firstWord + progress * span;
    ctx.fillStyle = '#8f8c84'; ctx.font = mono(13); ctx.textAlign = 'left'; ctx.fillText('NODE 0 · J-MACHINE · ONE MESSAGE SEND IN HARDWARE · MEASURED ON THE SIMULATOR', ox, oy - 60);
    ctx.fillStyle = '#1c1c19'; ctx.fillRect(ox, oy, len, 56);
    for (let w = 0; w < M.words; w++) { const c = M.firstWord + w * (M.lastWord - M.firstWord) / (M.words - 1); if (c > now) break; ctx.fillStyle = '#d7ae68'; ctx.fillRect(X(c), oy + 8, 14, 40); ctx.fillStyle = '#8f8c84'; ctx.font = mono(11); ctx.fillText(`W${w}`, X(c), oy + 72); }
    if (now >= M.dispatch) { ctx.fillStyle = '#ff5a2d'; ctx.fillRect(X(M.dispatch), oy - 30, 4, 116); ctx.font = mono(13, 600); ctx.fillText(`HANDLER RUNS · NODE 511 · CYCLE ${fmt(M.dispatch)}`, X(M.dispatch) - 260, oy - 44); ctx.fillText(`+${M.dispatch - M.lastWord} CYCLES AFTER THE LAST WORD · ${M.hops} HOPS`, X(M.dispatch) - 300, oy + 110); }
    ctx.fillStyle = '#ff5a2d'; ctx.fillRect(X(Math.min(now, M.dispatch + 20)), oy, 3, 56);
    ctx.fillStyle = '#8f8c84'; ctx.font = mono(13); ctx.fillText(`CYCLE ${fmt(M.firstWord)}`, ox, oy + 90); ctx.textAlign = 'right'; ctx.fillText(`CYCLE ${fmt(Math.floor(Math.min(now, M.dispatch + 20)))}`, ox + len, oy + 90); ctx.textAlign = 'left';
    ctx.fillStyle = '#3a3a34'; ctx.fillRect(ox, oy + 130, len, 1); ctx.fillStyle = '#8f8c84'; ctx.fillText('USEFUL WORK MEANWHILE', ox, oy + 160); ctx.fillStyle = '#d7ae68'; ctx.fillRect(ox, oy + 175, Math.min(len, progress * len), 8);
  };
  const artHotspot = (u, dur) => {
    clear('#060606'); camera(u, dur, 1.02, 1.1); const sample = sampleAt('hotspot', clamp(u / dur)); const cell = 150, ox = W / 2 - 2 * cell + 120, oy = H / 2 - 2 * cell + 20; const hot = 5;
    const pos = n => [ox + (n % 4) * cell + cell / 2, oy + Math.floor(n / 4) * cell + cell / 2];
    gridLines(4, 4, cell, ox, oy, '#ffffff14');
    for (const s of [3, 12, 15, 0]) { const [x1, y1] = pos(s), [x2, y2] = pos(hot); const busy = sample ? sample.sends[s] > 0 : false; ctx.strokeStyle = busy ? '#ff5a2d' : '#ffffff22'; ctx.lineWidth = busy ? 2 : 1; ctx.beginPath(); ctx.moveTo(x1, y1); ctx.lineTo(x2, y2); ctx.stroke();
      if (busy) for (let k = 0; k < 3; k++) { const f = ((u * 1.6 + k / 3 + s * .11) % 1); ctx.fillStyle = '#ff5a2d'; ctx.beginPath(); ctx.arc(x1 + (x2 - x1) * f, y1 + (y2 - y1) * f, 5, 0, Math.PI * 2); ctx.fill(); } }
    for (let n = 0; n < 16; n++) { const [x, y] = pos(n), act = sample ? clamp(sample.retired[n] / 200) : 0; ctx.fillStyle = n === hot ? `rgba(255,90,45,${.35 + act * .65})` : `rgba(215,174,104,${.12 + act * .8})`; ctx.fillRect(x - 34, y - 34, 68, 68); ctx.fillStyle = '#000'; ctx.font = mono(20, 600); ctx.textAlign = 'center'; ctx.fillText(String(n), x, y + 7);
      if (n === hot && sample) { const q = sample.pending[n]; for (let i = 0; i < 4; i++) { ctx.fillStyle = i < q ? '#ff5a2d' : '#ffffff22'; ctx.fillRect(x - 34 + i * 18, y + 44, 14, 8); } } }
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
  const tickerItems = () => ['J-MACHINE', 'FW91', 'MIT AI LAB · 1991', '512 NODES', '36-BIT WORDS', '4,096 WORDS SRAM / NODE', '3-D MESH 8×8×8', 'HANDLER RUNS +5 CYCLES AFTER THE LAST WORD', '32 MESSAGES TO ONE NODE', 'LIFE · 16 GENERATIONS · 14 ALIVE', 'HEAT · 24 SWEEPS · RESIDUAL 196', 'VERILATOR → WASM', 'CYCLE-ACCURATE IN THE BROWSER', 'NO INSTALL', 'APACHE 2.0', 'GITHUB.COM/RANVIER-LABS/J-MACHINE', 'J-MACHINE.PAGES.DEV'];
  const ticker = t => { const text = tickerItems().map(i => `${esc(i)}<span>★</span>`).join(''); const x = -((t * 110) % 3400); return el('ticker', '', `<div style="left:${x}px">${text}${text}</div>`); };
  const wave = t => { const i = Math.floor(t * (music.fps ?? 30)); let bars = ''; for (let k = 0; k < 28; k++) { const v = music.rms[Math.max(0, i - 27 + k)] ?? 0; bars += `<i style="height:${Math.max(2, v * 22)}px"></i>`; } return `<div class="wave">${bars}</div>`; };
  const ruler = t => { let html = ''; for (let i = 0; i < 16; i++) html += `<b>${pad(Math.floor(t * 4) + i * 3, 3)}</b>`; return el('ruler', '', html); };
  const timecode = t => el('timecode', '', `${pad(Math.floor(t / 60))}:${pad(Math.floor(t % 60))}:${pad(Math.floor((t % 1) * 30))}`);
  const common = (t, look, index, count) => el('tl', '', `${look.act ? `${look.act} · ` : ''}${index === null ? 'J-MACHINE · FW91' : `LOOK ${pad(index)} / ${pad(count)}`}`) + el('tr', '', 'J-MACHINE.PAGES.DEV') + wave(t) + ruler(t) + timecode(t) + ticker(t);
  const clock = (x, y, value, sub) => el('clock', `left:${x}px;top:${y}px;bottom:auto`, `${typeof value === 'number' ? fmt(value) : value}<small>${sub}</small>`);
  const caption = (u, lines) => { const html = lines.map(l => words(l.text, u, l.at)).filter(Boolean).join('<br>'); return html ? el('caption', '', html) : ''; };
  const big = (u, at, text, cls = '', style = '') => u >= at ? el(`big ${cls}`, style, text) : '';
  const two = (u, at1, t1, at2, t2, first = '', second = 'orange', top = 340) => big(u, at1, t1, first) + big(u, at2, t2, second, `top:${top}px;font-size:88px`);
  const winBracket = (name, id, u, dur, label, score, focusId = null, zoomTo = 1.08) => { const b = framed(name, id, u, dur, focusId, zoomTo); if (!b) return ''; const x = Math.round(b.x) + 6, y = Math.round(b.y) + 6, w = Math.round(b.w) - 12, h = Math.round(b.h) - 12; return bracket(x, y, w, h) + (label ? el('label', `left:${x + 12}px;top:${y < 90 ? y + 12 : y - 30}px`, `${label}${score ? `<span style="margin-left:26px;color:var(--dim)">${score}</span>` : ''}`) : ''); };
  const card = (u, roman, title) => el('big', 'top:380px;left:64px;font-size:64px;letter-spacing:.02em;font-weight:500', `ACT ${roman}`) + (u > .35 ? el('big orange', 'top:470px;left:64px;font-size:150px', title) : '');

  // ---- timeline: bars → looks ------------------------------------------------
  const ACT1 = 'ACT I · THE COST', ACT2 = 'ACT II · THE MACHINE', ACT3 = 'ACT III · YOURS';
  const looks = [
    { name: 'TITLE', bars: 4, index: null, art: artDark, hud: u => {
      const tag = `<div class="tag" style="left:1180px;top:300px;transform:rotate(-2deg)"><h1>J-MACHINE <span>★</span></h1>MESSAGE-DRIVEN MULTICOMPUTER<table><tr><td>MODEL</td><td>MDP · MESSAGE-DRIVEN PROCESSOR</td></tr><tr><td>SEASON</td><td>FW91 · MIT ARTIFICIAL INTELLIGENCE LAB</td></tr><tr><td>NODES</td><td>512 · 8×8×8 MESH</td></tr><tr><td>WORD</td><td>36 BITS · 32 DATA + 4 TAG</td></tr><tr><td>MEMORY</td><td>4,096 WORDS PER NODE</td></tr><tr><td>CARE</td><td>KEEP MESSAGES SHORT. DO NOT WAIT.</td></tr><tr><td>SHOW</td><td>j-machine.pages.dev</td></tr></table><div class="bar"></div></div>`;
      return big(u, .4, 'J-MACHINE.', '', 'top:260px') + big(u, 1.8, 'One idea:<br>a message should<br>cost almost nothing.', 'orange', 'top:390px;font-size:80px') + (u > 3 ? tag : '') + caption(u, [{ at: .6, text: 'A machine from 1991, built on one idea.' }, { at: 3.4, text: 'A message should cost almost nothing.' }]); } },
    { name: 'ACT I', bars: 1, index: null, act: ACT1, art: artDark, hud: u => card(u, 'I', 'The cost.') },
    { name: 'WAITING', bars: 7, act: ACT1, art: artCost, hud: (u, t, dur) => bracket(150, 560, 1660, 270, 'MODEL 1988 · LOOK 01', '0.61') + label(1560, 860, 'SOFTWARE SEND', true) + label(150, 860, 'DALLY ET AL. 1992: "HUNDREDS OF INSTRUCTIONS"') + dot(1740, 580)
      + big(u, 1.2, 'One message.<br>Hundreds of instructions.', '', 'top:190px;font-size:96px') + big(u, 5.5, 'The processor waits.', 'orange', 'top:420px;font-size:80px')
      + caption(u, [{ at: .4, text: 'Look 01. On the machines of its day, sending one message cost hundreds of instructions.' }, { at: 5.2, text: 'The processor waited.' }]) },
    { name: 'ACT II', bars: 1, index: null, act: ACT2, art: artDark, hud: u => card(u, 'II', 'The machine.') },
    { name: 'THE WORD', bars: 4, act: ACT2, art: artWord, hud: u => bracket(150, 600, 1660, 170, 'MODEL MDP · LOOK 02', '0.97') + label(1560, 790, '36 BITS') + label(150, 790, 'BIT 0', true) + dot(1740, 560)
      + two(u, .5, '36 bits.', 2.6, 'Four of them<br>say what it is.') + clock(96, 860, 36, 'BITS · 32 DATA + 4 TAG') + caption(u, [{ at: .3, text: 'Look 02. Thirty-six bits to a word. Four of them say what it is.' }, { at: 4, text: 'The hardware knows a message when it sees one.' }]) },
    { name: 'THE MESH', bars: 4, act: ACT2, art: artMesh, hud: (u, t, dur) => { const s = sampleAt(meshName, clamp(u / dur)); return bracket(620, 150, 1100, 800, 'MODEL MDP · LOOK 03', '0.98') + label(1560, 960, '8 × 8 × 8', true) + label(1560, 190, 'DIMENSION-ORDER ROUTING · X, Y, Z') + dot(1240, 330)
      + two(u, .5, '512.', 2.4, 'No cache.<br>No waiting.', 'orange', '') + clock(96, 720, s?.cycle ?? 0, `CYCLE · ${fmt(s ? s.retired.filter(r => r > Math.min(...s.retired)).length : 0)} NODES WORKING · ${fmt(s ? s.sends.filter(Boolean).length : 0)} SENDING`) + caption(u, [{ at: .3, text: 'Look 03. Five hundred twelve nodes in a cube. Eight by eight by eight.' }, { at: 4, text: 'Routed in dimension order: x, then y, then z.' }]); } },
    { name: 'DISPATCH', bars: 4, act: ACT2, art: artDispatch, hud: (u, t, dur) => bracket(150, 480, 1660, 280, 'MODEL MDP · LOOK 04', '0.99') + label(1560, 790, 'HARDWARE DISPATCH', true) + label(150, 790, 'MESH512.C · FIRST MESSAGE · NODE 0 → NODE 511') + dot(1740, 500)
      + two(u, 1, '5 cycles.', 4, '21 hops away.') + clock(96, 860, `+${FIRST_MESSAGE.dispatch - FIRST_MESSAGE.lastWord}`, 'CYCLES FROM LAST WORD TO RUNNING HANDLER · MEASURED')
      + caption(u, [{ at: .3, text: 'Look 04. The handler runs 5 cycles after the last word leaves the sender.' }, { at: 4.2, text: '21 hops away. Nobody polled. Nobody copied.' }]) },
    { name: 'THE HOTSPOT', bars: 3, act: ACT2, art: artHotspot, hud: (u, t, dur) => { const s = sampleAt('hotspot', clamp(u / dur)); const calls = data.hotspot ? data.hotspot.samples.slice(0, Math.floor(u / dur * data.hotspot.samples.length)).reduce((a, x) => a + x.dispatches[5], 0) : 0;
      return bracket(700, 170, 720, 720, 'MODEL MDP · LOOK 05', '0.99') + label(1240, 250, 'NODE 5 · HOT', true) + dot(1150, 520) + flap(96, 250, ['YOU HAVE', pad(calls, 2), 'MESSAGES'], u, .3)
      + big(u, 4.5, 'Hotspot.', 'orange', 'top:600px') + clock(96, 780, s?.cycle ?? 0, 'CYCLE · FOUR SENDERS · ONE ADDRESS') + caption(u, [{ at: .3, text: 'Look 05. Four senders, 32 messages, one address.' }, { at: 3.6, text: `Contention is visible, not hidden. ${fmt(totals('hotspot').sends)} link transfers.` }]); } },
    { name: 'LIFE', bars: 4, act: ACT2, art: artLife, hud: (u, t, dur) => { const b = boardAt('life16', u / dur); const gen = b.length ? Math.max(...b.map(f => f.frame)) : 0; const alive = b.reduce((a, f) => { const px = pixels(f); let n = 0; for (let i = 0; i < 16; i++) if (px[i * 4] > 100) n++; return a + n; }, 0);
      return bracket(720, 160, 760, 760, 'MODEL MDP · LOOK 06', '0.96') + label(1500, 900, '16 × 16 · TORUS') + label(700, 940, `GENERATION ${pad(gen)} / 16`, true) + dot(1470, 200) + two(u, .6, 'Alive.', 3, '16 tiles<br>trade edges.', 'orange', '')
      + clock(96, 720, alive, 'CELLS ALIVE · ONE TILE PER NODE') + caption(u, [{ at: .3, text: 'Look 06. Sixteen tiles trade their edges.' }, { at: 3.2, text: 'Sixteen generations of life. 14 survive.' }]); } },
    { name: 'HEAT', bars: 4, act: ACT2, art: artHeat, hud: (u, t, dur) => { const b = boardAt('heat16', u / dur); const sweep = b.length ? Math.max(...b.map(f => f.frame)) : 0; const s = sampleAt('heat16', clamp(u / dur));
      return bracket(720, 160, 760, 760, 'MODEL MDP · LOOK 07', '0.95') + label(1500, 900, '8-BIT TEMPERATURE') + label(700, 940, `SWEEP ${pad(sweep)} / 24`, true) + dot(760, 210) + two(u, .6, 'Cool down.', 3, 'One sweep<br>at a time.')
      + clock(96, 720, s?.cycle ?? 0, 'CYCLE · JACOBI RELAXATION') + caption(u, [{ at: .3, text: 'Look 07. Heat leaves the hot corner, one sweep at a time.' }, { at: 3.6, text: 'Real programs. Real cycles. Residual 196.' }]); } },
    { name: 'ACT III', bars: 1, index: null, act: ACT3, art: artDark, hud: u => card(u, 'III', 'Yours.') },
    { name: 'IN THE TAB', bars: 3, act: ACT3, art: (u, dur) => artStill('workbench', u, dur), hud: (u, t, dur) => winBracket('workbench', 'editor', u, dur, 'MODEL MDP · LOOK 08', '1.00') + label(1300, 150, 'VERILATOR → C++ → WASM', true) + label(64, 150, 'j-machine.pages.dev') + dot(1700, 160)
      + two(u, .4, 'Gate for gate.', 2.2, 'In a browser tab.') + caption(u, [{ at: .3, text: 'Look 08. The whole machine, gate for gate, inside a browser tab.' }, { at: 3, text: 'No hardware. No install.' }]) },
    { name: 'THE DEBUGGER', bars: 4, act: ACT3, art: (u, dur) => artStill('debugger', u, dur, 'debugger', 1.45), hud: (u, t, dur) => winBracket('debugger', 'debugger', u, dur, 'MODEL MDP · LOOK 09 · DEBUGGER', '1.00', 'debugger', 1.45) + winBracket('debugger', 'editor', u, dur, 'BREAKPOINT · LINE 6', null, 'debugger', 1.45)
      + label(1300, 150, 'F10 STEP · F11 NEXT LINE · F5 CONTINUE', true) + label(64, 150, 'REGISTERS · INSTRUCTION POINTER · MEMORY · ANY NODE') + dot(1700, 160)
      + two(u, .4, 'Stop.', 2.2, 'Step. Watch.') + caption(u, [{ at: .3, text: 'Look 09. A breakpoint on a line. One instruction at a time.' }, { at: 3.4, text: 'Registers, memory, the instruction pointer of any node. Amber marks what changed.' }]) },
    { name: 'EVERY PACKET', bars: 4, act: ACT3, art: (u, dur) => artStill('packets', u, dur, 'packets', 1.3), hud: (u, t, dur) => winBracket('packets', 'packets', u, dur, 'MODEL MDP · LOOK 10 · PACKETS', '1.00', 'packets', 1.3) + winBracket('packets', 'geometry', u, dur, 'ROUTING GEOMETRY · OBSERVED ROUTE', null, 'packets', 1.3) + winBracket('packets', 'waiting', u, dur, 'WAITING · WHY A NODE STALLS', null, 'packets', 1.3)
      + label(1300, 150, 'INJECTION · ROUTE · DELIVERY · HANDLER · REPLY', true) + dot(300, 200)
      + two(u, .4, 'Every packet.', 2.2, 'Every cycle.') + caption(u, [{ at: .3, text: 'Look 10. Every message is a packet: injection, route, delivery, handler, reply.' }, { at: 3.6, text: 'Its route drawn in the mesh. Its stalls explained. Nothing is hidden.' }]) },
    { name: 'CONTENTION', bars: 3, act: ACT3, art: (u, dur) => artStill('contention', u, dur, 'geometry', 1.35), hud: (u, t, dur) => winBracket('contention', 'geometry', u, dur, 'MODEL MDP · LOOK 11 · SIXTEEN NODES', '0.99', 'geometry', 1.35) + winBracket('contention', 'waiting', u, dur, 'WAITING', null, 'geometry', 1.35)
      + label(1300, 150, 'RED · BLOCKED INPUT · WIDTH · TRAFFIC', true) + dot(1700, 160)
      + two(u, .4, 'Contention.', 2, 'Explained.') + caption(u, [{ at: .3, text: 'Look 11. Four senders, one address, sixteen nodes.' }, { at: 2.6, text: 'Blocked inputs in red. Network breakpoints stop on a stall.' }]) },
    { name: 'DRAW', bars: 3, act: ACT3, art: (u, dur) => artStill('graphics', u, dur, 'display', 1.35), hud: (u, t, dur) => winBracket('graphics', 'display', u, dur, 'MODEL MDP · LOOK 12 · DISPLAY', '0.98', 'display', 1.35) + label(1300, 150, 'A FRAMEBUFFER PER NODE', true) + dot(300, 200)
      + two(u, .4, 'Draw.', 2, 'Every node<br>its tile.') + caption(u, [{ at: .3, text: 'Look 12. Four nodes split the Mandelbrot set, each painting its own tile.' }, { at: 3, text: 'Watch a pixel: stop when it changes.' }]) },
    { name: 'THE CALL', bars: 4, act: ACT3, light: true, art: u => artLight(u), hud: u => { const src = (data.life16?.source ?? 'int main(void) { return 0; }').split('\n'); const start = Math.max(0, src.findIndex(l => /@/.test(l)) - 6); const lines = src.slice(start, start + 20); const chars = Math.floor(u * 140); let acc = 0, html = '';
      for (const line of lines) { if (acc >= chars) break; const part = line.slice(0, chars - acc); acc += line.length + 1; html += esc(part).replace(/(\w+\([^)]*\))@(\w+(?:\([^)]*\))?)/g, '<b>$1</b><em>@$2</em>') + '\n'; }
      return big(u, .3, 'Message-Driven C.', '', 'top:190px;font-size:104px') + big(u, 1.4, 'f()@node', 'mono orange', 'top:330px;font-size:120px')
        + big(u, 2.6, 'C plus one operator.<br>Compiled in the tab by a compiler<br>written in Lean 4, running as WebAssembly.', '', 'top:520px;font-size:44px;line-height:1.15;font-weight:500;letter-spacing:-.01em;max-width:1000px')
        + el('code', 'left:1040px;top:190px;font-size:21px;line-height:1.45', html) + bracket(1010, 170, 860, 700) + label(1022, 150, 'LIFE16.C · SIXTEEN NODES') + label(1560, 880, 'COMPILER · LEAN 4 → WASM', true) + dot(1850, 200)
        + caption(u, [{ at: .3, text: 'Look 13. C plus one operator: call a function at a node.' }, { at: 3.6, text: 'The compiler is written in Lean 4 and runs in the tab as WebAssembly. No toolchain to install.' }]); } },
    { name: 'FREE', bars: 3, act: ACT3, light: true, art: u => artLight(u), hud: u => flap(96, 250, ['OPEN SOURCE', 'APACHE 2 0', 'FREE'], u, .3, 5) + big(u, 2.4, 'Yours.', 'orange', 'top:620px') + label(96, 560, 'github.com/ranvier-labs/j-machine · rtl, compiler, workbench')
      + caption(u, [{ at: .3, text: 'Look 14. Open source. Apache 2.0. Free.' }, { at: 2.6, text: 'The RTL, the compiler, the workbench.' }]) },
    { name: 'END', bars: 5, index: null, light: true, art: u => artLight(u), hud: u => flap(96, 200, ['START HERE'], u, .2, 11) + big(u, .9, 'j-machine.pages.dev', 'orange', 'top:330px;font-size:132px;letter-spacing:-.03em;max-width:1800px')
      + big(u, 2.2, 'Open source · Apache 2.0<br>github.com/ranvier-labs/j-machine', '', 'top:560px;font-size:48px;font-weight:500;letter-spacing:-.01em;max-width:1800px') + (u > 4.5 ? el('label', 'left:96px;top:790px;font-size:18px;padding:8px 14px', 'RANVIER LABS · 2026 · MADE WITH THE SIMULATOR IT SHOWS') : '')
      + caption(u, [{ at: .3, text: 'Start at j-machine.pages.dev.' }, { at: 4.6, text: 'Every cycle count in this film was measured on the simulator.' }]) },
  ];
  let start = 0; for (const look of looks) { look.start = start; look.dur = look.bars * BAR; start += look.dur; }
  const numbered = looks.filter(l => l.index !== null);
  const duration = start;

  function seek(t) {
    t = clamp(t, 0, duration - 1 / 60);
    const look = looks.find(l => t < l.start + l.dur) ?? looks[looks.length - 1];
    const u = t - look.start, index = look.index === null ? null : numbered.indexOf(look) + 1;
    stage.classList.toggle('light', Boolean(look.light));
    look.art(u, look.dur);
    if (u < .1 && look !== looks[0]) { ctx.setTransform(1, 0, 0, 1, 0, 0); ctx.fillStyle = `rgba(255,255,255,${.35 * (1 - u / .1)})`; ctx.fillRect(0, 0, W, H); }
    hud.innerHTML = common(t, look, index, numbered.length) + look.hud(u, t, look.dur);
  }
  return { duration, seek, looks };
}
