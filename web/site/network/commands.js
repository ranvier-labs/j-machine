export function breakpointSpec(type, text = '') {
  const spec = { type };
  const fields = { node: 'node', src: 'source', dst: 'destination', port: 'port', priority: 'priority', handler: 'handler', cycles: 'cycles' };
  for (const part of text.trim().split(/\s+/).filter(Boolean)) {
    const match = part.match(/^([a-z]+)=(0x[0-9a-f]+|\d+)$/i);
    if (!match || !fields[match[1]]) throw new Error('Use node=0 src=0 dst=1 port=2 priority=0 handler=0x1000 cycles=20.');
    spec[fields[match[1]]] = Number(match[2]);
  }
  if (type === 'stall' && spec.cycles === undefined) spec.cycles = 20;
  return spec;
}
