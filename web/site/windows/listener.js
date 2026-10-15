import { element, observe } from './common.js';
import { presentationHelp } from '../core/presentations.js';
import { instructionsPanel } from './instructions.js';
import { debuggerWindow } from './debugger.js';

export function listenerWindow(ide) {
  const root = element('div', 'listener-window'), tabs = element('div', 'inspection-tabs'), terminal = element('div', 'listener-terminal');
  tabs.setAttribute('role', 'tablist'); tabs.ariaLabel = 'IDE tools';
  const instructions = instructionsPanel(ide), debuggerTool = debuggerWindow(ide);
  const instructionTab = buttonTab('Instructions', 'instructions'), listenerTab = buttonTab('Listener', 'listener'), debuggerTab = buttonTab('Debugger', 'debugger');
  const tools = [['listener', listenerTab, terminal], ['instructions', instructionTab, instructions.element], ['debugger', debuggerTab, debuggerTool.element]];
  function buttonTab(label, id) {
    const tab = element('button', '', label); tab.type = 'button'; tab.id = `inspection-tab-${id}`; tab.setAttribute('role', 'tab');
    tab.setAttribute('aria-controls', `inspection-panel-${id}`); tab.onclick = () => selectTab(id); return tab;
  }
  let active = ide.fs.data.session.inspectionTab ?? (ide.fs.data.session.tutorialDone ? 'listener' : 'instructions');
  const selectTab = (id, { focus = true } = {}) => {
    active = tools.some(([name]) => name === id) ? id : 'listener'; ide.fs.setSession({ inspectionTab: active });
    for (const [id, tab, panel] of tools) {
      tab.setAttribute('aria-selected', String(active === id)); tab.tabIndex = active === id ? 0 : -1; panel.hidden = active !== id;
    }
    if (active === 'instructions') instructions.render();
    if (focus) (active === 'listener' ? input : tools.find(([id]) => id === active)[1]).focus();
  };
  tabs.onkeydown = event => {
    if (!['ArrowLeft', 'ArrowRight', 'Home', 'End'].includes(event.key)) return;
    event.preventDefault();
    const index = tools.findIndex(([id]) => id === active), next = event.key === 'Home' ? 0 : event.key === 'End' ? tools.length - 1 : (index + (event.key === 'ArrowRight' ? 1 : -1) + tools.length) % tools.length;
    selectTab(tools[next][0], { focus: false }); tools[next][1].focus();
  };
  for (const [id, tab, panel] of tools) {
    panel.id = `inspection-panel-${id}`; panel.setAttribute('role', 'tabpanel'); panel.setAttribute('aria-labelledby', tab.id);
  }
  tabs.append(...tools.map(([, tab]) => tab)); root.append(tabs, ...tools.map(([, , panel]) => panel));
  const log = element('div', 'listener-log'); log.setAttribute('role', 'log'); log.ariaLabel = 'Listener output';
  const form = element('form', 'listener-prompt'), prompt = element('label', '', '~/ >'), input = element('input');
  input.id = 'listener-input'; prompt.htmlFor = input.id; input.ariaLabel = 'Listener command'; input.placeholder = 'help'; input.autocomplete = 'off'; input.spellcheck = false;
  const mouseHelp = element('div', 'listener-mouse-help', 'Enter / click: visit · Shift+Enter / Shift-click: insert · Escape: prompt');
  form.append(prompt, input); terminal.append(log, mouseHelp, form); const history = []; let index = 0, draft = '';
  form.onsubmit = event => {
    event.preventDefault(); const command = input.value; if (!command.trim()) return;
    history.push(command); index = history.length; input.value = ''; draft = ''; ide.command(command);
  };
  input.onkeydown = event => {
    if (event.altKey || !['ArrowUp', 'ArrowDown'].includes(event.key)) return;
    event.preventDefault(); if (index === history.length) draft = input.value;
    index = Math.max(0, Math.min(history.length, index + (event.key === 'ArrowUp' ? -1 : 1)));
    input.value = index === history.length ? draft : history[index]; input.setSelectionRange(input.value.length, input.value.length);
  };
  log.addEventListener('keydown', event => {
    const entries = [...log.querySelectorAll('.presentation')], index = entries.indexOf(document.activeElement);
    if (event.key === 'Escape') { event.preventDefault(); input.focus(); }
    else if (event.key === 'Enter' && event.shiftKey && index >= 0) { event.preventDefault(); entries[index].dispatchEvent(new MouseEvent('click', { shiftKey: true, bubbles: true })); }
    else if (['ArrowUp','ArrowDown','ArrowLeft','ArrowRight','Home','End'].includes(event.key) && index >= 0) {
      event.preventDefault(); const next = event.key === 'Home' ? 0 : event.key === 'End' ? entries.length - 1 : Math.max(0,Math.min(entries.length - 1,index + (['ArrowDown','ArrowRight'].includes(event.key) ? 1 : -1))); entries[next].focus();
    }
  });
  input.addEventListener('keydown', event => {
    if (event.altKey && event.key === 'ArrowUp') { event.preventDefault(); [...log.querySelectorAll('.presentation')].at(-1)?.focus(); }
  });
  const render = observe(ide, ['log', 'cwd'], () => {
    const atEnd = log.scrollHeight - log.scrollTop - log.clientHeight < 45;
    log.replaceChildren(...ide.logs.map(entry => {
      const row = element('div', `listener-entry ${entry.kind}`), cycle = element('span', 'log-cycle', entry.cycle), text = element('pre');
      for (const part of entry.parts) {
        if (typeof part === 'string') text.append(document.createTextNode(part));
        else {
          const presentation = element('button', 'presentation', part.text); presentation.type = 'button';
          presentation.title = presentationHelp(part); presentation.ariaLabel = presentation.title;
          presentation.onclick = event => ide.perform(() => ide.selectPresentation(part, event.shiftKey)); text.append(presentation);
        }
      }
      row.append(cycle, text); return row;
    }));
    prompt.textContent = `${ide.cwd.replace(/^\/home\/user(?=\/|$)/, '~')}>`; prompt.title = ide.cwd;
    if (atEnd && !log.contains(document.activeElement)) log.scrollTop = log.scrollHeight;
  }); render(); selectTab(active, { focus: false });
  return { id: 'listener', title: 'TOOLS', element: root, selectTab, get activeTab() { return active; }, onResize: instructions.render, onFocus: () => active === 'instructions' ? instructions.focus() : active === 'debugger' ? debuggerTool.onFocus() : input.focus(), insert: (value, replace = false) => {
    selectTab('listener');
    if (replace) input.value = value;
    else { const start = input.selectionStart, end = input.selectionEnd; input.setRangeText(`${start && !/\s/.test(input.value[start - 1]) ? ' ' : ''}${value}`, start, end, 'end'); }
    input.focus();
  } };
}
