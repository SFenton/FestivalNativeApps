import { readFileSync, mkdirSync } from 'node:fs';
import { join, resolve } from 'node:path';
import { test, expect } from '../../../FortniteFestivalLeaderboardScraper/FortniteFestivalWeb/e2e/fixtures/test';
import { createPopulatedScenario } from '../../../FortniteFestivalLeaderboardScraper/FortniteFestivalWeb/e2e/fixtures/scenarios';
import { gotoAppRoute } from '../../../FortniteFestivalLeaderboardScraper/FortniteFestivalWeb/e2e/support/drivers/app';
import { isSongsResponse } from '../../../FortniteFestivalLeaderboardScraper/FortniteFestivalWeb/src/api/songsCache';

const root = resolve(import.meta.dirname, '../..');
const output = process.env.FST_VISUAL_OUT ?? join(root, '.visual-output');
const songs: unknown = JSON.parse(
  readFileSync(join(root, 'contracts/fixtures/songs-demo.json'), 'utf8'),
);
if (!isSongsResponse(songs) || songs.count !== songs.songs.length) {
  throw new Error('Invalid synthetic songs fixture');
}
const scenario = createPopulatedScenario();
scenario.songs = songs;
scenario.songsEtag = '"fst-visual-songs"';

const viewports = [
  { id: 'phone-portrait', width: 390, height: 844 },
  { id: 'phone-landscape', width: 844, height: 390 },
  { id: 'tablet-portrait', width: 820, height: 1180 },
  { id: 'tablet-landscape', width: 1180, height: 820 },
];

test.use({ scenario });
test.beforeEach(async ({ appState, page }) => {
  await page.route('**/*', async route => {
    const url = new URL(route.request().url());
    if (url.pathname.startsWith('/api/')) {
      await route.fallback();
    } else if (url.hostname === 'cdn2.unrealengine.com') {
      const name = url.pathname.includes('orbit') ? 'orbit' : 'pulse';
      const art = await fetch(`http://127.0.0.1:8765/__fixture__/art/${name}.png`);
      if (!art.ok) throw new Error(`Fixture art ${art.status}`);
      await route.fulfill({
        status: 200, contentType: 'image/png',
        body: Buffer.from(await art.arrayBuffer()),
      });
    } else if (url.hostname === '127.0.0.1' || url.hostname === 'localhost') {
      await route.continue();
    } else {
      await route.abort('blockedbyclient');
    }
  });
  await appState.reset();
  await page.emulateMedia({ reducedMotion: 'reduce' });
});

for (const viewport of viewports) {
  test(`fixture-backed PWA page layouts: ${viewport.id}`, async ({ page }, testInfo) => {
    mkdirSync(output, { recursive: true });
    await page.setViewportSize({ width: viewport.width, height: viewport.height });
    const prefix = `${testInfo.project.name}-${viewport.id}`;
    const pages = [
      { id: 'songs', path: '/songs', text: 'Fixture Pulse' },
      { id: 'song-detail', path: '/songs/fixture-pulse', text: 'Intensity' },
      { id: 'song-leaderboard', path: '/songs/fixture-pulse/Solo_Guitar', text: 'Score Player 1' },
      { id: 'settings', path: '/settings', text: 'App Settings' },
    ];
    for (const entry of pages) {
      await gotoAppRoute(page, entry.path);
      await expect(page.locator('#main-content')).toContainText(entry.text, { timeout: 15_000 });
      await page.screenshot({
        path: join(output, `${prefix}-${entry.id}.png`),
        animations: 'disabled',
      });
    }
  });
}
