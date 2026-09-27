import { element, observe, canvasContext } from './common.js';
import { describeWord } from '../runtime.js';
import { basename } from '../core/filesystem.js';

// A newcomer's view of the machine: which nodes are working, how many cycles
// have passed, and what main returned, in large type.
export function machineWindow(ide) {
  const root = element('div', 'machine-window'), strip = element('div', 'tool-strip'), topology = element('strong', '', 'NO MACHINE'), cycle = element('span');
  strip.append(topology, cycle);
  const stage = element('div', 'machine-stage'), canvas = element('canvas'); canvas.ariaLabel = 'Node activity. Click a node to inspect it.'; stage.append(canvas);
  const legend = element('div', 'machine-legend'); legend.innerHTML = '<span><i></i> idle</span><span><i class="active"></i> retiring instructions</span><span><i class="selected-node"></i> selected</span>';
  const result = element('div', 'machine-result'), label = element('span', 'machine-result-label', 'MAIN RESULT · node 0 · word 0x300'), value = element('strong', 'machine-result-value', '—');
  const reason = element('div', 'machine-reason', 'Compile & Run a C buffer to load a machine.');
  result.append(label, value); root.append(strip, stage, legend, result, reason);
  let cells = [];
  const draw = () => {
    const context = canvasContext(canvas); if (!context) return;
    const { ctx, width, height } = context, snapshot = ide.debug?.snapshot; cells = [];
    if (!snapshot) return;
    const nodes = snapshot.nodes, count = nodes.length;
    const columns = count <= 4 ? Math.min(count, width < 260 ? 2 : 4) : Math.max(1, Math.min(count, Math.ceil(Math.sqrt(count * width / height))));
    const rows = Math.ceil(count / columns), gap = count > 64 ? 2 : 8;
    const w = Math.max(1, (width - gap * (columns - 1) - 2) / columns), h = Math.max(1, (height - gap * (rows - 1) - 2) / rows);
    nodes.forEach((node, index) => {
      const x = 1 + index % columns * (w + gap), y = 1 + Math.floor(index / columns) * (h + gap), selected = index === ide.selectedNode;
      const delta = node.retired - (ide.previous?.nodes[index]?.retired ?? node.retired);
      ctx.fillStyle = node.catastrophe ? '#3b2420' : delta > 0n ? '#3a382a' : '#141413'; ctx.fillRect(x, y, w, h);
      ctx.strokeStyle = node.catastrophe ? '#d88373' : selected ? '#d7ae68' : '#51514b'; ctx.lineWidth = selected ? 2 : 1; ctx.strokeRect(x + .5, y + .5, w - 1, h - 1);
      cells.push({ x, y, w, h, index });
      if (w < 62 || h < 30) { if (delta > 0n) { ctx.fillStyle = '#d7ae68'; ctx.fillRect(x + w / 2 - 1, y + h / 2 - 1, 2, 2); } return; }
      ctx.fillStyle = selected ? '#d7ae68' : '#d6d6ce'; ctx.font = '12px Menlo, monospace'; ctx.fillText(`NODE ${index}`, x + 9, y + 20);
      ctx.fillStyle = '#93938c'; ctx.font = '11px Menlo, monospace';
      if (h > 56) ctx.fillText(`${node.retired.toLocaleString()} retired`, x + 9, y + 40);
      if (h > 76) ctx.fillText(delta > 0n ? `+${delta.toLocaleString()} this sample` : node.background ? 'idle' : `priority ${node.priority}`, x + 9, y + 58);
    });
  };
  const render = observe(ide, ['machine', 'state', 'network'], () => {
    const debug = ide.debug, snapshot = debug?.snapshot;
    if (!snapshot) { topology.textContent = 'NO MACHINE'; cycle.textContent = ''; value.textContent = '—'; result.classList.remove('complete'); reason.textContent = ide.machineReason() || 'Compile & Run a C buffer to load a machine.'; draw(); return; }
    const mesh = ide.variants.find(v => v.nodes === ide.simulator.nodes)?.mesh ?? '';
    topology.textContent = `${basename(ide.compiledPath ?? '')} · ${ide.simulator.nodes} NODES · ${mesh.replaceAll('x', ' × ')}`;
    const packets = ide.network?.packets.size ?? 0;
    cycle.textContent = `CYCLE ${snapshot.cycle.toLocaleString()}${packets ? ` · ${packets} PACKETS` : ''}`;
    const word = ide.simulator.peek(0, 0x300), complete = word !== debug.initialResult;
    value.textContent = complete ? describeWord(word) : debug.running ? 'running…' : 'not returned yet';
    result.classList.toggle('complete', complete);
    reason.textContent = debug.running ? 'Executing · F5 pauses' : ide.machineReason() || debug.stopReason.message;
    draw();
  }); render();
  canvas.onclick = event => {
    if (!ide.debug || ide.debug.running) return;
    const rect = canvas.getBoundingClientRect(), x = event.clientX - rect.left, y = event.clientY - rect.top;
    const cell = cells.find(c => x >= c.x && x < c.x + c.w && y >= c.y && y < c.y + c.h);
    if (cell) ide.perform(() => ide.selectNode(cell.index));
  };
  return { id: 'machine', title: 'MACHINE', element: root, onResize: draw };
}

export function traceWindow(ide) {
  const root = element('div', 'trace-window'), meta = element('div', 'tool-strip', 'RETIRED INSTRUCTIONS / 0 SAMPLES'), stage = element('div', 'trace-stage'), canvas = element('canvas');
  canvas.ariaLabel = 'Retired instructions over sampled machine cycles'; stage.append(canvas); root.append(meta, stage);
  const draw = () => {
    const context = canvasContext(canvas); if (!context) return;
    const { ctx, width, height } = context, samples = ide.history; if (!samples.length) return;
    const selected = ide.selectedNode, lanes = [...new Set([selected, ...(ide.simulator.nodes <= 4 ? samples[0].nodes.map(n => n.index) : [0])])].slice(0, 4);
    const plotX = 50, plotW = Math.max(1, width - plotX - 10), laneH = (height - 20) / lanes.length;
    const start = samples[0].cycle, end = samples.at(-1).cycle, span = Number(end - start) || 1;
    lanes.forEach((node, row) => {
      const y = row * laneH; ctx.strokeStyle = '#30302b'; ctx.beginPath(); ctx.moveTo(plotX, y + laneH - 5); ctx.lineTo(width, y + laneH - 5); ctx.stroke();
      ctx.font = '10px Menlo, monospace'; ctx.fillStyle = node === selected ? '#d7ae68' : '#93938c'; ctx.fillText(`N${String(node).padStart(3, '0')}`, 0, y + laneH / 2);
      const initial = samples[0].nodes[node].retired, total = Number(samples.at(-1).nodes[node].retired - initial) || 1;
      ctx.strokeStyle = node === selected ? '#d6d6ce' : '#73736b'; ctx.beginPath();
      samples.forEach((sample, i) => {
        const x = plotX + Number(sample.cycle - start) / span * plotW, pointY = y + laneH - 7 - Number(sample.nodes[node].retired - initial) / total * (laneH - 13);
        if (i === 0) ctx.moveTo(x, pointY); else ctx.lineTo(x, pointY);
      }); ctx.stroke();
    });
    ctx.fillStyle = '#93938c'; ctx.font = '9px Menlo, monospace'; ctx.fillText(start.toString(), plotX, height - 1);
    ctx.textAlign = 'right'; ctx.fillText(`${end} CYCLES`, width, height - 1); ctx.textAlign = 'left';
  };
  const render = observe(ide, ['machine'], () => { meta.textContent = `RETIRED INSTRUCTIONS / ${ide.history.length} SAMPLES`; draw(); }); render();
  return { id: 'trace', title: 'EXECUTION TRACE', element: root, onResize: draw };
}
