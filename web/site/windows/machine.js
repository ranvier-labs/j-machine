import { ipAddress, ipPhase } from '../debugger.js';
import { describeWord } from '../runtime.js';
import { element, observe, canvasContext, hexAddress } from './common.js';

export function machineWindow(ide) {
  const root = element('div', 'machine-window'), info = element('div', 'tool-strip'), topology = element('span', '', 'NO MACHINE'), cycle = element('strong', '', 'CYCLE 00000000');
  info.append(topology, cycle);
  const stage = element('div', 'machine-stage'), canvas = element('canvas'); canvas.ariaLabel = 'Machine nodes. Choose a node in the debugger to inspect it.'; stage.append(canvas);
  const legend = element('div', 'machine-legend'); legend.innerHTML = '<span><i></i> IDLE</span><span><i class="retiring"></i> ACTIVE</span><span><i class="selected-node"></i> SELECTED</span>';
  const mailbox = element('div', 'mailbox'), label = element('span', '', 'MAIN RESULT'), result = element('strong', '', '—'); label.append(element('small', '', 'NODE 0 / 00300')); mailbox.append(label, result);
  root.append(info, stage, legend, mailbox); let cells = [];
  const draw = () => {
    const context = canvasContext(canvas); if (!context) return;
    const { ctx, width, height } = context, snapshot = ide.debug?.snapshot; cells = [];
    if (!snapshot) { ctx.fillStyle = '#93938c'; ctx.font = '11px Menlo, monospace'; ctx.fillText('Compile a C buffer to load a machine.', 12, 25); return; }
    const nodes = snapshot.nodes, columns = nodes.length <= 4 ? Math.min(nodes.length, width < 260 ? 2 : 4) : Math.max(1, Math.min(nodes.length, Math.ceil(Math.sqrt(nodes.length * width / height))));
    const rows = Math.ceil(nodes.length / columns), gap = nodes.length > 64 ? 2 : 8;
    const w = Math.max(1, (width - gap * (columns - 1) - 2) / columns), h = Math.max(1, (height - gap * (rows - 1) - 2) / rows);
    nodes.forEach((node, index) => {
      const x = 1 + index % columns * (w + gap), y = 1 + Math.floor(index / columns) * (h + gap), selected = index === ide.selectedNode;
      const delta = node.retired - (ide.previous?.nodes[index]?.retired ?? node.retired);
      ctx.fillStyle = node.catastrophe ? '#3b2420' : delta > 0n ? '#30302b' : '#141413'; ctx.fillRect(x, y, w, h);
      ctx.strokeStyle = node.catastrophe ? '#d88373' : selected ? '#d7ae68' : '#51514b'; ctx.lineWidth = 1; ctx.strokeRect(x + .5, y + .5, w - 1, h - 1); cells.push({ x, y, w, h, index });
      if (w < 65 || h < 34) { if (delta > 0n) { ctx.fillStyle = '#d6d6ce'; ctx.fillRect(x + w / 2 - 1, y + h / 2 - 1, 2, 2); } return; }
      ctx.fillStyle = selected ? '#d7ae68' : '#d6d6ce'; ctx.font = '11px Menlo, monospace'; ctx.fillText(`NODE ${String(index).padStart(2, '0')}`, x + 9, y + 21);
      ctx.fillStyle = '#93938c'; ctx.font = '10px Menlo, monospace';
      if (h > 62) ctx.fillText(node.background ? 'BACKGROUND' : `PRIORITY ${node.priority}`, x + 9, y + 42);
      if (h > 86) ctx.fillText(`IP ${hexAddress(ipAddress(node.ip))}:${ipPhase(node.ip)}`, x + 9, y + 65);
      if (h > 111) ctx.fillText(`RETIRED ${node.retired}`, x + 9, y + 89);
    });
  };
  const render = observe(ide, ['machine', 'state'], () => {
    const snapshot = ide.debug?.snapshot;
    if (snapshot) {
      topology.textContent = `${ide.variants.find(v => v.nodes === ide.simulator.nodes).mesh.replaceAll('x', ' × ')} · ${ide.simulator.nodes} NODES`;
      cycle.textContent = `CYCLE ${snapshot.cycle.toString().padStart(8, '0')}`;
      const value = ide.simulator.peek(0, 0x300); result.textContent = describeWord(value); mailbox.classList.toggle('complete', value !== ide.debug.initialResult);
    } draw();
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
