import { element, button, observe } from './common.js';
import { CHAPTERS, STEPS, openLessonWorkspace } from '../tutorial/steps.js';
import { renderMarkdown, ideLink } from '../documentation/markdown.js';

export function tutorialWindow(ide) {
  const root = element('div', 'tutorial-window'), strip = element('div', 'tool-strip'), counter = element('strong'), hint = element('span');
  const title = element('h3', 'tutorial-title'), body = element('div', 'documentation-page tutorial-body');
  const observation = element('p', 'tutorial-observation'), done = element('span', 'tutorial-done'); done.setAttribute('role', 'status');
  const link = ideLink(ide), session = ide.fs.data.session, legacy = ['run', 'edit', 'debug', 'remote', 'packets', 'contention', 'project', 'graphics', 'life', 'heat', 'mesh', 'files', 'desktop'];
  const savedId = session.tutorialStepId ?? (session.tutorialStep > 0 ? legacy[session.tutorialStep] : null);
  let index = Math.max(0, STEPS.findIndex(step => step.id === savedId)), busy = false, renderedStep, tourIndex = 0, active = false;
  const step = () => STEPS[index];
  const reading = element('dialog', 'tutorial-reading'); reading.setAttribute('aria-labelledby', 'lesson-title');
  const sheet = element('div', 'tutorial-sheet'), readingHeader = element('div', 'tutorial-reading-header');
  const logo = element('img', 'tutorial-logo'); logo.src = './assets/j-machine-logo.png'; logo.alt = 'J-Machine'; logo.width = 240; logo.height = 135;
  const readingTitle = element('h2'); readingTitle.id = 'lesson-title';
  const readingBody = element('div', 'documentation-page tutorial-reading-body'), readingActions = element('div', 'tutorial-reading-actions');
  const tour = element('dialog', 'tutorial-tour'); tour.setAttribute('aria-labelledby', 'tour-title');
  const spotlight = element('div', 'tutorial-spotlight'), caption = element('section', 'tutorial-tour-caption');
  const tourCount = element('p', 'tutorial-tour-count'), tourTitle = element('h2'), tourBody = element('p'), tourActions = element('div', 'tutorial-actions'); tourTitle.id = 'tour-title';
  const areas = [
    { selector: '[data-window=editor]', title: 'Your source editor', text: 'Read and edit Message-Driven C here. Tabs are buffers; the modeline reports the file and problems. A gutter click sets a source breakpoint.' },
    { selector: '[data-window=listener]', tab: 'listener', title: 'Listener', text: 'The Listener accepts IDE commands and records results. Try help after this tour. Its name comes from the interactive Listener of Lisp-machine environments; these commands control this IDE.' },
    { selector: '[data-window=listener]', tab: 'instructions', title: 'Compiled instructions', text: 'This tab displays the selected node’s actual memory decoded as MDP instructions. The arrow marks its next fetch. Hover a row for an explanation; use ? to understand the columns.' },
    { selector: '[data-window=listener]', tab: 'debugger', title: 'Debugger', text: 'Inspect registers and memory, manage breakpoints, and choose a node. Listener, Instructions, and Debugger share this panel beneath the editor. Switching tabs preserves the machine state.' },
    { selector: '[data-window=machine]', title: 'The machine', text: 'Each cell is a node. Click one to inspect its instructions and state. Inspection can change while all nodes keep running. Activity measures instruction retirement, not useful work.' },
    { selector: '.workbench-header', title: 'Compile, load, and run', text: 'Compile & Load prepares the current buffer. Run starts execution. For projects use Build, Load, then Run. A workspace button only opens tools: you operate them.' },
    { selector: '[data-window=tutorial]', title: 'Your chapter guide', text: 'Lesson text remains here while you work. Click it to reopen the full reading view. Back and Next in the page footer move between lessons; Lesson in the top bar lets you jump between chapters. Exit tutorial is at the top right. Finishing this tour leaves you on this lesson.' },
  ];
  const header = document.querySelector('.workbench-header'), footer = document.querySelector('.minibuffer');
  const menu = document.getElementById('tutorial-lesson'), lessonLabel = document.getElementById('tutorial-lesson-label');
  const exit = document.getElementById('tutorial-exit'), navigation = document.getElementById('tutorial-navigation');
  menu.onclick = () => ide.services.choose(CHAPTERS.flatMap(chapter => STEPS.filter(item => item.chapter === chapter.id).map(item => ({
    label: `${STEPS.indexOf(item) + 1}. ${item.title}`, group: chapter.title, detail: item === step() ? 'Current lesson' : '',
    run: () => go(STEPS.indexOf(item)),
  }))), { title: 'Lessons', label: 'Find a lesson', placeholder: 'Search lessons or chapters…', verb: 'Read lesson', help: 'quick-start' });
  // Keep the page bars interactive in the native modal's top layer.
  const syncChrome = () => {
    const modal = tour.open ? tour : reading.open ? reading : null;
    if (modal) modal.append(header, footer);
    else { document.body.prepend(header); document.body.append(footer); }
  };
  reading.addEventListener('close', syncChrome); tour.addEventListener('close', syncChrome);
  const finish = () => {
    reading.close(); tour.close(); active = false; index = 0; syncChrome();
    ide.fs.setSession({ tutorialDone: true, tutorialStep: 0, tutorialStepId: STEPS[0].id });
    ide.services.layout('development'); render();
  };
  const nextStep = () => index === STEPS.length - 1 ? finish() : go(index + 1);
  const showReading = () => {
    if (busy) return;
    ide.pause(); tour.close(); render(); readingBody.scrollTop = 0;
    if (!reading.open) reading.showModal(); syncChrome();
    readingBody.focus({ preventScroll: true });
  };
  const openWorkspace = () => ide.perform(async () => {
    busy = true; render();
    try {
      await openLessonWorkspace(ide, step()); reading.close(); syncChrome();
      if (step().id === 'environment') { tourIndex = 0; tour.showModal(); syncChrome(); showArea(); }
    } finally { busy = false; render(); }
  });
  body.tabIndex = 0; body.setAttribute('role', 'region'); body.ariaLabel = 'Lesson text'; body.title = 'Click or press Enter to read lesson';
  body.onclick = event => { if (!event.target.closest('a,button')) showReading(); };
  body.onkeydown = event => { if (event.target === body && ['Enter', ' '].includes(event.key)) { event.preventDefault(); showReading(); } };
  title.onclick = showReading;
  const back = button('← Back', 'Previous lesson', () => go(index - 1));
  const next = button('Next →', 'Next lesson', nextStep, 'primary');
  exit.onclick = finish; navigation.append(back, next);
  const readingPrimary = button('Next', 'Next lesson', () => step().workspace ? openWorkspace() : nextStep(), 'primary');
  const close = button('×', 'Close lesson', () => reading.close());
  readingBody.tabIndex = -1;
  const readingControls = element('div', 'tutorial-reading-controls'); readingControls.append(close);
  readingHeader.append(logo, readingControls); readingActions.append(readingPrimary);
  sheet.append(readingHeader, readingTitle, readingBody, readingActions); reading.append(sheet);
  const tourBack = button('← Back', 'Previous area', () => { tourIndex--; showArea(); });
  const tourNext = button('Next area →', 'Next area', () => {
    if (tourIndex === areas.length - 1) { tour.close(); syncChrome(); ide.fs.setSession({ tutorialTourDone: true }); ide.services.selectTool('instructions'); render(); }
    else { tourIndex++; showArea(); }
  }, 'primary');
  tourActions.append(tourBack, tourNext, button('Close tour', 'Close tour', () => tour.close()));
  caption.append(tourCount, tourTitle, tourBody, tourActions); tour.append(spotlight, caption); document.body.append(reading, tour);
  function positionArea() {
    if (!tour.open) return;
    const target = document.querySelector(areas[tourIndex].selector); if (!target) return;
    const rect = target.getBoundingClientRect(), gap = 12;
    Object.assign(spotlight.style, { left: `${rect.left}px`, top: `${rect.top}px`, width: `${rect.width}px`, height: `${rect.height}px` });
    const width = Math.min(380, innerWidth - gap * 2); caption.style.width = `${width}px`;
    const height = caption.offsetHeight, below = rect.bottom + gap, above = rect.top - height - gap;
    const top = below + height < innerHeight - gap ? below : above >= gap ? above : Math.max(gap, (innerHeight - height) / 2);
    const left = rect.right + width + gap < innerWidth ? rect.right + gap : rect.left - width - gap >= gap ? rect.left - width - gap : Math.min(innerWidth - width - gap, Math.max(gap, rect.left));
    Object.assign(caption.style, { left: `${left}px`, top: `${top}px` });
  }
  function showArea() {
    const area = areas[tourIndex]; if (area.tab) ide.services.selectTool(area.tab);
    tour.dataset.area = String(tourIndex); tourCount.textContent = `AREA ${tourIndex + 1} OF ${areas.length}`;
    tourTitle.textContent = area.title; tourBody.textContent = area.text; tourBack.disabled = tourIndex === 0;
    tourNext.textContent = tourIndex === areas.length - 1 ? 'Finish tour' : 'Next area →';
    requestAnimationFrame(positionArea); tourNext.focus();
  }
  window.addEventListener('resize', positionArea);
  strip.append(counter, hint, done);
  root.append(strip, title, body, observation);
  const go = target => {
    if (busy) return;
    active = true;
    index = Math.max(0, Math.min(STEPS.length - 1, target)); ide.fs.setSession({ tutorialStep: index, tutorialStepId: step().id });
    ide.services.applyLayout(step().layout());
    ide.services.openWindow('tutorial'); body.scrollTop = 0; showReading();
  };
  const render = observe(ide, ['machine', 'state', 'network', 'files', 'buffers', 'build'], () => {
    const current = step(); root.dataset.step = current.id;
    counter.textContent = `LESSON ${index + 1} OF ${STEPS.length}`; title.textContent = readingTitle.textContent = current.title;
    const chapter = CHAPTERS.find(item => item.id === current.chapter), chapterSteps = STEPS.filter(item => item.chapter === current.chapter);
    hint.textContent = `${chapter.title} · ${chapterSteps.indexOf(current) + 1}/${chapterSteps.length}`;
    menu.textContent = `Lesson ${index + 1}: ${current.title} ▾`; menu.title = chapter.title; menu.disabled = busy;
    lessonLabel.hidden = exit.hidden = navigation.hidden = !active;
    document.body.classList.toggle('tutorial-active', active);
    document.body.dataset.tutorialProject = String(active && !!current.workspace?.project);
    document.body.dataset.tutorialDesktop = String(active && current.id === 'desktop');
    if (renderedStep !== current) {
      for (const container of [body, readingBody]) { container.replaceChildren(); renderMarkdown(container, current.text, { link }); }
      renderedStep = current;
    }
    observation.textContent = current.observe?.(ide) ?? ''; observation.hidden = !observation.textContent;
    body.setAttribute('aria-disabled', String(busy));
    const primaryLabel = busy ? 'Opening…' : current.id === 'environment' ? 'Start guided tour' : current.workspace ? 'Open workspace' : 'Next lesson →';
    readingPrimary.textContent = readingPrimary.title = readingPrimary.ariaLabel = primaryLabel; readingPrimary.disabled = busy;
    const complete = !busy && (current.id === 'environment' ? !!ide.fs.data.session.tutorialTourDone : !!current.done?.(ide));
    done.textContent = complete ? '✓ Done' : ''; back.disabled = busy || index === 0;
    next.disabled = exit.disabled = busy;
  }); render();
  return { id: 'tutorial', title: 'TUTORIAL', element: root, onFocus: () => body.focus(), start: () => go(index), get step() { return index; } };
}
