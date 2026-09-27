// The lookbook: a title, eight numbered looks, and an end card, each drawn
// deterministically from the time t. The imagery comes from captured machine
// data (tools/motion/capture.mjs); the HUD layer is DOM. Replace `art` of a
// look with a photograph or generated still to change the imagery only.
const W = 1920, H = 1080, BAR = 60 / 128 * 4;   // one bar at 128 BPM
const rnd = seed => () => { seed |= 0; seed = seed + 0x6d2b79f5 | 0; let x = Math.imul(seed ^ seed >>> 15, 1 | seed); x = x + Math.imul(x ^ x >>> 7, 61 | x) ^ x; return ((x ^ x >>> 14) >>> 0) / 4294967296; };
const clamp = (v, a = 0, b = 1) => Math.min(b, Math.max(a, v));
const ease = v => { v = clamp(v); return v * v * (3 - 2 * v); };
const pad = (n, w = 2) => String(n).padStart(w, '0');
const fmt = n => Number(n).toLocaleString('en-US');
const esc = s => String(s).replace(/[&<>]/g, c => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;' })[c]);
const FLAP_CHARS = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789#*+-';

export function build(data) {
  const stage = document.getElementById('stage'), hud = document.getElementById('hud'), ctx = document.getElementById('art').getContext('2d');
  const music = data.music ?? { rms: [], fps: 30 };
  const workbench = data.workbench ? Object.assign(new Image(), { src: data.workbench }) : null;
  const decoded = new Map();
  const pixels = frame => { if (!decoded.has(frame)) { const bin = atob(frame.rgb), out = new Uint8ClampedArray(bin.length); for (let i = 0; i < bin.length; i++) out[i] = bin.charCodeAt(i); decoded.set(frame, out); } return decoded.get(frame); };
  const totals = name => data[name]?.totals ?? { sends: 0, retired: 0, dispatches: 0 };
  const cyclesOf = name => data[name]?.cycles ?? 0;
  // Frames of a program at fraction f of its run, one per node (latest frame at or before that cycle).
  const boardAt = (name, f) => { const p = data[name]; if (!p) return []; const c = f * p.cycles, latest = new Map(); for (const fr of p.frames) { if (fr.frame > 0 && fr.cycle <= c) latest.set(fr.node, fr); } return [...latest.values()]; };
  const finalBoard = name => { const p = data[name]; if (!p) return []; const latest = new Map(); for (const fr of p.frames) if (fr.frame > 0) latest.set(fr.node, fr); return [...latest.values()]; };
  const sampleAt = (name, f) => { const p = data[name]; if (!p?.samples.length) return null; return p.samples[Math.min(p.samples.length - 1, Math.floor(f * p.samples.length))]; };

  // ---- imagery ----------------------------------------------------------
  const clear = (color = '#050505') => { ctx.setTransform(1, 0, 0, 1, 0, 0); ctx.fillStyle = color; ctx.fillRect(0, 0, W, H); };
  const camera = (u, dur, from = 1, to = 1.07, dx = 0, dy = 0) => { const s = from + (to - from) * (u / dur); ctx.setTransform(s, 0, 0, s, W / 2 - s * (W / 2 + dx * u / dur), H / 2 - s * (H / 2 + dy * u / dur)); };
  const dotField = (u, seed = 1) => { const r = rnd(seed); ctx.fillStyle = '#ffffff'; for (let i = 0; i < 260; i++) { const x = r() * W, y = r() * H, a = .04 + .08 * (.5 + .5 * Math.sin(u * 1.7 + i)); ctx.globalAlpha = a; ctx.fillRect(x, y, 2, 2); } ctx.globalAlpha = 1; };
  const tiles = (frames, tilesAcross, tileW, tileH, cell, ox, oy, colorOf = (r, g, b) => `rgb(${r},${g},${b})`) => {
    for (const fr of frames) { const px = pixels(fr), tx = fr.node % tilesAcross, ty = Math.floor(fr.node / tilesAcross);
      for (let i = 0; i < fr.width * fr.height; i++) { const x = tx * tileW + i % fr.width, y = ty * tileH + Math.floor(i / fr.width); ctx.fillStyle = colorOf(px[i * 4], px[i * 4 + 1], px[i * 4 + 2]); ctx.fillRect(ox + x * cell, oy + y * cell, cell - 2, cell - 2); } }
  };
  const gridLines = (cols, rows, cell, ox, oy, color = '#ffffff12') => { ctx.strokeStyle = color; ctx.lineWidth = 1; for (let x = 0; x <= cols; x++) { ctx.beginPath(); ctx.moveTo(ox + x * cell - 1, oy); ctx.lineTo(ox + x * cell - 1, oy + rows * cell); ctx.stroke(); } for (let y = 0; y <= rows; y++) { ctx.beginPath(); ctx.moveTo(ox, oy + y * cell - 1); ctx.lineTo(ox + cols * cell, oy + y * cell - 1); ctx.stroke(); } };

  const artTitle = u => { clear('#050505'); dotField(u); };
  const artWord = (u, dur) => { // a 36-bit MDP word: 32 data bits, 4 tag bits
    clear('#070707'); camera(u, dur, 1, 1.06); const r = rnd(7); const cell = 46, ox = (W - 36 * cell) / 2 + 20, oy = 640;
    const tags = ['INT', 'BOOL', 'ADDR', 'CFUT', 'FUT', 'MSG', 'IP', 'SYM'], tagIndex = Math.floor(u / 1.4) % tags.length;
    const sample = sampleAt('hotspot', clamp(u / dur)); const bitsSrc = sample ? sample.retired.reduce((a, b) => a * 31 + b, 17) : 0;
    for (let b = 0; b < 36; b++) { const tag = b >= 32; const on = tag ? (tagIndex >> (b - 32)) & 1 : ((bitsSrc >>> (b % 30)) ^ Math.floor(u * 6 + r() * 4)) & 1;
      ctx.fillStyle = tag ? (on ? '#ff5a2d' : '#3a1a12') : on ? '#d7ae68' : '#181815'; ctx.fillRect(ox + b * cell + (tag ? 24 : 0), oy, cell - 6, 90);
      ctx.fillStyle = '#000'; ctx.font = '500 20px Berkeley Mono, Menlo, monospace'; ctx.textAlign = 'center'; ctx.fillText(on ? '1' : '0', ox + b * cell + (tag ? 24 : 0) + (cell - 6) / 2, oy + 56); }
    ctx.fillStyle = '#8f8c84'; ctx.font = '13px Berkeley Mono, Menlo, monospace'; ctx.textAlign = 'left'; ctx.fillText('DATA · 32 BITS', ox, oy - 18); ctx.fillText('TAG · 4 BITS', ox + 32 * cell + 24, oy - 18);
    ctx.fillStyle = '#ff5a2d'; ctx.font = '600 22px Berkeley Mono, Menlo, monospace'; ctx.fillText(tags[tagIndex], ox + 32 * cell + 24, oy + 122);
  };
  const artMesh = (u, dur) => { // the 8x8x8 mesh lit by mesh512 activity: idle nodes retire a steady background count, working nodes more
    clear('#040406'); const sample = sampleAt(data.rainbow ? 'rainbow' : 'mesh512', clamp(u / dur)); const a = .55 + u * .07, cs = Math.cos(a), sn = Math.sin(a);
    // Activity with a trail: nodes that worked in the last 30 samples keep a fading glow, so the route of the computation through the cube stays visible.
    const P = data.rainbow ?? data.mesh512, index = P ? Math.min(P.samples.length - 1, Math.floor(clamp(u / dur) * P.samples.length)) : 0, glow = new Float32Array(512), sent = new Uint8Array(512);
    for (let k = 0; k < 30 && index - k >= 0; k++) { const smp = P.samples[index - k], sorted = [...smp.retired].sort((p, q) => p - q), base = sorted[256], max = Math.max(base + 1, sorted[511]); for (let n = 0; n < 512; n++) { const a = clamp((smp.retired[n] - base) / (max - base)) * (1 - k / 30); if (a > glow[n]) glow[n] = a; if (k < 6 && smp.sends[n] > 0) sent[n] = 1; } }
    const pts = [];
    for (let n = 0; n < 512; n++) { const x = n % 8 - 3.5, y = Math.floor(n / 8) % 8 - 3.5, z = Math.floor(n / 64) - 3.5; const xr = x * cs - y * sn, yr = x * sn + y * cs; const sx = W / 2 + 60 + xr * 96, sy = H / 2 + 40 + yr * 40 - z * 76; pts.push({ n, sx, sy, depth: yr, act: glow[n], sending: Boolean(sent[n]) }); }
    pts.sort((p, q) => p.depth - q.depth);
    const at = n => pts.find(k => k.n === n);
    ctx.lineWidth = 1; ctx.strokeStyle = '#ffffff12';
    for (const p of pts) { const n = p.n; for (const m of [n % 8 < 7 ? n + 1 : -1, Math.floor(n / 8) % 8 < 7 ? n + 8 : -1, n < 448 ? n + 64 : -1]) { if (m < 0) continue; const q = at(m); ctx.beginPath(); ctx.moveTo(p.sx, p.sy); ctx.lineTo(q.sx, q.sy); ctx.stroke(); } }
    for (const p of pts) { const size = 2.5 + (p.depth + 5) * .35; ctx.beginPath(); ctx.arc(p.sx, p.sy, size + p.act * 8, 0, Math.PI * 2); ctx.fillStyle = p.act > .1 ? `rgba(215,174,104,${.3 + p.act * .7})` : 'rgba(110,108,100,.5)'; ctx.fill();
      if (p.sending) { ctx.beginPath(); ctx.arc(p.sx, p.sy, size + 14, 0, Math.PI * 2); ctx.strokeStyle = '#ff5a2d'; ctx.lineWidth = 2; ctx.stroke(); ctx.lineWidth = 1; ctx.strokeStyle = '#ffffff12'; } }
  };
  const artHotspot = (u, dur) => { // sixteen nodes, four senders, one address
    clear('#060606'); camera(u, dur, 1.02, 1.1); const sample = sampleAt('hotspot', clamp(u / dur)); const cell = 150, ox = W / 2 - 2 * cell + 120, oy = H / 2 - 2 * cell + 20; const hot = 5;
    const pos = n => [ox + (n % 4) * cell + cell / 2, oy + Math.floor(n / 4) * cell + cell / 2];
    gridLines(4, 4, cell, ox, oy, '#ffffff14');
    const senders = [3, 12, 15, 0];
    for (const s of senders) { const [x1, y1] = pos(s), [x2, y2] = pos(hot); const busy = sample ? sample.sends[s] > 0 : false; ctx.strokeStyle = busy ? '#ff5a2d' : '#ffffff22'; ctx.lineWidth = busy ? 2 : 1; ctx.beginPath(); ctx.moveTo(x1, y1); ctx.lineTo(x2, y2); ctx.stroke();
      if (busy) for (let k = 0; k < 3; k++) { const f = ((u * 1.6 + k / 3 + s * .11) % 1); ctx.fillStyle = '#ff5a2d'; ctx.beginPath(); ctx.arc(x1 + (x2 - x1) * f, y1 + (y2 - y1) * f, 5, 0, Math.PI * 2); ctx.fill(); } }
    for (let n = 0; n < 16; n++) { const [x, y] = pos(n), act = sample ? clamp(sample.retired[n] / 200) : 0; ctx.fillStyle = n === hot ? `rgba(255,90,45,${.35 + act * .65})` : `rgba(215,174,104,${.12 + act * .8})`; ctx.fillRect(x - 34, y - 34, 68, 68); ctx.fillStyle = '#000'; ctx.font = '600 20px Berkeley Mono, Menlo, monospace'; ctx.textAlign = 'center'; ctx.fillText(String(n), x, y + 7);
      if (n === hot && sample) { const q = sample.pending[n]; for (let i = 0; i < 4; i++) { ctx.fillStyle = i < q ? '#ff5a2d' : '#ffffff22'; ctx.fillRect(x - 34 + i * 18, y + 44, 14, 8); } } }
  };
  const artBoard = (name, u, dur, cell, cols, tileW, colorOf) => { clear('#050505'); camera(u, dur, 1, 1.09, 40, -20); const ox = W / 2 - cols * cell / 2 + 140, oy = H / 2 - cols * cell / 2 + 10; gridLines(cols, cols, cell, ox, oy, '#ffffff0c'); tiles(boardAt(name, u / dur), 4, tileW, tileW, cell, ox, oy, colorOf); };
  const artLife = (u, dur) => artBoard('life16', u, dur, 46, 16, 4, (r, g, b) => r > 100 ? '#d7ae68' : '#141412');
  const artHeat = (u, dur) => artBoard('heat16', u, dur, 46, 16, 4, (r, g, b) => `rgb(${Math.min(255, r * 1.1 + 12)},${g * .55 + 8},${b * .4 + 6})`);
  const artMandel = (u, dur) => { clear('#050505'); camera(u, dur, 1.12, 1, -30, 0); const cell = 26, ox = W / 2 - 16 * cell + 140, oy = H / 2 - 16 * cell + 10; gridLines(32, 32, cell, ox, oy, '#ffffff08'); ctx.save(); ctx.beginPath(); ctx.rect(ox - 4, oy - 4, 32 * cell + 8, (ease(u / (dur * .8)) * 32) * cell + 4); ctx.clip(); tiles(finalBoard('mandelbrot'), 2, 16, 16, cell, ox, oy, (r, g, b) => { const v = Math.max(r, g, b); const g2 = c => Math.round(255 * Math.pow(c / 255, .55)); return v === 0 ? '#0a0a0a' : `rgb(${g2(r)},${g2(g)},${g2(b)})`; }); ctx.restore(); const row = Math.min(31, Math.floor(ease(u / (dur * .8)) * 32)); ctx.fillStyle = '#ff5a2d'; ctx.fillRect(ox - 40, oy + row * cell, 24, cell - 2); };
  const artWorkbench = (u, dur) => { clear('#050505'); if (workbench?.complete && workbench.naturalWidth) { const s = 1.02 + .08 * (u / dur); ctx.setTransform(s, 0, 0, s, W / 2 - s * (W / 2 + 60 * u / dur), H / 2 - s * (H / 2 - 20)); ctx.drawImage(workbench, 0, 0, W, H); ctx.setTransform(1, 0, 0, 1, 0, 0); ctx.fillStyle = 'rgba(0,0,0,.28)'; ctx.fillRect(0, 0, W, H); } else dotField(u, 3); };
  const artSource = (u, dur) => { clear('#050505'); dotField(u, 5); };

  // ---- HUD --------------------------------------------------------------
  const el = (cls, style, html = '') => `<div class="${cls}" style="${style}">${html}</div>`;
  const bracket = (x, y, w, h, label, score) => el('bracket', `left:${x}px;top:${y}px;width:${w}px;height:${h}px`, '<i></i>') + (label ? el('label', `left:${x}px;top:${y - 30}px`, `${label}${score ? `<span style="margin-left:26px;color:var(--dim)">${score}</span>` : ''}`) : '');
  const label = (x, y, text, red = false) => el(`label${red ? ' red' : ''}`, `left:${x}px;top:${y}px`, text);
  const dot = (x, y) => el('dot', `left:${x}px;top:${y}px`);
  const words = (text, u, at, rate = .11) => { if (u < at) return ''; const n = Math.floor((u - at) / rate) + 1; const parts = text.split(' '); return parts.slice(0, n).map(w => /^\d[\d,.%]*$/.test(w) ? `<em>${w}</em>` : esc(w)).join(' '); };
  const flap = (x, y, lines, u, at, seed = 3) => { const r = rnd(seed); let html = ''; let i = 0; for (const [row, line] of lines.entries()) { for (const [col, ch] of [...line].entries()) { const settle = at + .3 + i * .045 + r() * .5; const target = ch; const shown = ch === ' ' ? ' ' : u < at ? ' ' : u < settle ? FLAP_CHARS[Math.floor(u * 22 + i * 7) % FLAP_CHARS.length] : target; const orange = u >= settle && /\d/.test(ch); html += `<b class="${ch === ' ' ? 'blank' : ''}${orange ? ' orange' : ''}" style="grid-row:${row + 1};grid-column:${col + 1}">${shown === ' ' ? '' : esc(shown)}</b>`; i++; } } return el('flap', `left:${x}px;top:${y}px`, html); };
  const tickerItems = () => ['J-MACHINE', '512 NODES', '36-BIT WORDS', '4,096 WORDS SRAM / NODE', '3-D MESH 8×8×8', '32 MESSAGES TO ONE NODE', 'LIFE · 16 GENERATIONS · 14 ALIVE', 'HEAT · 24 SWEEPS · RESIDUAL 196', 'VERILATOR → WASM', 'CYCLE-ACCURATE IN THE BROWSER', 'APACHE 2.0', 'GITHUB.COM/RANVIER-LABS/J-MACHINE', 'FW91'];
  const ticker = t => { const text = tickerItems().map(i => `${esc(i)}<span>★</span>`).join(''); const x = -((t * 110) % 2600); return el('ticker', '', `<div style="left:${x}px">${text}${text}</div>`); };
  const wave = t => { const i = Math.floor(t * (music.fps ?? 30)); let bars = ''; for (let k = 0; k < 28; k++) { const v = music.rms[Math.max(0, i - 27 + k)] ?? 0; bars += `<i style="height:${Math.max(2, v * 22)}px"></i>`; } return `<div class="wave">${bars}</div>`; };
  const ruler = t => { let html = ''; for (let i = 0; i < 16; i++) html += `<b>${pad(Math.floor(t * 4) + i * 3, 3)}</b>`; return el('ruler', '', html); };
  const timecode = t => { const f = Math.floor((t % 1) * 30); return el('timecode', '', `${pad(Math.floor(t / 60))}:${pad(Math.floor(t % 60))}:${pad(f)}`); };
  const common = (t, look, index, count) => el('tl', '', index === null ? 'J-MACHINE · FW91' : `LOOK ${pad(index)} / ${pad(count)}`) + el('tr', '', 'J-MACHINE · FW91') + wave(t) + ruler(t) + timecode(t) + ticker(t);
  const clock = (x, y, cycles, sub) => el('clock', `left:${x}px;top:${y}px;bottom:auto`, `${fmt(cycles)}<small>${sub}</small>`);
  const caption = (u, lines) => { const html = lines.map(l => words(l.text, u, l.at)).filter(Boolean).join('<br>'); return html ? el('caption', '', html) : ''; };
  const big = (u, at, text, cls = '') => u >= at ? el(`big ${cls}`, '', text) : '';

  // ---- looks ------------------------------------------------------------
  const L = (n, dur) => n * dur;
  const looks = [
    { name: 'TITLE', dur: 4 * BAR, index: null, art: artTitle, hud: (u) => {
      const tag = `<div class="tag" style="left:1180px;top:300px;transform:rotate(-2deg)"><h1>J-MACHINE <span>★</span></h1>MESSAGE-DRIVEN MULTICOMPUTER<table><tr><td>MODEL</td><td>MDP · MESSAGE-DRIVEN PROCESSOR</td></tr><tr><td>SEASON</td><td>FW91 · MIT ARTIFICIAL INTELLIGENCE LAB</td></tr><tr><td>NODES</td><td>512 · 8×8×8 MESH</td></tr><tr><td>WORD</td><td>36 BITS · 32 DATA + 4 TAG</td></tr><tr><td>MEMORY</td><td>4,096 WORDS PER NODE</td></tr><tr><td>CARE</td><td>KEEP MESSAGES SHORT. DO NOT WAIT.</td></tr></table><div class="bar"></div></div>`;
      return (u > .4 ? el('big', 'top:260px', 'J-MACHINE.') : '') + (u > 1.6 ? el('big orange', 'top:390px;font-size:96px', 'Collection<br>of one.') : '') + (u > 2.6 ? tag : '') + caption(u, [{ at: .6, text: 'J-Machine. Fall Winter ninety-one. Collection of one.' }]); } },
    { name: 'THE WORD', dur: 6 * BAR, art: artWord, hud: (u) => bracket(150, 600, 1660, 170, 'MODEL MDP · LOOK 01', '0.97') + label(1560, 790, '36 BITS') + label(150, 790, 'BIT 0', true) + dot(1740, 560)
      + big(u, 1.2, '36 bits.', '') + big(u, 3.3, 'Four of them<br>say what it is.', 'orange') .replace('class="big orange"', 'class="big orange" style="top:340px;font-size:88px"')
      + clock(96, 860, 36, 'BITS · 32 DATA + 4 TAG') + caption(u, [{ at: .4, text: 'Look 01. Thirty-six bits to a word.' }, { at: 3.2, text: 'Four of them say what it is.' }]) },
    { name: 'THE MESH', dur: 6 * BAR, art: artMesh, hud: (u, t, dur) => { const s = sampleAt(data.rainbow ? 'rainbow' : 'mesh512', clamp(u / dur)); return bracket(620, 150, 1100, 800, 'MODEL MDP · LOOK 02', '0.98') + label(1560, 960, '8 × 8 × 8', true) + label(1560, 190, '2 CYCLES / HOP') + dot(1240, 330)
      + big(u, .8, '512.', 'orange') + big(u, 2.4, 'No cache.<br>No waiting.', '').replace('class="big "', 'class="big " style="top:340px;font-size:88px"')
      + clock(96, 720, s?.cycle ?? 0, `CYCLE · ${fmt(s ? s.retired.filter(r => r > Math.min(...s.retired)).length : 0)} NODES WORKING · ${fmt(s ? s.sends.filter(Boolean).length : 0)} SENDING`) + caption(u, [{ at: .3, text: 'Look 02. Five hundred twelve nodes in a cube.' }, { at: 3, text: 'Eight by eight by eight. Two cycles a hop.' }]); } },
    { name: 'THE MESSAGE', dur: 6 * BAR, art: artHotspot, hud: (u, t, dur) => { const s = sampleAt('hotspot', clamp(u / dur)); const calls = data.hotspot ? data.hotspot.samples.slice(0, Math.floor(u / dur * data.hotspot.samples.length)).reduce((a, x) => a + x.dispatches[5], 0) : 0;
      return bracket(700, 170, 720, 720, 'MODEL MDP · LOOK 03', '0.99') + label(1240, 250, 'NODE 5 · HOT', true) + dot(1150, 520) + flap(96, 250, ['YOU HAVE', pad(calls, 2), 'MESSAGES'], u, .5)
      + big(u, 6.2, 'Hotspot.', 'orange').replace('class="big orange"', 'class="big orange" style="top:600px"') + clock(96, 780, s?.cycle ?? 0, 'CYCLE · FOUR SENDERS · ONE ADDRESS') + caption(u, [{ at: .3, text: 'Look 03. Four senders, 32 messages, one address.' }, { at: 4.2, text: `Everybody waits their turn. ${fmt(totals('hotspot').sends)} link transfers.` }]); } },
    { name: 'LIFE', dur: 6 * BAR, art: artLife, hud: (u, t, dur) => { const b = boardAt('life16', u / dur); const gen = b.length ? Math.max(...b.map(f => f.frame)) : 0; const alive = b.reduce((a, f) => { const px = pixels(f); let n = 0; for (let i = 0; i < 16; i++) if (px[i * 4] > 100) n++; return a + n; }, 0);
      return bracket(720, 160, 760, 760, 'MODEL MDP · LOOK 04', '0.96') + label(1500, 900, '16 × 16 · TORUS') + label(700, 940, `GENERATION ${pad(gen)} / 16`, true) + dot(1470, 200) + big(u, 1, 'Alive.', 'orange') + big(u, 4, '16 tiles<br>trade edges.', '').replace('class="big "', 'class="big " style="top:340px;font-size:88px"')
      + clock(96, 720, alive, 'CELLS ALIVE · ONE TILE PER NODE') + caption(u, [{ at: .3, text: 'Look 04. Sixteen tiles trade their edges.' }, { at: 3.6, text: 'Sixteen generations of life. 14 survive.' }]); } },
    { name: 'HEAT', dur: 6 * BAR, art: artHeat, hud: (u, t, dur) => { const b = boardAt('heat16', u / dur); const sweep = b.length ? Math.max(...b.map(f => f.frame)) : 0; const s = sampleAt('heat16', clamp(u / dur));
      return bracket(720, 160, 760, 760, 'MODEL MDP · LOOK 05', '0.95') + label(1500, 900, '8-BIT TEMPERATURE') + label(700, 940, `SWEEP ${pad(sweep)} / 24`, true) + dot(760, 210) + big(u, 1.2, 'Cool down.', '') + big(u, 4.4, 'One sweep<br>at a time.', 'orange').replace('class="big orange"', 'class="big orange" style="top:340px;font-size:88px"')
      + clock(96, 720, s?.cycle ?? 0, 'CYCLE · JACOBI RELAXATION') + caption(u, [{ at: .3, text: 'Look 05. Heat leaves the hot corner.' }, { at: 3.8, text: 'One sweep at a time. Residual 196.' }]); } },
    { name: 'ESCAPE', dur: 6 * BAR, art: artMandel, hud: (u, t, dur) => { const s = sampleAt('mandelbrot', clamp(u / dur)); return bracket(700, 140, 800, 800, 'MODEL MDP · LOOK 06', '0.99') + label(1520, 160, '4 NODES · 2 × 2', true) + label(700, 960, '32 × 32 · ESCAPE TIME') + dot(1240, 560) + big(u, 1, 'Escape.', 'orange') + big(u, 3.8, 'Nobody shares<br>a byte.', '').replace('class="big "', 'class="big " style="top:340px;font-size:88px"')
      + clock(96, 720, s?.cycle ?? 0, 'CYCLE · FOUR QUADRANTS') + caption(u, [{ at: .3, text: 'Look 06. Four nodes split the Mandelbrot set.' }, { at: 3.4, text: 'Nobody shares a byte.' }]); } },
    { name: 'IN THE TAB', dur: 6 * BAR, art: artWorkbench, hud: (u) => bracket(180, 120, 1560, 860, 'MODEL MDP · LOOK 07', '1.00') + label(1400, 1000, 'VERILATOR → C++ → WASM', true) + label(200, 1000, 'j-machine.pages.dev') + dot(1700, 160) + big(u, 1, 'Gate for gate.', '') + big(u, 4, 'In the tab.', 'orange').replace('class="big orange"', 'class="big orange" style="top:330px"')
      + caption(u, [{ at: .3, text: 'Look 07. The whole machine, gate for gate,' }, { at: 3, text: 'inside a browser tab.' }]) },
    { name: 'THE CALL', dur: 6 * BAR, art: artSource, hud: (u) => { const src = (data.life16?.source ?? 'int main(void) { return 0; }').split('\n'); const start = Math.max(0, src.findIndex(l => /@/.test(l)) - 6); const lines = src.slice(start, start + 18); const chars = Math.floor(u * 90); let acc = 0, html = '';
      for (const line of lines) { if (acc >= chars) break; const part = line.slice(0, chars - acc); acc += line.length + 1; html += esc(part).replace(/(\w+\([^)]*\))@(\w+(?:\([^)]*\))?)/g, '<b>$1</b><em>@$2</em>') + '\n'; }
      return el('code', 'left:96px;top:170px', html) + bracket(1180, 170, 660, 380, 'MODEL MDP · LOOK 08', '0.97') + label(1200, 570, 'MESSAGE-DRIVEN C', true) + big(u, 4, 'f()@node', 'mono orange').replace('class="big mono orange"', 'class="big mono orange" style="left:1180px;top:640px;font-size:120px"')
      + caption(u, [{ at: .3, text: 'Look 08. Message-driven C.' }, { at: 2.4, text: 'Call a function at a node. That is the whole language.' }]); } },
    { name: 'END', dur: 3.5 * BAR, index: null, art: artTitle, light: true, hud: (u) => flap(96, 250, ['END OF SHOW', 'J-MACHINE  FW91'], u, .2, 11) + el('label', 'left:96px;top:520px', 'github.com/ranvier-labs/j-machine · Apache 2.0') + el('label', 'left:96px;top:560px', 'j-machine.pages.dev') + caption(u, [{ at: .3, text: 'End of show.' }]) },
  ];
  let start = 0; for (const look of looks) { look.start = start; start += look.dur; }
  const numbered = looks.filter(l => l.index !== null);
  const duration = start;

  function seek(t) {
    t = clamp(t, 0, duration - 1 / 60);
    const look = looks.find(l => t < l.start + l.dur) ?? looks[looks.length - 1];
    const u = t - look.start, index = look.index === null ? null : numbered.indexOf(look) + 1;
    stage.classList.toggle('light', Boolean(look.light));
    if (look.light) clear('#ece9e2'); else look.art(u, look.dur);
    if (look.light) { ctx.setTransform(1, 0, 0, 1, 0, 0); }
    // A hard cut: the first three frames of a look flash the frame white a little, like a shutter.
    if (u < .1 && look !== looks[0]) { ctx.setTransform(1, 0, 0, 1, 0, 0); ctx.fillStyle = `rgba(255,255,255,${.35 * (1 - u / .1)})`; ctx.fillRect(0, 0, W, H); }
    hud.innerHTML = common(t, look, index, numbered.length) + look.hud(u, t, look.dur);
  }
  return { duration, seek, looks };
}
