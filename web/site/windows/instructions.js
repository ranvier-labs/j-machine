import { element, button, observe, hexAddress, syncCommandButton } from './common.js';
import { ipPhase } from '../debugger.js';
import { decodeWord, instructionAddress } from '../instructions.js';

export function instructionsPanel(ide) {
  const root = element('div', 'instructions-panel'), controls = element('div', 'instruction-controls');
  controls.append(element('span', '', 'Next:'));
  const steps = [['Instruction', 'instruction', 'step-instruction'], ['Clock cycle', 'cycles', 'step-cycle'], ['Source line', 'source', 'step-source']].map(([label, mode, command]) => {
    const control = button(label, `Next ${label.toLowerCase()}`, () => ide.perform(() => ide.execute(mode)));
    controls.append(control); return { control, command };
  });
  const run = button('Run', 'Run or pause the machine', () => ide.perform(() => ide.run()), 'instruction-run'); controls.append(run);
  const status = element('div', 'instruction-status'), listing = element('div', 'instruction-listing');
  listing.ariaLabel = 'MDP instructions in selected node memory';
  const table = element('div', 'instruction-table'), headers = element('div', 'instruction-row instruction-headers');
  table.setAttribute('role', 'table'); table.ariaLabel = 'MDP instructions in selected node memory';
  headers.setAttribute('role', 'row'); listing.setAttribute('role', 'rowgroup');
  for (const [className, label, title] of [
    ['instruction-marker', '', 'Arrow marks the next fetch'],
    ['instruction-address', 'Word : slot', 'Hexadecimal memory-word address on the selected node. Slot 0 is the high instruction, executed first; slot 1 is the low instruction, executed second.'],
    ['instruction-encoding', 'Hex bits', 'Encoded 17-bit instruction, or the whole 36-bit word for a literal constant.'],
    ['instruction-code', 'MDP instruction', 'Decoded MDP Version 11 instruction and operands. Hover or focus a row for an explanation.'],
    ['instruction-source', 'Source line', 'Corresponding line in the compiled C source, when available.'],
  ]) {
    const cell = element('span', className, label); cell.setAttribute('role', 'columnheader'); cell.title = title;
    if (!label) cell.ariaLabel = title;
    headers.append(cell);
  }
  const legend = element('div', 'instruction-legend'); legend.id = 'instruction-legend'; legend.setAttribute('popover', 'auto');
  legend.setAttribute('role', 'dialog'); legend.setAttribute('aria-labelledby', 'instruction-legend-title');
  const legendTitle = element('strong', '', 'Reading the instruction listing'); legendTitle.id = 'instruction-legend-title';
  legend.append(legendTitle, element('p', '', 'The listing reads the selected node’s memory. Addresses and encoded bits are hexadecimal.'), element('p', '', 'Each instruction word contains two slots: :0 is the first instruction, :1 is the second. Literal constants use the whole word.'), element('p', '', 'Source line links visit the corresponding C code, when available.'));
  const legendToggle = button('?', 'Explain instruction columns', undefined, 'instruction-legend-toggle');
  legendToggle.setAttribute('popovertarget', legend.id); controls.append(legendToggle);
  table.append(headers, listing);
  const help = element('div', 'instruction-help'); help.setAttribute('role', 'tooltip'); help.id = 'instruction-help';
  root.append(controls, status, table, help, legend);
  let debug, selected, groups = new Map(), current, lastKey, explanation = 'Hover or focus an instruction to learn what it does.';
  const visible = new Set(), viewport = new IntersectionObserver(entries => {
    for (const entry of entries) {
      const group = groups.get(Number(entry.target.dataset.wordAddress));
      if (!group || group.element !== entry.target) continue;
      if (entry.isIntersecting) visible.add(group); else visible.delete(group);
    }
    render();
  }, { root: listing });
  const showHelp = text => { help.textContent = text; };
  const update = group => {
    const word = ide.simulator.peek(ide.selectedNode, group.address);
    if (group.word === word) return;
    group.word = word;
    group.element.replaceChildren(...decodeWord(word).map(instruction => {
      const row = element('div', 'instruction-row'); row.tabIndex = 0;
      row.setAttribute('role', 'row');
      row.dataset.address = hexAddress(group.address); row.dataset.phase = instruction.phase;
      row.dataset.focusKey = `${group.address}:${instruction.phase}`;
      row.title = `${instruction.explanation}${group.source?.annotation ? `\nCompiler: ${group.source.annotation}` : ''}`;
      row.setAttribute('aria-describedby', help.id);
      row.onmouseenter = row.onfocus = () => showHelp(row.title);
      row.onmouseleave = row.onblur = () => showHelp(explanation);
      const encoded = (word >> 34n) === 3n ? Number((word >> (instruction.phase ? 0n : 17n)) & 0x1ffffn).toString(16).padStart(5, '0') : word.toString(16).padStart(9, '0');
      row.append(element('span', 'instruction-marker'), element('span', 'instruction-address', `${hexAddress(group.address)}:${instruction.phase}`), element('span', 'instruction-encoding', encoded), element('span', 'instruction-code', instruction.text));
      const source = element('span', 'instruction-source');
      if (group.source?.line) source.append(button(`L${group.source.line}`, `Visit source line ${group.source.line}`, () => ide.perform(() => ide.reveal(ide.compiledPath, group.source.line, group.source.column)), 'text-button'));
      row.append(source);
      for (const cell of row.children) cell.setAttribute('role', 'cell');
      return row;
    }));
  };
  const add = address => {
    if (groups.has(address)) return groups.get(address);
    const group = { address, source: debug.info.words.get(address), element: element('div', 'instruction-word') };
    group.element.dataset.wordAddress = address;
    groups.set(address, group); update(group); viewport.observe(group.element); return group;
  };
  const render = observe(ide, ['machine', 'state', 'buffers', 'files'], () => {
    for (const { control, command } of steps) syncCommandButton(control, ide, command);
    syncCommandButton(run, ide, 'continue', { label: true });
    if (root.hidden || !root.isConnected) return;
    const state = ide.debug?.snapshot?.nodes[ide.selectedNode];
    if (!state) { status.textContent = 'Compile & Run a C buffer to see its MDP instructions.'; listing.replaceChildren(); showHelp(explanation); return; }
    const address = instructionAddress(state), phase = ipPhase(state.ip), key = `${ide.selectedNode}:${address}:${phase}`;
    if (debug !== ide.debug || selected !== ide.selectedNode) {
      viewport.disconnect(); visible.clear();
      debug = ide.debug; selected = ide.selectedNode; groups = new Map(); current = null; lastKey = null;
      // Source annotations identify code; instruction words and their adjacent
      // literals are read from this node, including remotely fetched code.
      const addresses = [...debug.info.words.values()].filter(entry => entry.address >= 0x1000).map(entry => entry.address);
      listing.replaceChildren(...addresses.sort((a, b) => a - b).map(a => add(a).element));
    }
    if (!groups.has(address)) {
      for (let a = Math.max(0, address - 8); a <= Math.min(0xfffff, address + 8); a++) add(a);
      listing.replaceChildren(...[...groups.values()].sort((a, b) => a.address - b.address).map(group => group.element));
    }
    for (const group of new Set([...visible, groups.get(address)])) update(group);
    if (current) { current.classList.remove('next'); current.removeAttribute('aria-current'); current.querySelector('.instruction-marker').textContent = ''; }
    current = groups.get(address).element.children[phase] ?? groups.get(address).element.firstElementChild;
    current.classList.add('next'); current.setAttribute('aria-current', 'step'); current.querySelector('.instruction-marker').textContent = '▶';
    explanation = current.title;
    if (!listing.contains(document.activeElement) && !listing.matches(':hover')) showHelp(explanation);
    table.ariaLabel = `Node ${selected} MDP instructions in memory`;
    status.textContent = `NODE ${selected} MEMORY · ${state.background ? 'BACKGROUND' : `PRIORITY ${state.priority}`} · ${state.retired.toLocaleString()} retired · ${state.atFetch ? 'Next' : 'Pending fetch'} ${hexAddress(address)}:${phase}${state.atFetch ? '' : ' (instruction in progress; target may change)'}`;
    if (key !== lastKey) { current.scrollIntoView({ block: 'center', inline: 'nearest' }); lastKey = key; }
  });
  return { element: root, render, focus: () => current ? current.focus() : steps[0].control.focus() };
}
