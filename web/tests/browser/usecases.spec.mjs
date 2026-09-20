import { test, expect } from '@playwright/test';

// End-to-end use cases in the order a new user meets them: read and run the
// example, change it, debug it, write a new program, look at a multi-node
// program's messages, build a project, watch graphical output, load the
// largest mesh, and come back after a reload.
const status = page => page.locator('#status-text');
async function boot(page, query = '', loaded = '/home/user/main.c') {
  await page.goto(`/${query}`);
  await page.evaluate(() => localStorage.clear());
  await page.goto(`/${query}`);
  await expect(status(page)).toHaveText(new RegExp(`Loaded ${loaded.replace(/[./]/g, '\$&')}`), { timeout: 60_000 });
}
async function listener(page, command) {
  await page.locator('#listener-input').fill(command);
  await page.locator('#listener-input').press('Enter');
}
async function replaceSource(page, text) {
  await page.locator('.source-editor .view-lines').click();
  await page.waitForFunction(() => document.activeElement?.closest('.source-editor'));
  // Select all and delete through Monaco's own keybindings, then insert the
  // text as one input event: typing would trigger auto-closing and
  // auto-indent, and insertText does not replace an EditContext selection.
  await page.keyboard.press(process.platform === 'darwin' ? 'Meta+a' : 'Control+a');
  await expect.poll(() => page.locator('.source-editor .selected-text').count()).toBeGreaterThan(0);
  await page.keyboard.press('Backspace');
  await expect(page.locator('.source-editor .view-line')).toHaveCount(1);
  // Paste rather than type: typed braces auto-close and newlines auto-indent.
  await page.evaluate(value => navigator.clipboard.writeText(value), text);
  await page.keyboard.press(process.platform === 'darwin' ? 'Meta+v' : 'Control+v');
}

test('edit the example, recompile with Cmd/Ctrl+Enter, and see the new result', async ({ page }) => {
  await boot(page);
  await replaceSource(page, 'int factorial(int n) {\n  if (n == 0) return 1;\n  return n * factorial(n - 1);\n}\nint main(void) { return factorial(5); }\n');
  await expect(page.locator('.buffer-path .modified')).toHaveText(/MODIFIED/);
  await expect(page.locator('.state-tag')).toHaveText('STALE');
  await expect(page.locator('#run-machine')).toBeDisabled();
  await page.keyboard.press(process.platform === 'darwin' ? 'Meta+Enter' : 'Control+Enter');
  // The status line still reads "Loaded" from boot; the debugger tag changes STALE → LOADED.
  await expect(page.locator('.state-tag')).toHaveText('LOADED');
  await page.keyboard.press('F5');
  await expect(status(page)).toHaveText(/Main returned INT\(120\)/);
  await page.keyboard.press(process.platform === 'darwin' ? 'Meta+s' : 'Control+s');
  await expect(status(page)).toHaveText(/Saved \/home\/user\/main\.c/);
  await expect(page.locator('.buffer-path span').last()).toHaveText(/SAVED · v2/);
});

test('set a source breakpoint, stop on it, step, and continue', async ({ page }) => {
  await boot(page);
  // Line 6 of the seeded factorial: `return n * factorial(n - 1);`
  await page.locator('.source-editor .view-lines').click();
  await page.keyboard.press(process.platform === 'darwin' ? 'Meta+ArrowUp' : 'Control+Home');
  for (let i = 0; i < 5; i++) await page.keyboard.press('ArrowDown');
  await page.keyboard.press('F9');
  const debuggerWindow = page.locator('[data-window=debugger]');
  await expect(debuggerWindow.locator('.compact-list li').first()).toContainText('L6 · bound');
  await expect(page.locator('.breakpoint-glyph')).toHaveCount(1);
  await page.keyboard.press('F5');
  await expect(debuggerWindow.locator('.state-tag')).toHaveText('BREAKPOINT');
  await expect(page.locator('.execution-arrow')).toHaveCount(1);
  await expect(page.locator('#run-machine')).toHaveText('Continue');
  await page.keyboard.press('F10');
  await expect(debuggerWindow.locator('.state-tag')).toHaveText(/INSTRUCTION|STEP/);
  await expect(debuggerWindow.locator('.register strong.changed').first()).toBeVisible();
  await page.keyboard.press('F5');
  await expect(debuggerWindow.locator('.state-tag')).toHaveText('BREAKPOINT');
  await page.keyboard.press('F9');
  await expect(page.locator('.breakpoint-glyph')).toHaveCount(0);
  await page.keyboard.press('F5');
  await expect(status(page)).toHaveText(/Main returned INT\(720\)/);
});

test('create a new file, write a program, save, compile, and run it', async ({ page }) => {
  await boot(page);
  await page.locator('#new-file').click();
  const dialog = page.locator('dialog.path-dialog');
  await expect(dialog).toBeVisible();
  await dialog.locator('input').fill('/home/user/hello.c');
  await page.keyboard.press('Enter');
  await expect(page.locator('.buffer-path span').first()).toHaveText('/home/user/hello.c');
  await expect(page.locator('#compile-buffer')).toBeEnabled();
  await replaceSource(page, 'int main(void) { return 6 * 7; }\n');
  await page.locator('#compile-buffer').click();
  await expect(status(page)).toHaveText(/Loaded \/home\/user\/hello\.c/);
  await page.keyboard.press('F5');
  await expect(status(page)).toHaveText(/Main returned INT\(42\)/);
  await expect(page.locator('[data-window=files] [data-path="/home/user/hello.c"]')).toBeVisible();
});

test('a remote call shows its packets, route, and handler source', async ({ page }) => {
  await boot(page, '?example=remote_call.c', '/examples/remote_call.c');
  await page.keyboard.press('F5');
  await expect(status(page)).toHaveText(/Main returned/);
  await listener(page, 'tile network');
  const packets = page.locator('[data-window=packets]');
  await expect(packets.locator('.packet-row').first()).toBeVisible();
  await packets.locator('.packet-row').first().click();
  await expect(packets.locator('.packet-details h3')).toContainText('#');
  await expect(packets.locator('.inspection-fields')).toContainText('Handler');
  await packets.getByRole('button', { name: 'Visit the message handler' }).click();
  await expect(page.locator('[data-window=editor]')).toBeVisible();
  await expect(page.locator('.buffer-path span').first()).toHaveText('/examples/remote_call.c');
});

test('build a project target from the header, load it through the chooser, and run', async ({ page }) => {
  await boot(page);
  await page.locator('#build-project').click();
  await expect(status(page)).toHaveText(/Build complete/);
  await expect(page.locator('[data-window=build] .build-state').first()).toHaveText('AVAILABLE');
  await page.locator('#load-project').click();
  await expect(status(page)).toHaveText(/Loaded \/build\/main\.image/);
  await expect(page.locator('.loaded-source')).toContainText('/home/user/main.c');
  await page.locator('#run-machine').click();
  await expect(status(page)).toHaveText(/Main returned INT\(720\)/);
});

test('the graphics build shows all four Mandelbrot tiles without choosing a mosaic', async ({ page }) => {
  await boot(page);
  await listener(page, 'use-build /home/user/build-graphics.jm');
  await listener(page, 'build');
  await expect(status(page)).toHaveText(/Build complete/, { timeout: 60_000 });
  await listener(page, 'load /build/mandelbrot.image');
  await expect(status(page)).toHaveText(/Loaded \/build\/mandelbrot\.image/);
  await listener(page, 'tile graphics');
  await listener(page, 'run');
  const display = page.locator('[data-window=display]');
  await expect(display.locator('.network-status')).toHaveText(/distributed_mandelbrot\.c · NODES 0–3/, { timeout: 60_000 });
  await expect(display.locator('select').first()).toHaveValue('auto');
});

test('the 512-node mesh reports fetch and instantiate stages and loads', async ({ page }) => {
  await boot(page);
  const seen = [];
  const watcher = setInterval(async () => { try { seen.push(await status(page).textContent()); } catch {} }, 25);
  await page.locator('#node-count').selectOption('512');
  await page.locator('#compile-buffer').click();
  await expect(status(page)).toHaveText(/Loaded \/home\/user\/main\.c · 714,240 words/, { timeout: 120_000 });
  clearInterval(watcher);
  expect(seen.some(text => /Fetching the 512-node simulator · [\d.]+ MB/.test(text ?? ''))).toBe(true);
  await expect(page.locator('.loaded-source')).toContainText('512 NODES');
  await expect(page.locator('[data-window=geometry] .network-status').first()).toContainText('8 × 8 × 8');
  await page.keyboard.press('F5');
  await expect(status(page)).toHaveText(/Main returned INT\(720\)/, { timeout: 120_000 });
});

test('edits, open buffers, and the layout survive a reload', async ({ page }) => {
  await boot(page);
  await replaceSource(page, 'int main(void) { return 9; }\n');
  await listener(page, 'edit /examples/futures.c');
  await listener(page, 'tile editing');
  await page.waitForTimeout(400);
  await page.reload();
  await expect(status(page)).toHaveText(/Loaded|Environment ready/, { timeout: 60_000 });
  await expect(page.locator('.buffer-tab')).toHaveCount(2);
  await expect(page.locator('[data-window=debugger]')).toBeHidden();
  await page.locator('.buffer-tab button', { hasText: 'main.c' }).click();
  await expect(page.locator('.buffer-path span').last()).toHaveText(/MODIFIED · draft retained/);
  await expect(page.locator('.source-editor')).toContainText('return 9;');
});
