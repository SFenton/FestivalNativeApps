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
      if (url.hostname === '127.0.0.1' || url.hostname === 'localhost') {
        await route.fallback();
      } else {
        await route.abort('blockedbyclient');
      }
    } else if (url.pathname.startsWith('/__fixture__/art/')
               || url.hostname === 'cdn2.unrealengine.com') {
      const name = url.pathname.endsWith('/orbit.png') ? 'orbit'
        : url.pathname.endsWith('/pulse.png') ? 'pulse'
        : null;
      if (!name) throw new Error(`Unexpected fixture artwork path: ${url.pathname}`);
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

for (const viewport of viewports.filter(entry => entry.id.endsWith('portrait'))) {
  test(`fixture-backed PWA anonymous Sort modal: ${viewport.id}`, async ({ page }, testInfo) => {
    mkdirSync(output, { recursive: true });
    await page.setViewportSize({ width: viewport.width, height: viewport.height });
    await gotoAppRoute(page, '/songs');
    await expect(page.locator('#main-content')).toContainText('Fixture Pulse', { timeout: 15_000 });
    await page.getByRole('button', { name: 'Sort Songs', exact: true }).click();
    const dialog = page.getByRole('dialog', { name: 'Sort Songs' });
    await expect(dialog).toBeVisible();
    await expect(dialog.getByRole('button', { name: 'Duration', exact: true })).toBeVisible();
    await expect(dialog.getByRole('button', { name: 'Reset', exact: true })).toBeVisible();
    const apply = dialog.getByRole('button', { name: 'Apply Sort Changes', exact: true });
    await expect(apply).toBeDisabled();
    await page.screenshot({
      path: join(output, `${testInfo.project.name}-${viewport.id}-songs-sort-default.png`),
      animations: 'disabled',
    });
    await dialog.getByRole('button', { name: 'Artist', exact: true }).click();
    await dialog.getByRole('button', { name: 'Descending', exact: true }).click();
    await expect(dialog.getByRole('button', { name: 'Artist', exact: true }))
      .toHaveAttribute('aria-pressed', 'true');
    await expect(apply).toBeEnabled();
    await page.screenshot({
      path: join(output, `${testInfo.project.name}-${viewport.id}-songs-sort-draft.png`),
      animations: 'disabled',
    });
  });
}

for (const viewport of viewports.filter(entry => entry.id.endsWith('portrait'))) {
  test(`fixture-backed PWA CHOpt Paths modal: ${viewport.id}`, async ({ page }, testInfo) => {
    mkdirSync(output, { recursive: true });
    await page.setViewportSize({ width: viewport.width, height: viewport.height });
    await page.route('**/api/paths/**', async route => {
      const source = new URL(route.request().url());
      const fixture = await fetch(`http://127.0.0.1:8765${source.pathname}${source.search}`);
      await route.fulfill({
        status: fixture.status,
        contentType: fixture.headers.get('content-type') ?? 'application/octet-stream',
        body: Buffer.from(await fixture.arrayBuffer()),
      });
    });
    await gotoAppRoute(page, '/songs/fixture-pulse');
    await expect(page.locator('#main-content')).toContainText('Intensity', { timeout: 15_000 });
    await page.getByRole('button', { name: 'View Paths' }).click();
    await expect(page.getByText('Karaoke is not available for path visualization yet.'))
      .toBeVisible();
    await page.getByRole('button', { name: 'OK', exact: true }).click();
    const dialog = page.getByRole('dialog', { name: 'Paths' });
    await expect(dialog).toBeVisible();
    await expect(dialog.getByRole('img', { name: 'Lead Expert path' }))
      .toBeVisible({ timeout: 15_000 });
    await page.screenshot({
      path: join(output, `${testInfo.project.name}-${viewport.id}-chopt-path-image.png`),
      animations: 'disabled',
    });
    await dialog.getByRole('button', {
      name: viewport.width <= 768 ? 'Path display: Image' : 'Image',
      exact: true,
    }).click();
    await dialog.getByRole('button', { name: 'Text', exact: true }).click();
    await expect(dialog.getByText('5.50', { exact: true })).toBeVisible({ timeout: 15_000 });
    await page.screenshot({
      path: join(output, `${testInfo.project.name}-${viewport.id}-chopt-path-text.png`),
      animations: 'disabled',
    });
  });
}

for (const viewport of viewports.filter(entry => entry.id.endsWith('portrait'))) {
  test(`fixture-backed PWA Item Shop: ${viewport.id}`, async ({ page }, testInfo) => {
    mkdirSync(output, { recursive: true });
    await page.setViewportSize({ width: viewport.width, height: viewport.height });
    await page.route('**/api/shop*', async route => {
      const source = new URL(route.request().url());
      const fixture = await fetch(`http://127.0.0.1:8765${source.pathname}${source.search}`);
      await route.fulfill({
        status: fixture.status,
        contentType: 'application/json',
        body: Buffer.from(await fixture.arrayBuffer()),
      });
    });
    await gotoAppRoute(page, '/shop');
    await expect(page.locator('#main-content')).toContainText('Fixture Orbit', { timeout: 15_000 });
    await expect(page.locator('#main-content')).toContainText('Fixture Pulse');
    await page.screenshot({
      path: join(output, `${testInfo.project.name}-${viewport.id}-shop-loaded.png`),
      animations: 'disabled',
    });
  });
}

test('fixture-backed PWA artwork actually rotates after the five-second dwell', async ({ page }, testInfo) => {
  mkdirSync(output, { recursive: true });
  await page.setViewportSize({ width: 390, height: 844 });
  await page.emulateMedia({ reducedMotion: 'no-preference' });
  await gotoAppRoute(page, '/songs');
  await expect(page.locator('#main-content')).toContainText('Fixture Pulse', { timeout: 15_000 });

  const activeCover = () => page.evaluate(() => {
    const layers = Array.from(document.querySelectorAll<HTMLDivElement>('div'));
    const active = layers.find(element => {
      const style = getComputedStyle(element);
      return style.position === 'absolute'
        && style.backgroundImage.includes('/__fixture__/art/')
        && Number(style.opacity) > 0.95;
    });
    return active ? getComputedStyle(active).backgroundImage : null;
  });
  await expect.poll(activeCover, { timeout: 15_000 }).not.toBeNull();
  const first = await activeCover();
  await page.screenshot({
    path: join(output, `${testInfo.project.name}-phone-portrait-artwork-first.png`),
    animations: 'allow',
  });
  await expect.poll(async () => {
    const cover = await activeCover();
    return cover && cover !== first ? cover : null;
  }, { timeout: 9_000 }).not.toBeNull();
  await page.screenshot({
    path: join(output, `${testInfo.project.name}-phone-portrait-artwork-next.png`),
    animations: 'allow',
  });
});
