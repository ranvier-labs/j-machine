// Some embedding browsers (the Claude Code preview pane, remote-control
// bridges) inject trusted keyboard events whose `key` is set but whose
// `code` is empty and `keyCode` is 0. The desktop's own dispatch reads
// `event.key` and works; Monaco's keybinding resolver and the browser's
// built-in actions (closing a dialog on Escape, submitting a form on Enter,
// activating a button on Space) work from the key code and do nothing. This
// module repairs such events: it stops the degraded event, re-dispatches one
// with `code` and `keyCode` filled in, and performs the missing defaults.
const NAMED = { Escape: 27, Enter: 13, Tab: 9, Backspace: 8, Delete: 46, Insert: 45, ArrowLeft: 37, ArrowUp: 38, ArrowRight: 39, ArrowDown: 40,
  Home: 36, End: 35, PageUp: 33, PageDown: 34, ' ': 32, CapsLock: 20, Shift: 16, Control: 17, Alt: 18, Meta: 91, ContextMenu: 93, Pause: 19, ScrollLock: 145, NumLock: 144 };
const PUNCTUATION = { ';': 186, ':': 186, '=': 187, '+': 187, ',': 188, '<': 188, '-': 189, '_': 189, '.': 190, '>': 190, '/': 191, '?': 191, '`': 192, '~': 192,
  '[': 219, '{': 219, '\\': 220, '|': 220, ']': 221, '}': 221, "'": 222, '"': 222 };
const SHIFTED_DIGITS = ')!@#$%^&*(';

export function keyCodeFor(key) {
  if (key in NAMED) return NAMED[key];
  const fn = key.match(/^F(\d{1,2})$/); if (fn && fn[1] >= 1 && fn[1] <= 24) return 111 + Number(fn[1]);
  if (key.length !== 1) return 0;
  if (/[a-z]/i.test(key)) return key.toUpperCase().charCodeAt(0);
  if (/\d/.test(key)) return key.charCodeAt(0);
  const shifted = SHIFTED_DIGITS.indexOf(key); if (shifted >= 0) return 48 + shifted;
  return PUNCTUATION[key] ?? 0;
}
export function codeFor(key) {
  if (key === ' ') return 'Space';
  if (key.length === 1) return /[a-z]/i.test(key) ? `Key${key.toUpperCase()}` : /\d/.test(key) ? `Digit${key}` : '';
  return key;
}
export const isDegraded = event => event.keyCode === 0 && event.which === 0 && typeof event.key === 'string' && event.key.length > 0 && !event.isComposing;

// Emulates the browser default the synthetic event cannot trigger itself.
function performDefault(event, target) {
  if (event.type !== 'keydown' || event.defaultPrevented || event.metaKey || event.ctrlKey || event.altKey) return;
  if (event.key === 'Escape') {
    const dialog = [...document.querySelectorAll('dialog[open]')].at(-1);
    if (dialog) { const cancel = new Event('cancel', { cancelable: true }); if (dialog.dispatchEvent(cancel)) dialog.close(); }
  } else if (event.key === 'Enter' && target instanceof HTMLInputElement && target.form && !['button', 'submit', 'checkbox', 'radio'].includes(target.type)) {
    target.form.requestSubmit();
  } else if ((event.key === 'Enter' || event.key === ' ') && target instanceof HTMLElement && target.matches('button, summary, a[href], [role=option]')) {
    target.click();
  }
}

export function repairKeyEvent(event) {
  if (!isDegraded(event)) return false;
  const keyCode = keyCodeFor(event.key); if (!keyCode) return false;
  event.stopImmediatePropagation(); event.preventDefault();
  const repaired = new KeyboardEvent(event.type, { key: event.key, code: event.code || codeFor(event.key), keyCode, which: keyCode, location: event.location,
    metaKey: event.metaKey, ctrlKey: event.ctrlKey, altKey: event.altKey, shiftKey: event.shiftKey, repeat: event.repeat, bubbles: true, cancelable: true, composed: true });
  const target = event.target ?? document.activeElement ?? document.body;
  target.dispatchEvent(repaired);
  performDefault(repaired, target);
  return true;
}

// Registers before any other keyboard listener so the desktop, Monaco, and
// dialogs all observe the repaired event exactly once.
export function installKeyRepair(root = document) {
  for (const type of ['keydown', 'keyup']) root.addEventListener(type, repairKeyEvent, true);
}
