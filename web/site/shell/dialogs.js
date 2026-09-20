export function download(name, content, type = 'text/plain') {
  const url = URL.createObjectURL(new Blob([content], { type })), anchor = document.createElement('a');
  anchor.href = url; anchor.download = name; anchor.click(); setTimeout(() => URL.revokeObjectURL(url), 1000);
}

export function requestPath({ title, value, label = 'Pathname', submit = 'Create', run }) {
  const previousFocus = document.activeElement;
  const dialog = document.createElement('dialog'); dialog.className = 'path-dialog';
  dialog.innerHTML = '<form><h2></h2><label><span></span><input required autocomplete="off" spellcheck="false"></label><p class="dialog-error" role="alert"></p><div class="dialog-actions"><button type="button">Cancel</button><button class="primary" type="submit"></button></div></form>';
  dialog.querySelector('h2').textContent = title; dialog.querySelector('label span').textContent = label;
  const input = dialog.querySelector('input'); input.value = value;
  dialog.querySelector('[type=submit]').textContent = submit;
  dialog.querySelector('[type=button]').onclick = () => dialog.close();
  dialog.querySelector('form').onsubmit = async event => {
    event.preventDefault();
    try { await run(input.value); dialog.close(); }
    catch (error) { dialog.querySelector('.dialog-error').textContent = error.message; }
  };
  dialog.addEventListener('close', () => { dialog.remove(); if (document.activeElement === document.body && previousFocus?.isConnected) previousFocus.focus(); }); document.body.append(dialog); dialog.showModal(); input.focus(); input.select();
}

export class CommandPalette {
  constructor() {
    this.dialog = document.createElement('dialog'); this.dialog.className = 'command-palette';
    this.dialog.innerHTML = '<form><label><b></b><span></span><input role="combobox" aria-expanded="true" aria-controls="palette-options" aria-autocomplete="list" autocomplete="off" spellcheck="false"></label></form><div id="palette-options" class="palette-results" role="listbox"></div><p></p>';
    document.body.append(this.dialog); this.input = this.dialog.querySelector('input'); this.list = this.dialog.querySelector('.palette-results');
    this.dialog.addEventListener('cancel', () => { const previous = this.previousFocus; queueMicrotask(() => previous?.isConnected && previous.focus()); });
    this.input.oninput = () => { this.selected = 0; this.render(); };
    this.dialog.querySelector('form').onsubmit = event => { event.preventDefault(); this.execute(); };
    this.input.onkeydown = event => {
      if (event.key === 'F1' && this.onHelp) { event.preventDefault(); const topic = this.results[this.selected]?.help ?? this.help; this.dialog.close(); this.onHelp(topic); return; }
      if (!['ArrowDown', 'ArrowUp', 'PageDown', 'PageUp'].includes(event.key)) return;
      event.preventDefault(); this.selected = Math.max(0, Math.min(this.results.length - 1, this.selected + ({ArrowDown:1, ArrowUp:-1, PageDown:10, PageUp:-10})[event.key])); this.renderSelection();
    };
  }
  open(entries, { value = '', fallback, title = 'Commands', label = 'Command or file', placeholder = 'Type a command or pathname…', verb = 'Execute', shortcut = '', help = 'keyboard' } = {}) {
    if (!this.dialog.open) this.previousFocus = document.activeElement;
    this.entries = entries; this.fallback = fallback; this.selected = 0; this.input.value = value;
    this.help = help; this.title = title;
    this.dialog.setAttribute('aria-label', title); this.dialog.querySelector('b').textContent = title;
    this.dialog.querySelector('label > span').textContent = shortcut;
    this.input.ariaLabel = label; this.input.placeholder = placeholder; this.list.ariaLabel = title;
    this.dialog.querySelector('p').textContent = `↑ ↓ Select · Return ${verb} · Escape Cancel · F1 Help`;
    this.render(); if (!this.dialog.open) this.dialog.showModal(); this.input.focus();
  }
  execute(index = this.selected) {
    const entry = this.results[index], state = entry?.state?.(), action = entry?.run, input = this.input.value;
    if (entry && (state?.enabled ?? entry.enabled) === false) { this.render(); return; }
    if (!action && !this.fallback) return;
    this.dialog.close(); if (this.previousFocus?.isConnected) this.previousFocus.focus({ preventScroll: true });
    if (action) action(); else this.fallback(input);
  }
  render() {
    const words = this.input.value.toLowerCase().trim().split(/\s+/);
    const entries = this.entries.map(entry => {
      const state = entry.state?.();
      return state ? { ...entry, label: state.label, enabled: state.enabled, detail: [state.detail, state.keys?.join(' / '), entry.id, state.reason].filter(Boolean).join(' · ') } : entry;
    });
    const groups = new Map();
    for (const entry of entries.filter(entry => words.every(word => `${entry.label} ${entry.detail ?? ''} ${entry.group ?? ''}`.toLowerCase().includes(word)))) {
      if (!groups.has(entry.group)) groups.set(entry.group, []); groups.get(entry.group).push(entry);
    }
    this.results = [...groups.values()].flat(); this.selected = Math.max(0, Math.min(this.selected, this.results.length - 1));
    let previousGroup;
    this.list.replaceChildren(...this.results.flatMap((entry, index) => {
      const state = entry.state?.(), button = document.createElement('button'); button.type = 'button'; button.setAttribute('role', 'option'); button.id = `palette-option-${index}`; button.tabIndex = -1;
      button.setAttribute('aria-disabled', String((state?.enabled ?? entry.enabled) === false));
      const label = document.createElement('span'), detail = document.createElement('small'); label.textContent = entry.label; detail.textContent = entry.detail ?? '';
      if (state?.reason && !detail.textContent.includes(state.reason)) detail.textContent += ` · ${state.reason}`;
      button.append(label, detail); button.onmousedown = event => event.preventDefault();
      button.onclick = () => { this.selected = index; this.execute(index); };
      if (entry.group && entry.group !== previousGroup) { previousGroup = entry.group; const heading = document.createElement('div'); heading.className = 'palette-group'; heading.setAttribute('role', 'presentation'); heading.textContent = entry.group; return [heading, button]; }
      return [button];
    }));
    if (!this.results.length) { const text = document.createElement('div'); text.className = 'empty-state'; text.textContent = this.fallback ? 'Return sends this command to the listener.' : 'No matching entries.'; this.list.append(text); }
    this.renderSelection();
  }
  renderSelection() {
    if (this.results[this.selected]) this.input.setAttribute('aria-activedescendant', `palette-option-${this.selected}`); else this.input.removeAttribute('aria-activedescendant');
    [...this.list.querySelectorAll('button')].forEach((button, index) => { button.setAttribute('aria-selected', String(index === this.selected)); if (index === this.selected) button.scrollIntoView({ block: 'nearest' }); });
  }
}
