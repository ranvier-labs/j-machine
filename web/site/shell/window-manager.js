import { TileLayout, leaves, restoreLayout, tilePositions } from './layout.js';
import './window-manager.css';

// A window contributes only an element and lifecycle hooks. This module knows
// nothing about files, editors, compilers, or machine state.
export class WindowManager {
  constructor(element, { storage, key = 'jmc.tiles.v2', legacyKey = 'jmc.tiles.v1', aliases = {}, onChange = () => {}, onSplit = () => {} } = {}) {
    this.element = element; this.storage = storage; this.key = key; this.legacyKey = legacyKey; this.aliases = aliases;
    this.onChange = onChange; this.onSplit = onSplit;
    this.registry = new Map(); this.frames = new Map(); this.lastFocus = new Map(); this.layout = new TileLayout();
    this.element.addEventListener('focusin', event => {
      const frame = event.target.closest?.('[data-window]');
      if (frame) { this.lastFocus.set(frame.dataset.window, event.target); this.focus(frame.dataset.window, false); }
    });
    this.element.addEventListener('pointerdown', event => {
      const frame = event.target.closest?.('[data-window]');
      if (frame) this.focus(frame.dataset.window, false);
    });
  }
  register(window) {
    if (!window.id || this.registry.has(window.id)) throw new Error(`Duplicate window: ${window.id}`);
    this.registry.set(window.id, window);
  }
  restore(fallback) {
    let saved;
    try { saved = JSON.parse(this.storage?.getItem(this.key) ?? (this.legacyKey ? this.storage?.getItem(this.legacyKey) : null)); } catch { /* Use the supplied layout. */ }
    const tree = saved?.version === 1 && saved.tree === null ? null : restoreLayout(saved?.tree, [...this.registry.keys()], this.aliases) ?? fallback;
    this.layout = new TileLayout(tree);
    const focused = this.aliases[saved?.focused] ?? saved?.focused;
    if (leaves(this.layout.tree).includes(focused)) this.layout.focused = focused;
    this.render();
  }
  save() {
    try { this.storage?.setItem(this.key, JSON.stringify({ version: 1, tree: this.layout.tree, focused: this.layout.focused })); }
    catch { /* Layout remains usable when browser storage is unavailable. */ }
    this.onChange(this.layout);
  }
  setLayout(tree) { this.layout = new TileLayout(restoreLayout(tree, [...this.registry.keys()])); this.render(); }
  open(id, options) { if (!this.registry.has(id)) throw new Error(`Unknown window: ${id}`); this.layout.open(id, options); this.render(); this.focus(id); }
  close(id) { this.layout.close(id); this.registry.get(id)?.onHide?.(); this.render(); this.focus(this.layout.focused); }
  move(id, target, edge) { this.layout.move(id, target, edge); this.render(); this.focus(id); }
  zoom(id) { this.layout.zoom(id); this.render(); this.focus(this.layout.focused); }
  cycle(direction) { this.layout.cycle(direction); this.render(); this.focus(this.layout.focused); }
  visible(id) { return leaves(this.layout.tree).includes(id); }
  focus(id, keyboard = true) {
    if (!this.visible(id)) return;
    this.layout.focused = id;
    for (const [key, frame] of this.frames) frame.classList.toggle('focused', key === id);
    this.save();
    if (keyboard) {
      const last = this.lastFocus.get(id);
      if (last?.isConnected && !last.disabled && !last.closest('[hidden]')) last.focus();
      else if (this.registry.get(id)?.onFocus) this.registry.get(id).onFocus();
      else this.frame(id).querySelector('button,input,select,[tabindex="0"]')?.focus();
    }
  }
  resize(axis, delta) { this.layout.resizeFocused(axis, delta); this.render(); this.focus(this.layout.focused); }
  focusDirection(direction) {
    const positions=tilePositions(this.layout.tree), current=positions.get(this.layout.focused);if(!current)return;
    const x = current.x + current.width / 2, y = current.y + current.height / 2;
    const axis = ['left','right'].includes(direction) ? 'x' : 'y', sign = ['left','up'].includes(direction) ? -1 : 1;
    const candidates = [...positions].filter(([id]) => id !== this.layout.focused).map(([id,r]) => {
      const dx = r.x + r.width/2 - x, dy = r.y + r.height/2 - y;
      return { id, primary: (axis === 'x' ? dx : dy) * sign, secondary: Math.abs(axis === 'x' ? dy : dx) };
    }).filter(c => c.primary > .001).sort((a,b) => a.primary + a.secondary*2 - b.primary - b.secondary*2);
    if (candidates[0]) { if (this.layout.zoomed) this.layout.zoomed = candidates[0].id; this.render(); this.focus(candidates[0].id); }
  }
  frame(id) {
    if (this.frames.has(id)) return this.frames.get(id);
    const window = this.registry.get(id);
    const frame = document.createElement('section'); frame.className = 'tile-frame'; frame.dataset.window = id;
    frame.setAttribute('aria-label', `${window.title} window`);
    const header = document.createElement('header'); header.className = 'tile-header'; header.draggable = true;
    const title = document.createElement('button'); title.className = 'tile-title'; title.textContent = window.title;
    title.onclick = () => this.focus(id); title.ondblclick = () => this.zoom(id);
    header.append(title);
    const actions = [
      ['↔', 'Split right', () => this.onSplit(id, 'right')], ['↕', 'Split below', () => this.onSplit(id, 'bottom')],
      ['□', 'Zoom / restore', () => this.zoom(id)], ['×', 'Close', () => this.close(id)],
    ];
    for (const [label, action, run] of actions) {
      const button = document.createElement('button'); button.className = 'tile-action'; button.textContent = label;
      button.title = `${action} ${window.title}`; button.ariaLabel = button.title;
      button.onclick = event => { event.stopPropagation(); run(); }; header.append(button);
    }
    header.addEventListener('dragstart', event => { this.dragged = id; event.dataTransfer.effectAllowed = 'move'; event.dataTransfer.setData('text/plain', id); });
    header.addEventListener('dragend', () => { this.dragged = null; for (const f of this.frames.values()) delete f.dataset.drop; });
    const dropEdge = event => {
      const box = frame.getBoundingClientRect(), x = (event.clientX - box.left) / box.width, y = (event.clientY - box.top) / box.height;
      return [[x, 'left'], [1 - x, 'right'], [y, 'top'], [1 - y, 'bottom']].sort((a, b) => a[0] - b[0])[0][1];
    };
    frame.addEventListener('dragover', event => {
      if (!this.dragged || this.dragged === id) return;
      event.preventDefault(); frame.dataset.drop = dropEdge(event);
    });
    frame.addEventListener('dragleave', event => { if (!frame.contains(event.relatedTarget)) delete frame.dataset.drop; });
    frame.addEventListener('drop', event => {
      if (!this.dragged) return;
      event.preventDefault(); const source = this.dragged; this.dragged = null;
      delete frame.dataset.drop; this.move(source, id, dropEdge(event));
    });
    window.element.classList.add('tile-content'); frame.append(header, window.element);
    this.frames.set(id, frame); return frame;
  }
  render() {
    const active = this.element.contains(document.activeElement) ? document.activeElement : null;
    const shown = this.layout.zoomed ? [this.layout.zoomed] : leaves(this.layout.tree);
    const build = node => {
      if (node.type === 'leaf') return this.frame(node.id);
      const container = document.createElement('div'); container.className = `tile-split axis-${node.axis}`;
      const size = () => {
        container.style[node.axis === 'x' ? 'gridTemplateColumns' : 'gridTemplateRows'] = `minmax(0, ${node.ratio}fr) 6px minmax(0, ${1 - node.ratio}fr)`;
      }; size();
      const divider = document.createElement('div'); divider.className = 'tile-divider'; divider.tabIndex = 0;
      divider.setAttribute('role', 'separator'); divider.setAttribute('aria-label', 'Resize tiled windows');
      divider.setAttribute('aria-orientation', node.axis === 'x' ? 'vertical' : 'horizontal');
      divider.setAttribute('aria-valuemin', '12'); divider.setAttribute('aria-valuemax', '88');
      divider.setAttribute('aria-valuenow', String(Math.round(node.ratio * 100)));
      const update = ratio => { node.ratio = Math.max(.12, Math.min(.88, ratio)); this.layout.resize(node.id, node.ratio); size(); divider.setAttribute('aria-valuenow', String(Math.round(node.ratio * 100))); this.resized(); };
      divider.addEventListener('pointerdown', event => {
        if (event.button !== 0) return;
        event.preventDefault(); divider.setPointerCapture(event.pointerId); const box = container.getBoundingClientRect();
        const move = e => update(node.axis === 'x' ? (e.clientX - box.left) / box.width : (e.clientY - box.top) / box.height);
        const done = () => { divider.removeEventListener('pointermove', move); this.save(); };
        divider.addEventListener('pointermove', move); divider.addEventListener('pointerup', done, { once: true }); divider.addEventListener('pointercancel', done, { once: true });
      });
      divider.addEventListener('keydown', event => {
        if (!['ArrowLeft', 'ArrowRight', 'ArrowUp', 'ArrowDown', 'Home'].includes(event.key)) return;
        event.preventDefault(); update(event.key === 'Home' ? .5 : node.ratio + (['ArrowLeft', 'ArrowUp'].includes(event.key) ? -.03 : .03)); this.save();
      });
      container.append(build(node.first), divider, build(node.second)); return container;
    };
    for (const [id, window] of this.registry) window.element.hidden = !shown.includes(id);
    this.element.replaceChildren();
    if (this.layout.zoomed) this.element.append(this.frame(this.layout.zoomed));
    else if (this.layout.tree) this.element.append(build(this.layout.tree));
    else { const empty = document.createElement('p'); empty.className = 'desktop-empty'; empty.textContent = 'No windows. Use Windows or M-x to open a tool.'; this.element.append(empty); }
    for (const [id, frame] of this.frames) frame.classList.toggle('focused', id === this.layout.focused);
    this.save(); if (active?.isConnected && !active.closest('[hidden]')) active.focus({ preventScroll: true });
    requestAnimationFrame(() => this.resized());
  }
  resized() { for (const id of this.layout.zoomed ? [this.layout.zoomed] : leaves(this.layout.tree)) this.registry.get(id)?.onResize?.(); }
}
