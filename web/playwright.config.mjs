import { defineConfig } from '@playwright/test';

// Browser-level checks against the built workbench in dist/. The engines
// (compiler.wasm, simulator_*.wasm) must be built first; `npm run build`
// refreshes the frontend bundle.
export default defineConfig({
  testDir: './tests/browser',
  timeout: 90_000,
  expect: { timeout: 30_000 },
  retries: 0,
  reporter: [['list']],
  use: { baseURL: 'http://127.0.0.1:8017', viewport: { width: 1280, height: 800 }, permissions: ['clipboard-read', 'clipboard-write'] },
  webServer: {
    command: 'python3 -m http.server 8017 --bind 127.0.0.1 --directory dist',
    url: 'http://127.0.0.1:8017/index.html',
    reuseExistingServer: true,
  },
  // The installed Google Chrome by default: it supports the Wasm exception
  // and tail-call features the engines need, and avoids a browser download.
  // PLAYWRIGHT_CHANNEL=chromium uses a build from `npx playwright install chromium`.
  projects: [{ name: 'chromium', use: { browserName: 'chromium', channel: process.env.PLAYWRIGHT_CHANNEL === 'chromium' ? undefined : (process.env.PLAYWRIGHT_CHANNEL ?? 'chrome') } }],
});
