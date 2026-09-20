import { ipAddress, ipPhase } from '../debugger.js';
import { wordHex, describeWord } from '../runtime.js';
import { basename } from '../core/filesystem.js';
import { element, button, observe, hexAddress, parseAddress, syncCommandButton } from './common.js';

export function debuggerWindow(ide) {
  const root = element('div', 'debugger-window'), controls = element('div', 'debug-toolbar');
  const run = button('Run', 'Run loaded image (F5)', () => ide.perform(() => ide.execute()), 'run-toggle');
  const source = button('Source', 'Step to the next source line (F11)', () => ide.perform(() => ide.execute('source')));
  const instruction = button('Instruction', 'Step one instruction (F10)', () => ide.perform(() => ide.execute('instruction')));
  const cycle = button('Cycle', 'Step one machine cycle', () => ide.perform(() => ide.execute('cycles')));
  const hundred = button('+100', 'Step one hundred machine cycles', () => ide.perform(() => ide.execute('cycles', 100)));
  const reset = button('Reset', 'Reset the loaded machine image', () => ide.perform(() => ide.reset()));
  const restart = button('Restart', 'Reset and run the loaded machine image', () => ide.perform(() => ide.restart())); controls.append(run, restart, source, instruction, cycle, hundred, reset);
  const loaded = element('button', 'loaded-source text-button'); loaded.onclick = () => ide.perform(() => ide.openFile(ide.compiledPath, { adoptTarget: false }));
  const status = element('div', 'debug-status'), tag = element('span', 'state-tag', 'BOOT'), reason = element('span', '', 'Build and load a project image, or compile a C buffer.'); status.append(tag, reason);
  const scroll = element('div', 'debug-scroll'), options = element('div', 'debug-options'), nodeLabel = element('label', '', 'NODE '), node = element('select'); node.ariaLabel = 'Inspect machine node'; nodeLabel.append(node);
  node.onchange = () => ide.perform(() => ide.selectNode(Number(node.value)));
  const faultLabel = element('label'), fault = element('input'); fault.type = 'checkbox'; fault.onchange = () => { ide.breakOnFault = fault.checked; if (ide.debug) ide.debug.breakOnFault = fault.checked; }; faultLabel.append(fault, document.createTextNode(' Break on handled faults')); options.append(nodeLabel, faultLabel);
  const budgetLabel = element('label', '', 'Cycle budget '), budget = element('input'); budget.type='number';budget.min='1';budget.max='100000000';budget.value='10000000';budget.ariaLabel='Execution cycle budget';budget.style.width='100px';
  budget.onchange=()=>ide.perform(()=>{const n=Number(budget.value);if(!Number.isSafeInteger(n)||n<1||n>100000000)throw new Error('Cycle budget must be between 1 and 100,000,000.');if(ide.debug)ide.debug.maxCycles=n;});budgetLabel.append(budget);options.append(budgetLabel);
  const context = element('div', 'subheading'), registers = element('div', 'registers');
  const breakpointSection = element('section', 'debug-section'), breakpointHeader = element('div', 'subheading'), breakpointLabel = element('span', '', 'SOURCE BREAKPOINTS');
  breakpointHeader.append(breakpointLabel, button('+ Cursor', 'Toggle breakpoint at editor cursor (F9)', () => ide.perform(() => ide.toggleBreakpoint(ide.editor.editor.getPosition()?.lineNumber))));
  const breakpoints = element('ul', 'compact-list'), addressForm = element('form', 'inline-form'), address = element('input'), addAddress = element('button', '', '+ IP');
  address.placeholder = 'Instruction address, hex'; address.ariaLabel = 'Instruction breakpoint address in hex'; address.maxLength = 7; addressForm.append(address, addAddress);
  addressForm.onsubmit = event => { event.preventDefault(); ide.perform(() => {
    if (!ide.debug) throw new Error('Load a machine first.');
    ide.addressBreakpoints.push({ address: parseAddress(address.value), node: ide.selectedNode }); ide.bindBreakpoints(); address.value = ''; render();
  }); };
  breakpointSection.append(breakpointHeader, breakpoints, addressForm);
  const memorySection = element('section', 'debug-section'), memoryHeader = element('div', 'subheading', 'MEMORY / SELECTED NODE'), memoryForm = element('form', 'inline-form');
  const memoryAddress = element('input'); memoryAddress.value = '00300'; memoryAddress.ariaLabel = 'Memory address in hex'; memoryAddress.maxLength = 7;
  const read = element('button', '', 'Read'), watch = button('Watch', 'Break when this memory word changes', () => ide.perform(() => { ide.debug.addWatchpoint(ide.selectedNode, parseAddress(memoryAddress.value)); render(); }));
  const memoryValue = element('div', 'peek-result'), raw = element('strong', '', '—'), decoded = element('span'), watches = element('ul', 'compact-list'); memoryValue.append(raw, decoded); memoryForm.append(memoryAddress, read, watch);
  const readMemory = () => { if (!ide.debug) return; const value = ide.simulator.peek(ide.selectedNode, parseAddress(memoryAddress.value)); raw.textContent = wordHex(value); decoded.textContent = describeWord(value); };
  memoryForm.onsubmit = event => { event.preventDefault(); ide.perform(readMemory); };
  memorySection.append(memoryHeader, memoryForm, memoryValue, watches);
  const columns = element('div', 'debug-columns'); columns.append(breakpointSection, memorySection); scroll.append(options, context, registers, columns);
  root.append(controls, loaded, status, scroll);
  let nodeCount = 0;
  const render = observe(ide, ['machine', 'state', 'buffers', 'files'], () => {
    const debug = ide.debug, running = !!debug?.running, snapshot = debug?.snapshot;
    syncCommandButton(run,ide,'continue',{label:true});
    run.classList.toggle('running', running);
    for (const [control,command] of [[source,'step-source'],[instruction,'step-instruction'],[cycle,'step-cycle'],[hundred,'step-100'],[reset,'reset'],[restart,'restart']]) syncCommandButton(control,ide,command);
    for (const control of [read, watch, addAddress, node]) control.disabled = !debug || running || ide.busy;
    loaded.textContent = ide.compiledPath ? `${ide.simulator.nodes} NODES · ${ide.compiledPath}${ide.stale ? ' · SOURCE CHANGED' : ''}` : 'No image loaded'; loaded.disabled = !ide.compiledPath || !ide.fs.exists(ide.compiledPath);
    loaded.classList.toggle('error-text', ide.stale);
    tag.textContent = ide.busy ? 'BUSY' : running ? 'RUN' : ide.loadFailure ? 'LOAD FAILED' : ide.stale ? 'STALE' : debug?.stopReason.type.toUpperCase() ?? 'BOOT';
    reason.textContent = running ? `Executing · node ${ide.selectedNode} · Pause to stop` : ide.machineReason() || debug?.stopReason.message || 'Build and load a project image, or compile a C buffer.';
    if (snapshot) {
      if (nodeCount !== ide.simulator.nodes) { nodeCount = ide.simulator.nodes; node.replaceChildren(...Array.from({ length: nodeCount }, (_, i) => new Option(String(i), String(i)))); }
      node.value = String(ide.selectedNode); const current = snapshot.nodes[ide.selectedNode], previous = ide.previous?.nodes[ide.selectedNode];
      context.replaceChildren(element('span', '', current.catastrophe ? 'CATASTROPHE' : current.faultMode ? `FAULT ${current.fault}` : current.background ? 'BACKGROUND' : `PRIORITY ${current.priority}`), element('span', '', `IP ${hexAddress(ipAddress(current.ip))}:${ipPhase(current.ip)} / ${current.atFetch ? 'FETCH' : 'EXEC'}`));
      registers.replaceChildren(...current.registers.map((word, i) => {
        const item = element('div', 'register'), value = element('strong', '', wordHex(word).slice(2)); value.title = describeWord(word); value.classList.toggle('changed', !!previous?.registers && previous.registers[i] !== word);
        item.append(element('span', '', i < 4 ? `R${i}` : `A${i - 4}`), value); return item;
      }));
      if (!running && /^(?:0x)?[0-9a-f]{1,5}$/i.test(memoryAddress.value.trim())) readMemory();
    }
    breakpointLabel.textContent = `BREAKPOINTS · ${ide.activePath ? basename(ide.activePath) : 'NO BUFFER'}`;
    breakpoints.replaceChildren(...ide.breakpoints().map(bp => {
      const row = element('li'), bound = ide.activePath === ide.compiledPath && !ide.stale && debug?.info.entries.has(bp.line);
      row.append(button(`L${bp.line} · ${bound ? 'bound' : 'pending'}`, `Reveal breakpoint on line ${bp.line}`, () => ide.perform(() => ide.reveal(ide.activePath, bp.line)), 'text-button'), button('×', `Remove source breakpoint on line ${bp.line}`, () => ide.perform(() => ide.toggleBreakpoint(bp.line)), 'text-button')); return row;
    }));
    for (const bp of ide.addressBreakpoints) {
      const row = element('li'); row.append(element('span', '', `N${bp.node} IP ${hexAddress(bp.address)}`), button('×', 'Remove instruction breakpoint', () => { ide.addressBreakpoints = ide.addressBreakpoints.filter(item => item !== bp); ide.bindBreakpoints(); render(); }, 'text-button')); breakpoints.append(row);
    }
    if (!breakpoints.children.length) breakpoints.append(element('li', 'empty-state', 'Click the editor gutter or press F9.'));
    watches.replaceChildren(...[...(debug?.watchpoints.values() ?? [])].map(item => {
      const row = element('li'), value = ide.simulator.peek(item.node, item.address);
      row.append(element('span', '', `N${item.node}:${hexAddress(item.address)} ${describeWord(value)}`), button('×', 'Remove memory watch', () => { debug.watchpoints.delete(item.id); render(); }, 'text-button')); return row;
    }));
    if (!watches.children.length) watches.append(element('li', 'empty-state', 'No memory watches.'));
  }); render();
  return { id: 'debugger', title: 'DEBUGGER', element: root, onFocus: () => run.focus() };
}
