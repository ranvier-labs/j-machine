export const hexAddress = value => value.toString(16).padStart(5, '0');
export function element(tag, className, text) {
  const node = document.createElement(tag); if (className) node.className = className;
  if (text !== undefined) node.textContent = text; return node;
}
export function button(label, title, run, className = '') {
  const node = element('button', className, label); node.type = 'button'; node.title = title; node.ariaLabel = title; node.onclick = run; return node;
}
export function syncCommandButton(node, ide, id, { label = false } = {}) {
  const state = ide.commandState(id); node.disabled = !state.enabled;
  if (label && state.label) node.textContent = state.label;
  const name = node.textContent.trim(), detail = state.reason || state.detail;
  const title = detail ? detail.toLowerCase().startsWith(name.toLowerCase()) ? detail : `${name}: ${detail}` : state.label || node.title;
  node.title = node.ariaLabel = `${title}${state.keys?.length ? ` (${state.keys.join(' / ')})` : ''}`;
  return state;
}
export function observe(ide, types, update) {
  const render = () => {
    const active = document.activeElement, frame = active?.closest?.('[data-window]');
    const identity = active?.dataset?.focusKey, label = active?.getAttribute?.('aria-label');
    update();
    if (frame?.isConnected && !active.isConnected) {
      const replacement = [...frame.querySelectorAll('button,input,select,[tabindex],summary')].find(e => identity ? e.dataset.focusKey === identity : label && e.getAttribute('aria-label') === label);
      replacement?.focus({ preventScroll: true });
    }
  };
  let pending = false, frame, timer;
  const flush = () => { if (!pending) return; pending = false; cancelAnimationFrame(frame); clearTimeout(timer); render(); };
  ide.on(types, () => {
    if (pending) return; pending = true;
    frame = requestAnimationFrame(flush);
    // Background tabs may suspend animation frames while a build is still
    // completing. Keep their listener and accessible state current as well.
    timer = setTimeout(flush, 50);
  });
  return render;
}
export function canvasContext(canvas) {
  const { width, height } = canvas.getBoundingClientRect();
  if (width < 1 || height < 1) return null;
  const scale = Math.min(devicePixelRatio || 1, 2), w = Math.round(width * scale), h = Math.round(height * scale);
  if (canvas.width !== w || canvas.height !== h) { canvas.width = w; canvas.height = h; }
  const ctx = canvas.getContext('2d'); ctx.setTransform(scale, 0, 0, scale, 0, 0); ctx.clearRect(0, 0, width, height);
  return { ctx, width, height };
}
export function parseAddress(value) {
  if (!/^(?:0x)?[0-9a-f]{1,5}$/i.test(value.trim())) throw new Error('Enter a hexadecimal address from 00000 to fffff.');
  return parseInt(value.replace(/^0x/i, ''), 16);
}
