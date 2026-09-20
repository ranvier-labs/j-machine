export function keyName(event) {
  const parts = [];
  if (event.ctrlKey) parts.push('Ctrl');
  if (event.metaKey) parts.push('Meta');
  if (event.altKey) parts.push('Alt');
  if (event.shiftKey) parts.push('Shift');
  const key = event.altKey && /^Key[A-Z]$/.test(event.code ?? '') ? event.code.slice(3).toLowerCase() : event.key.length === 1 ? event.key.toLowerCase() : event.key;
  return [...parts, key].join('+');
}
export function matchesKey(binding, event) {
  const key = keyName(event), variants = binding.includes('Mod') ? [binding.replace('Mod', 'Ctrl'), binding.replace('Mod', 'Meta')] : [binding];
  return variants.some(value => value.split('+').sort().join('+') === key.split('+').sort().join('+'));
}
export class CommandRegistry {
  constructor({ execute = action => action() } = {}) { this.commands = new Map(); this.overrides = {}; this.execute = execute; }
  register(command) { if (this.commands.has(command.id)) throw new Error(`Duplicate command: ${command.id}`); this.commands.set(command.id, command); }
  state(id) {
    const c = this.commands.get(id); if (!c) throw new Error(`Unknown command: ${id}`);
    const state = { label: c.label, detail: typeof c.detail === 'function' ? c.detail() : c.detail ?? '', enabled: true, reason: '', ...c.state?.() };
    if (c.enabled && !c.enabled()) { state.enabled = false; state.reason ||= c.disabledReason ?? `${state.label} is unavailable in this state.`; }
    return { ...state, keys: this.keys(c) };
  }
  run(id, ...args) {
    const c = this.commands.get(id); if (!c) throw new Error(`Unknown command: ${id}`);
    return this.execute(() => { const state = this.state(id); if (!state.enabled) throw new Error(state.reason); return c.run(...args); });
  }
  keys(command) { return this.overrides[command.id] ?? command.keys ?? []; }
  entries(scope, { menu, allScopes = false } = {}) {
    return [...this.commands.values()].filter(c => (!menu || c.menu === menu) && (allScopes || !c.scope || c.scope === scope)).map(c => {
      const state = this.state(c.id);
      return { id: c.id, label: state.label, group: c.group, help: c.help, enabled: state.enabled,
        state: () => this.state(c.id), detail: [state.detail, this.keys(c).join(' / '), c.id, state.reason].filter(Boolean).join(' · '), run: () => this.run(c.id) };
    });
  }
  keymap() { return JSON.stringify({ version: 1, bindings: Object.fromEntries([...this.commands.values()].map(c => [c.id, this.keys(c)])) }, null, 2); }
  loadKeymap(text) {
    const value = JSON.parse(text);
    if (value.version !== 1 || !value.bindings || Array.isArray(value.bindings) || typeof value.bindings !== 'object') throw new Error('Keymap needs version 1 and a bindings object.');
    const next = {};
    for (const [id, bindings] of Object.entries(value.bindings)) {
      if (!this.commands.has(id)) throw new Error(`Unknown keymap command: ${id}`);
      if (!Array.isArray(bindings) || bindings.some(key => typeof key !== 'string' || !key.length || key.length > 80)) throw new Error(`Invalid key binding for ${id}.`);
      next[id] = bindings;
    }
    const used = new Map();
    for (const c of this.commands.values()) for (const key of next[c.id] ?? c.keys ?? []) {
      for (const expanded of key.includes('Mod') ? [key.replace('Mod','Ctrl'),key.replace('Mod','Meta')] : [key]) {
        const canonical = `${c.scope ?? '*'}:${expanded.split('+').sort().join('+')}`;
        if (used.has(canonical)) throw new Error(`Key ${key} is assigned to both ${used.get(canonical)} and ${c.id}.`);
        used.set(canonical,c.id);
      }
    }
    this.overrides = next;
  }
  handle(event, scope) {
    if (event.isComposing || event.defaultPrevented) return false;
    const candidates = [...this.commands.values()].filter(c => !c.scope || c.scope === scope).sort((a,b) => Number(!!b.scope)-Number(!!a.scope));
    const command = candidates.find(c => this.keys(c).some(key => matchesKey(key,event)));
    if (!command) return false;
    event.preventDefault(); this.run(command.id); return true;
  }
}
