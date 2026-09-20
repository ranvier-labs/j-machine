import { element, observe } from './common.js';
import { presentationHelp } from '../core/presentations.js';

export function listenerWindow(ide) {
  const root = element('div', 'listener-window');
  const log = element('div', 'listener-log'); log.setAttribute('role', 'log'); log.ariaLabel = 'Listener output';
  const form = element('form', 'listener-prompt'), prompt = element('label', '', '~/ >'), input = element('input');
  input.id = 'listener-input'; prompt.htmlFor = input.id; input.ariaLabel = 'Listener command'; input.placeholder = 'help'; input.autocomplete = 'off'; input.spellcheck = false;
  const mouseHelp = element('div', 'listener-mouse-help', 'Enter / click: visit · Shift+Enter / Shift-click: insert · Escape: prompt');
  form.append(prompt, input); root.append(log, mouseHelp, form); const history = []; let index = 0, draft = '';
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
  }); render();
  return { id: 'listener', title: 'LISTENER', element: root, onFocus: () => input.focus(), insert: (value, replace = false) => {
    if (replace) input.value = value;
    else { const start = input.selectionStart, end = input.selectionEnd; input.setRangeText(`${start && !/\s/.test(input.value[start - 1]) ? ' ' : ''}${value}`, start, end, 'end'); }
    input.focus();
  } };
}
