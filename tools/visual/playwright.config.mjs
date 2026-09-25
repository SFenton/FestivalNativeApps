import { defineConfig, devices } from '../../../FortniteFestivalLeaderboardScraper/FortniteFestivalWeb/node_modules/@playwright/test/index.mjs';
import { dirname, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';

const here = dirname(fileURLToPath(import.meta.url));
const sourceWeb = resolve(here, '../../../FortniteFestivalLeaderboardScraper/FortniteFestivalWeb');
const nativeRepo = resolve(here, '../..');

export default defineConfig({
  testDir: here,
  testMatch: '*.spec.ts',
  timeout: 90_000,
  reporter: [['list']],
  use: {
    baseURL: 'http://127.0.0.1:4173',
    headless: true,
    screenshot: 'off',
  },
  projects: [
    { name: 'webkit-mobile', use: { ...devices['iPhone 14'] } },
    { name: 'chromium-desktop', use: { ...devices['Desktop Chrome'] } },
  ],
  webServer: [
    {
      command: 'python3 tools/mock_service.py --port 8765',
      cwd: nativeRepo,
      url: 'http://127.0.0.1:8765/__fixture__/health',
      reuseExistingServer: true,
      timeout: 30_000,
    },
    {
      command: 'node_modules/.bin/vite --mode e2e --host 127.0.0.1 --port 4173 --strictPort',
      cwd: sourceWeb,
      env: { VITE_API_BASE: 'http://127.0.0.1:9', VITE_API_KEY: '' },
      url: 'http://127.0.0.1:4173',
      reuseExistingServer: false,
      timeout: 60_000,
    },
  ],
});
