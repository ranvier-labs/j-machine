import { test, expect } from '@playwright/test';
import { CHAPTERS, STEPS } from '../../site/tutorial/steps.js';
import { FILESYSTEM_KEY } from '../../site/core/filesystem.js';

async function fresh(page) {
  await page.goto('/'); await page.evaluate(() => localStorage.clear()); await page.goto('/');
  await expect(page.locator('#status-text')).toHaveText(/Loaded/, { timeout: 60_000 });
  await expect(page.locator('.tutorial-reading')).toBeVisible();
}

async function chooseLesson(page, id) {
  await page.getByRole('button', { name: 'Tutorial lesson', exact: true }).click();
  const catalog = page.getByRole('dialog', { name: 'Lessons', exact: true });
  await catalog.getByRole('combobox', { name: 'Find a lesson', exact: true }).fill(STEPS.find(lesson => lesson.id === id).title);
  await page.keyboard.press('Enter');
  await expect(catalog).toBeHidden();
}

test('lesson reading, logo, manual workspace, shared tools, and explicit Next', async ({ page }) => {
  await page.setViewportSize({ width: 1280, height: 720 });
  await fresh(page);
  const reading = page.locator('.tutorial-reading'), guide = page.locator('[data-window=tutorial]');
  await page.getByRole('button', { name: 'Tutorial lesson', exact: true }).click();
  const catalog = page.getByRole('dialog', { name: 'Lessons', exact: true });
  await expect(catalog.locator('.palette-group')).toHaveCount(CHAPTERS.length);
  await expect(catalog.getByRole('option')).toHaveCount(STEPS.length);
  await expect(page.locator('#tutorial-lesson')).toHaveJSProperty('tagName', 'BUTTON');
  await page.keyboard.press('Escape');
  await expect(reading).toBeVisible();
  await expect(reading.locator('.tutorial-logo')).toBeVisible();
  await expect(page.locator('#tutorial-exit')).toBeVisible();
  await expect(page.locator('.workbench-header > #tutorial-exit')).toHaveCount(1);
  await expect(page.locator('#tutorial-navigation .primary')).toHaveText('Next →');
  await expect(reading.getByRole('button', { name: 'Close lesson', exact: true })).toHaveText('×');
  await expect(page.locator('.tutorial-window')).not.toContainText('STEP');
  expect(await reading.locator('.tutorial-logo').evaluate(img => img.complete && img.naturalWidth > 0)).toBe(true);
  expect(await reading.locator('.tutorial-reading-body').evaluate(el => el.scrollHeight > el.clientHeight)).toBe(true);
  await page.keyboard.press('F5');
  await expect(page.locator('.machine-result-value')).toHaveText('not returned yet');
  await chooseLesson(page, 'edit');
  await reading.getByRole('button', { name: 'Open workspace', exact: true }).click();
  await expect(reading).toBeHidden();
  for (const id of ['new-file', 'find-file', 'examples-menu', 'save-buffer', 'node-count', 'build-project', 'load-project', 'restart-machine', 'window-menu', 'layout-menu', 'tutorial-menu', 'command-menu']) await expect(page.locator(`#${id}`)).toBeHidden();
  for (const id of ['compile-buffer', 'run-machine', 'help-menu', 'tutorial-exit', 'tutorial-lesson']) await expect(page.locator(`#${id}`)).toBeVisible();
  await expect(page.locator('.source-editor')).toContainText('factorial(6)');
  await expect(page.locator('.machine-result-value')).toHaveText('not returned yet');
  for (const name of ['Listener', 'Instructions', 'Debugger']) {
    const tab = page.getByRole('tab', { name, exact: true }); await tab.click();
    await expect(tab).toHaveAttribute('aria-selected', 'true');
    await expect(page.locator(`#inspection-panel-${name.toLowerCase()}`)).toBeVisible();
    await expect(page.locator('[data-window=debugger]')).toHaveCount(0);
  }
  const editor = await page.locator('[data-window=editor]').boundingBox(), tools = await page.locator('[data-window=listener]').boundingBox();
  const tutorial = await guide.boundingBox(), machine = await page.locator('[data-window=machine]').boundingBox();
  expect(tutorial.x + tutorial.width).toBeLessThanOrEqual(editor.x);
  expect(Math.abs(tutorial.y - editor.y)).toBeLessThan(2);
  expect(Math.abs(tutorial.y + tutorial.height - tools.y - tools.height)).toBeLessThan(2);
  expect(tools.y).toBeGreaterThanOrEqual(editor.y + editor.height);
  expect(tools.width).toBeLessThan(editor.width);
  expect(Math.abs(machine.y - tools.y)).toBeLessThan(2);
  expect(machine.x).toBeGreaterThanOrEqual(tools.x + tools.width);
  expect(Math.abs(machine.x + machine.width - editor.x - editor.width)).toBeLessThan(2);
  const result = await page.locator('.machine-result-value').boundingBox();
  expect(result.y + result.height).toBeLessThanOrEqual(machine.y + machine.height);
  await page.locator('#tutorial-navigation').getByRole('button', { name: 'Next lesson', exact: true }).click();
  await expect(reading).toBeVisible(); await expect(reading.locator('h2')).toHaveText('Stop and step');
  await reading.getByRole('button', { name: 'Open workspace', exact: true }).click();
  await expect(page.getByRole('tab', { name: 'Debugger', exact: true })).toHaveAttribute('aria-selected', 'true');
  await expect(page.locator('#tutorial-navigation button')).toHaveText(['← Back', 'Next →']);
  await expect(page.locator('.workbench-header').getByRole('button', { name: 'Exit tutorial', exact: true })).toBeVisible();
  await guide.locator('.tutorial-body p').first().click();
  await expect(reading).toBeVisible();
  await reading.getByRole('button', { name: 'Close lesson', exact: true }).click();
  await guide.getByRole('region', { name: 'Lesson text', exact: true }).focus();
  await page.keyboard.press('Enter');
  await expect(reading).toBeVisible();
});

test('reading-only lessons always offer Next lesson and the pane exits at the top', async ({ page }) => {
  await fresh(page);
  const reading = page.locator('.tutorial-reading'), guide = page.locator('[data-window=tutorial]');
  for (const step of STEPS.filter(step => !step.workspace)) {
    await chooseLesson(page, step.id);
    await expect(reading.locator('.tutorial-reading-actions .primary')).toHaveText('Next lesson →');
  }
  await reading.getByRole('button', { name: 'Next lesson →', exact: true }).click();
  await expect(reading).toBeHidden(); await expect(guide).toHaveCount(0);
  await page.locator('#tutorial-menu').click();
  await reading.getByRole('button', { name: 'Close lesson', exact: true }).click();
  await expect(page.locator('#tutorial-navigation button')).toHaveText(['← Back', 'Next →']);
  await page.locator('.workbench-header').getByRole('button', { name: 'Exit tutorial', exact: true }).click();
  await expect(guide).toHaveCount(0);
});

test('tutorial header reveals project controls only when needed and restores the IDE on exit', async ({ page }) => {
  await fresh(page);
  const reading = page.locator('.tutorial-reading');
  await chooseLesson(page, 'project');
  await reading.getByRole('button', { name: 'Open workspace', exact: true }).click();
  for (const id of ['build-project', 'load-project', 'run-machine', 'help-menu']) await expect(page.locator(`#${id}`)).toBeVisible();
  await expect(page.locator('#compile-buffer')).toBeHidden();
  await page.locator('.tutorial-body p').first().click();
  await expect(reading).toBeVisible();
  await page.locator('.workbench-header > #tutorial-exit').click();
  await expect(reading).toBeHidden();
  await expect(page.locator('#tutorial-navigation')).toBeHidden();
  await expect(page.locator('#tutorial-lesson')).toBeHidden();
  for (const id of ['new-file', 'examples-menu', 'node-count', 'window-menu', 'layout-menu', 'command-menu']) await expect(page.locator(`#${id}`)).toBeVisible();
});

test('guided IDE tour spotlights each area and leaves explicit progression', async ({ page }) => {
  await fresh(page);
  const reading = page.locator('.tutorial-reading');
  await reading.getByRole('button', { name: 'Next lesson →', exact: true }).click();
  await expect(reading.locator('h2')).toHaveText('Look around the desktop');
  await reading.getByRole('button', { name: 'Start guided tour', exact: true }).click();
  const tour = page.locator('.tutorial-tour');
  for (let i = 0; i < 7; i++) {
    await expect(tour).toHaveAttribute('data-area', String(i));
    await expect(tour.locator('.tutorial-spotlight')).toBeVisible();
    await expect(tour.locator('h2')).not.toBeEmpty();
    await tour.getByRole('button', { name: 'Next area', exact: true }).click();
  }
  await expect(tour).toBeHidden();
  await expect(page.locator('.tutorial-window')).toHaveAttribute('data-step', 'environment');
  await expect(page.locator('.tutorial-done')).toHaveText('✓ Done');
  await page.locator('#tutorial-navigation').getByRole('button', { name: 'Next lesson', exact: true }).click();
  await expect(reading.locator('h2')).toHaveText('Choose what to inspect');
});

test('chapter jumps and reloads preserve the lesson without running it', async ({ page }) => {
  await fresh(page);
  const reading = page.locator('.tutorial-reading');
  await chooseLesson(page, 'futures');
  await page.reload();
  await expect(reading).toBeVisible(); await expect(reading.locator('h2')).toHaveText('Wait when you need a future');
  await expect(page.locator('.machine-result-value')).toHaveText('not returned yet');
  await page.locator('#tutorial-navigation').getByRole('button', { name: 'Previous lesson', exact: true }).click();
  await expect(reading.locator('h2')).toHaveText('Sending does not mean finished');
  await page.evaluate(key => {
    const data = JSON.parse(localStorage.getItem(key));
    data.session.tutorialStep = 3; delete data.session.tutorialStepId;
    localStorage.setItem(key, JSON.stringify(data));
  }, FILESYSTEM_KEY);
  await page.reload();
  await expect(reading.locator('h2')).toHaveText('Request, handler, and reply');
});

test('instructions follow the inspected node, explain opcodes, and support all three steps', async ({ page }) => {
  await page.goto('/'); await page.evaluate(() => localStorage.clear()); await page.goto('/');
  await expect(page.locator('#status-text')).toHaveText(/Loaded/, { timeout: 60_000 });
  await page.getByRole('button', { name: 'Close lesson', exact: true }).click();
  const instructions = page.locator('#inspection-panel-instructions');
  await expect(instructions).toBeVisible();
  await expect(instructions.getByRole('columnheader', { name: 'Word : slot' })).toBeVisible();
  await expect(instructions.getByRole('columnheader', { name: 'Hex bits' })).toBeVisible();
  await expect(instructions.getByRole('columnheader', { name: 'MDP instruction' })).toBeVisible();
  await expect(instructions.getByRole('columnheader', { name: 'Source line', exact: true })).toBeVisible();
  await expect(instructions.locator('.instruction-encoding').first()).toHaveCSS('text-align', 'right');
  const legend = instructions.getByRole('dialog', { name: 'Reading the instruction listing' });
  await expect(legend).toBeHidden();
  await instructions.getByRole('button', { name: 'Explain instruction columns' }).click();
  await expect(legend).toBeVisible();
  await expect(legend).toContainText(':0 is the first instruction');
  await page.keyboard.press('Escape');
  await expect(legend).toBeHidden();
  const next = instructions.locator('.instruction-row.next');
  await expect(next).toHaveCount(1);
  await next.hover();
  await expect(instructions.locator('.instruction-help')).not.toBeEmpty();
  await expect(next).toHaveAttribute('title', /.+/);
  await instructions.getByRole('button', { name: /^Clock cycle:/ }).click();
  await expect(page.locator('#status-text')).toHaveText('Advanced 1 cycle.');
  await instructions.getByRole('button', { name: /^Instruction:/ }).click();
  await expect(page.locator('#status-text')).toHaveText(/Instruction retired/);
  await instructions.getByRole('button', { name: /^Source line:/ }).click();
  await expect(page.locator('#status-text')).toHaveText(/Source step/);
  const machine = page.locator('[data-window=machine] canvas');
  const bounds = await machine.boundingBox();
  await machine.click({ position: { x: bounds.width * .75, y: bounds.height / 2 } });
  await expect(instructions.locator('.instruction-status')).toContainText('NODE 1');
  await expect(instructions.getByRole('table')).toHaveAttribute('aria-label', 'Node 1 MDP instructions in memory');
  await expect(next).toHaveCount(1);
  await page.getByRole('tab', { name: 'Listener', exact: true }).click();
  await page.locator('#listener-input').fill('window instructions'); await page.locator('#listener-input').press('Enter');
  await expect(instructions).toBeVisible();
});

test('node inspection switches while execution continues', async ({ page }) => {
  await page.goto('/'); await page.evaluate(() => localStorage.clear()); await page.goto('/');
  await expect(page.locator('#status-text')).toHaveText(/Loaded/, { timeout: 60_000 });
  await page.getByRole('button', { name: 'Close lesson', exact: true }).click();
  await page.locator('.source-editor .view-lines').click();
  await page.keyboard.press(process.platform === 'darwin' ? 'Meta+a' : 'Control+a');
  await page.keyboard.insertText('int main(void) { while (1) {} return 0; }');
  await page.locator('#compile-buffer').click();
  await expect(page.locator('#status-text')).toHaveText(/Loaded/);
  await page.getByRole('tab', { name: 'Listener', exact: true }).click();
  await page.locator('#listener-input').fill('window debugger'); await page.locator('#listener-input').press('Enter');
  await page.getByRole('spinbutton', { name: 'Execution cycle budget' }).fill('100000000');
  await page.getByRole('spinbutton', { name: 'Execution cycle budget' }).press('Tab');
  await page.getByRole('tab', { name: 'Instructions', exact: true }).click();
  await page.locator('#run-machine').click();
  await expect(page.locator('#run-machine')).toHaveText('Pause');
  const canvas = page.locator('[data-window=machine] canvas'), bounds = await canvas.boundingBox();
  await canvas.click({ position: { x: bounds.width * .75, y: bounds.height / 2 } });
  await expect(page.locator('.instruction-status')).toContainText('NODE 1');
  await expect(page.locator('#run-machine')).toHaveText('Pause');
  await page.locator('#run-machine').click();
  await expect(page.locator('#status-text')).toHaveText('Execution paused.');
  await expect(page.locator('.instruction-row.next')).toHaveCount(1);
});

test('Run compiles the active buffer when it is not the loaded program', async ({ page }) => {
  await page.goto('/'); await page.evaluate(() => localStorage.clear()); await page.goto('/');
  await expect(page.locator('#status-text')).toHaveText(/Loaded \/home\/user\/main\.c/, { timeout: 60_000 });
  await page.getByRole('button', { name: 'Close lesson', exact: true }).click();
  await page.locator('#examples-menu').click();
  await page.locator('dialog.command-palette input').fill('Remote Call');
  await page.keyboard.press('Enter');
  await expect(page.locator('.buffer-path span').first()).toHaveText('/examples/remote_call.c');
  await expect(page.locator('#run-machine')).toHaveText('Compile & Run');
  await page.keyboard.press('F5');
  await expect(page.locator('#status-text')).toHaveText(/Main returned INT\(142\)/);
  await expect(page.locator('[data-window=machine] .machine-result-value')).toHaveText('INT(142)');
});
