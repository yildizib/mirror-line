import { defineConfig } from '@playwright/test';

export default defineConfig({
  testDir: './tests',
  timeout: 30_000,
  expect: { timeout: 5_000 },
  use: {
    baseURL: 'http://127.0.0.1:4173',
    viewport: { width: 412, height: 915 },
    colorScheme: 'light',
    locale: 'tr-TR',
  },
  webServer: {
    command: 'npm run dev -- --host 127.0.0.1 --port 4173 --strictPort',
    url: 'http://127.0.0.1:4173',
    reuseExistingServer: true,
  },
  reporter: [['list'], ['html', { outputFolder: 'build/playwright-report', open: 'never' }]],
});
