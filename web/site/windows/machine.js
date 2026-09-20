import { element, observe, canvasContext } from './common.js';

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
