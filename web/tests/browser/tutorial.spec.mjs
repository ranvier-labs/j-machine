import { test, expect } from '@playwright/test';

// The first visit shows the tutorial's first step and nothing else; the tour
// then performs every step's action and waits for its done mark.
test('a first visit shows the tour, and every step completes', async ({ page }) => {
  test.setTimeout(900_000);
  await page.goto('/'); await page.evaluate(() => localStorage.clear()); await page.goto('/');
  await expect(page.locator('#status-text')).toHaveText(/Loaded \/home\/user\/main\.c/, { timeout: 60_000 });
  for (const id of ['tutorial', 'editor', 'listener', 'machine']) await expect(page.locator(`[data-window=${id}]`)).toBeVisible();
  for (const id of ['files', 'build', 'debugger', 'geometry']) await expect(page.locator(`[data-window=${id}]`)).toHaveCount(0);
  await expect(page.locator('#examples-menu')).toBeVisible(); await expect(page.locator('#tutorial-menu')).toBeVisible();
  await expect(page.locator('.workbench-header h1')).toHaveText('J-Machine');
  const tour = page.locator('[data-window=tutorial]'), counter = tour.locator('.tool-strip strong'), doIt = tour.locator('.tutorial-actions button').first();
  const next = tour.getByRole('button', { name: 'Next step' }), done = tour.locator('.tutorial-done');
  const expected = [
    ['Run a program', 'Run main.c', /INT\(720\)/, 'machine'], ['Change the program', 'Change 6 to 5 and run', /INT\(120\)/, 'machine'],
    ['Stop and step', 'Break on line 6 and run', /BREAKPOINT/, 'debugger'], ['Two nodes', 'Run remote_call.c', /INT\(142\)/, 'machine'],
    ['Follow the messages', 'Select the first packet', /#\d+/, 'packets'], ['Contention on sixteen nodes', 'Run message_hotspot.c', /16 NODES/, 'machine'],
    ['Projects', 'Build, load, and run /build/main.image', /AVAILABLE/, 'build'], ['Pictures from memory', 'Build and run the Mandelbrot image', /distributed_mandelbrot\.c/, 'display'],
    ['Life across sixteen nodes', 'Run life16.c on 16 nodes', /life16\.c · NODES 0–15/, 'display'], ['A heat equation on the mesh', 'Run heat16.c on 16 nodes', /heat16\.c · NODES 0–15/, 'display'],
    ['The full mesh', 'Run mesh512.c on 512 nodes', /8 × 8 × 8/, 'geometry'], ['Your files', 'Copy remote_call.c into /home/user', /my_remote_call\.c/, 'files'],
  ];
  for (const [index, [title, action, evidence, windowId]] of expected.entries()) {
    await expect(counter).toHaveText(`STEP ${index + 1} OF 13`);
    await expect(tour.locator('.tutorial-title')).toHaveText(title);
    await expect(doIt).toHaveText(action);
    await expect(page.locator(`[data-window=${windowId}]`)).toBeVisible();
    await doIt.click();
    await expect(done).toHaveText('✓ Done', { timeout: 420_000 });
    await expect(page.locator(`[data-window=${windowId}]`)).toContainText(evidence, { timeout: 60_000 });
    await next.click();
  }
  await expect(counter).toHaveText('STEP 13 OF 13');
  await expect(doIt).toHaveText('Show the development layout');
  const snapshot = () => page.evaluate(() => ({ status: document.getElementById('status-text').textContent, windows: [...document.querySelectorAll('[data-window]')].map(e => e.dataset.window).join(','), step: document.querySelector('[data-window=tutorial] .tool-strip strong')?.textContent }));
  console.log('before final Do it', JSON.stringify(await snapshot()));
  await doIt.click();
  await page.waitForTimeout(1500);
  console.log('after final Do it', JSON.stringify(await snapshot()));
  await expect(page.locator('#status-text')).toHaveText(/Layout: development/);
  await expect(page.locator('[data-window=files]')).toBeVisible();
  await expect(page.locator('[data-window=tutorial]')).toHaveCount(0);
  await page.locator('#tutorial-menu').click();
  await expect(page.locator('[data-window=tutorial]')).toBeVisible();
  await expect(counter).toHaveText('STEP 13 OF 13');
  await tour.getByRole('button', { name: 'Next step' }).click();
  await page.reload();
  await expect(page.locator('#status-text')).toHaveText(/Loaded/, { timeout: 60_000 });
  await expect(page.locator('[data-window=files]')).toBeVisible();
  await expect(page.locator('[data-window=tutorial]')).toHaveCount(0);
});

test('Run compiles the active buffer when it is not the loaded program', async ({ page }) => {
  await page.goto('/'); await page.evaluate(() => localStorage.clear()); await page.goto('/');
  await expect(page.locator('#status-text')).toHaveText(/Loaded \/home\/user\/main\.c/, { timeout: 60_000 });
  await page.locator('#examples-menu').click();
  await page.locator('dialog.command-palette input').fill('Remote Call');
  await page.keyboard.press('Enter');
  await expect(page.locator('.buffer-path span').first()).toHaveText('/examples/remote_call.c');
  await expect(page.locator('#run-machine')).toHaveText('Compile & Run');
  await page.keyboard.press('F5');
  await expect(page.locator('#status-text')).toHaveText(/Main returned INT\(142\)/);
  await expect(page.locator('[data-window=machine] .machine-result-value')).toHaveText('INT(142)');
});
