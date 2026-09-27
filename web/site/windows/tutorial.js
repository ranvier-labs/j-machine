import { element, button, observe } from './common.js';
import { STEPS } from '../tutorial/steps.js';
import { renderMarkdown, ideLink } from '../documentation/markdown.js';

export function tutorialWindow(ide) {
  const root = element('div', 'tutorial-window'), strip = element('div', 'tool-strip'), counter = element('strong'), hint = element('span', '', 'Do it performs the step; Next continues');
  const title = element('h3', 'tutorial-title'), body = element('div', 'documentation-page tutorial-body'), actions = element('div', 'tutorial-actions');
  const link = ideLink(ide);
  strip.append(counter, hint);
  let index = Math.max(0, Math.min(STEPS.length - 1, ide.fs.data.session.tutorialStep ?? 0)), busy = false;
  const step = () => STEPS[index];
  const doIt = button('Do it', 'Perform this step', () => ide.perform(async () => {
    busy = true; render();
    try { await step().action.run(ide); } finally { busy = false; render(); }
  }), 'primary');
  const done = element('span', 'tutorial-done'); done.setAttribute('role', 'status');
  // Finishing or leaving the tour always returns to the development desktop
  // and forgets the step, so the next visit starts from the beginning.
  const finish = () => { ide.fs.setSession({ tutorialDone: true, tutorialStep: 0 }); index = 0; ide.services.layout('development'); };
  const back = button('← Back', 'Previous step', () => go(index - 1));
  const next = button('Next →', 'Next step', () => index === STEPS.length - 1 ? finish() : go(index + 1));
  const exit = button('Exit', 'Leave the tutorial and show the development layout', finish);
  actions.append(doIt, back, next, exit, done);
  root.append(strip, title, body, actions);
  const go = (target, { arrange = true } = {}) => {
    index = Math.max(0, Math.min(STEPS.length - 1, target)); ide.fs.setSession({ tutorialStep: index });
    if (arrange) ide.services.applyLayout(step().layout());
    render(); ide.services.openWindow('tutorial');
  };
  const render = observe(ide, ['machine', 'state', 'network', 'files', 'buffers', 'build'], () => {
    const current = step();
    counter.textContent = `STEP ${index + 1} OF ${STEPS.length}`; title.textContent = current.title;
    body.replaceChildren(); renderMarkdown(body, current.text, { link });
    doIt.textContent = busy ? 'Working…' : current.action.label; doIt.title = doIt.ariaLabel = current.action.label; doIt.disabled = busy;
    const complete = !busy && !!current.done?.(ide);
    done.textContent = complete ? '✓ Done' : ''; back.disabled = index === 0;
    next.textContent = index === STEPS.length - 1 ? 'Finish' : 'Next →'; next.classList.toggle('primary', complete);
  }); render();
  return { id: 'tutorial', title: 'TUTORIAL', element: root, onFocus: () => doIt.focus(), start: () => go(index), get step() { return index; } };
}
