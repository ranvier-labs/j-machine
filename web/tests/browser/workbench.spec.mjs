import { test, expect } from '@playwright/test';

// A fresh workspace for every test: storage is per origin and would otherwise
// carry buffers, drafts, and layouts between runs.
// A fresh visit shows the tutorial layout; most checks want the full desktop.
async function boot(page, query = '', loaded = '/home/user/main.c', { full = true } = {}) {
  await page.goto(`/${query}`);
  await page.evaluate(() => localStorage.clear());
  await page.goto(`/${query}`);
  await expect(page.locator('#status-text')).toHaveText(new RegExp(`Loaded ${loaded.replace(/[./]/g, '\$&')}`), { timeout: 60_000 });
  if (full) { await page.locator('#listener-input').fill('tile development'); await page.locator('#listener-input').press('Enter'); await expect(page.locator('[data-window=debugger]')).toBeVisible(); }
}
const selectAll = process.platform === 'darwin' ? 'Meta+a' : 'Control+a';
const listener = async (page, command) => {
  await page.locator('#listener-input').fill(command);
  await page.locator('#listener-input').press('Enter');
};

test('boots, compiles the seeded buffer, and runs it to completion', async ({ page }) => {
  await boot(page);
  await expect(page.locator('#run-machine')).toHaveText('Run');
  await page.keyboard.press('F5');
  await expect(page.locator('#status-text')).toHaveText(/Main returned INT\(720\)/);
  await expect(page.locator('#run-machine')).toBeDisabled();
  await expect(page.locator('#restart-machine')).toBeEnabled();
});

test('the header stays on one row at a laptop width', async ({ page }) => {
  await boot(page);
  const header = page.locator('.workbench-header');
  const box = await header.boundingBox();
  const buttons = await header.locator('button, select').evaluateAll(nodes => nodes.map(n => n.getBoundingClientRect().top));
  expect(new Set(buttons.map(Math.round)).size).toBe(1);
  expect(box.height).toBeLessThan(44);
  await expect(header.locator('#project-file')).toHaveCount(0);
});

test('M-x opens the command palette, filters, and closes on Escape', async ({ page }) => {
  await boot(page);
  await page.keyboard.press('Alt+x');
  const palette = page.locator('dialog.command-palette');
  await expect(palette).toBeVisible();
  await palette.locator('input').fill('layout network');
  await expect(palette.locator('[role=option]').first()).toContainText('Layout: network');
  await page.keyboard.press('Escape');
  await expect(palette).toBeHidden();
});

test('listener layouts and window aliases keep the geometry window reachable', async ({ page }) => {
  await boot(page);
  await listener(page, 'tile network');
  await expect(page.locator('[data-window=geometry]')).toBeVisible();
  await expect(page.locator('[data-window=editor]')).toBeHidden();
  // The network layout has no listener; the palette restores the development layout.
  await page.keyboard.press('Alt+x');
  await page.locator('dialog.command-palette input').fill('Layout: development');
  await page.keyboard.press('Enter');
  await expect(page.locator('[data-window=editor]')).toBeVisible();
  await expect(page.locator('[data-window=debugger]')).toBeVisible();
  await listener(page, 'window machine');
  await expect(page.locator('#focused-window')).toHaveText('MACHINE');
  await listener(page, 'window geometry');
  await expect(page.locator('#focused-window')).toHaveText('ROUTING GEOMETRY');
});

test('compile errors name the buffer pathname and reach the Problems list', async ({ page }) => {
  await boot(page);
  await page.locator('.source-editor .view-lines').click();
  await page.keyboard.press(selectAll);
  await page.keyboard.type('int broken = ; int main(void) { return 1; ');
  await expect(page.locator('.editor-modeline button')).toHaveText(/1 problem/);
  await page.locator('#compile-buffer').click();
  await expect(page.locator('#status-text')).toHaveText(/\/home\/user\/main\.c:\d+:\d+/);
  await expect(page.locator('#status-text')).not.toHaveText(/<browser>/);
  await listener(page, 'window problems');
  await expect(page.locator('.problem-row .problem-location')).toContainText('/home/user/main.c:1:14');
});

test('file operations hide when they do not apply and commands report why', async ({ page }) => {
  await boot(page);
  const files = page.locator('[data-window=files]');
  await files.locator('[data-path="/home/user/main.c"]').click();
  await expect(files.getByRole('button', { name: 'Rename or move selected path' })).toBeVisible();
  await files.locator('[data-path="/home/user"]').click();
  await expect(files.getByRole('button', { name: 'Rename or move selected path' })).toBeHidden();
  await expect(files.getByRole('button', { name: 'Download the selected file or a filesystem backup' })).toBeVisible();
  await listener(page, 'command file-versions');
  await expect(page.locator('#status-text')).toHaveText(/Versions does not apply/);
});

test('project build, load, and run through the listener, then the workflow hint retires', async ({ page }) => {
  await boot(page);
  await expect(page.locator('.build-workflow')).toBeVisible();
  await listener(page, 'build /build/main.image');
  await expect(page.locator('#status-text')).toHaveText(/Build complete · 1 built/);
  await listener(page, 'load /build/main.image');
  await expect(page.locator('#status-text')).toHaveText(/Loaded \/build\/main\.image/);
  await expect(page.locator('.build-workflow')).toBeHidden();
  await listener(page, 'run');
  await expect(page.locator('#status-text')).toHaveText(/Main returned INT\(720\)/);
});

test('a multi-node program captures packets and the geometry auto view labels nodes', async ({ page }) => {
  await boot(page, '?example=remote_call.c', '/examples/remote_call.c');
  await page.keyboard.press('F5');
  await expect(page.locator('#status-text')).toHaveText(/Main returned/);
  await listener(page, 'window packets');
  await expect(page.locator('.network-status').first()).toHaveText(/LIVE · [1-9]\d* packets/);
  await listener(page, 'window geometry');
  const geometry = page.locator('[data-window=geometry]');
  await expect(geometry.locator('.mesh-node')).toHaveCount(2);
  await expect(geometry.locator('.mesh-node text')).toHaveCount(2);
});

// Embedding browsers may inject trusted key events with `key` set but no key
// code. The desktop repairs them so dialogs, forms, and Monaco still respond.
const degraded = (page, selector, key, init = {}) => page.evaluate(([selector, key, init]) => {
  const target = document.querySelector(selector) ?? document.activeElement;
  for (const type of ['keydown', 'keyup']) target.dispatchEvent(new KeyboardEvent(type, { key, code: '', bubbles: true, cancelable: true, composed: true, ...init }));
}, [selector, key, init]);

test('key events without key codes still close dialogs, submit the listener, and reach Monaco', async ({ page }) => {
  await boot(page);
  await page.keyboard.press('Alt+x');
  const palette = page.locator('dialog.command-palette');
  await expect(palette).toBeVisible();
  await degraded(page, 'dialog.command-palette input', 'Escape');
  await expect(palette).toBeHidden();
  await page.locator('#listener-input').fill('tile editing');
  await degraded(page, '#listener-input', 'Enter');
  await expect(page.locator('[data-window=debugger]')).toBeHidden();
  await expect(page.locator('#listener-input')).toHaveValue('');
  await page.locator('.source-editor .view-lines').click();
  await page.waitForFunction(() => document.activeElement?.closest('.source-editor'));
  await page.keyboard.insertText('zzz');
  await expect(page.locator('.source-editor')).toContainText('zzz');
  await degraded(page, '.source-editor .native-edit-context, .source-editor textarea', 'z', { metaKey: process.platform === 'darwin', ctrlKey: process.platform !== 'darwin' });
  await expect(page.locator('.source-editor')).not.toContainText('zzz');
  await degraded(page, '.source-editor .native-edit-context, .source-editor textarea', 'F5');
  await expect(page.locator('#status-text')).toHaveText(/Main returned INT\(720\)/);
});
