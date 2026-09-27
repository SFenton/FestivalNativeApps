import { readFileSync, mkdirSync } from 'node:fs';
import { join, resolve } from 'node:path';
import { test, expect } from '../../../FortniteFestivalLeaderboardScraper/FortniteFestivalWeb/e2e/fixtures/test';
import { createPopulatedScenario } from '../../../FortniteFestivalLeaderboardScraper/FortniteFestivalWeb/e2e/fixtures/scenarios';
import { dismissObstructions, gotoAppRoute } from '../../../FortniteFestivalLeaderboardScraper/FortniteFestivalWeb/e2e/support/drivers/app';
import { isSongsResponse } from '../../../FortniteFestivalLeaderboardScraper/FortniteFestivalWeb/src/api/songsCache';

const root = resolve(import.meta.dirname, '../..');
const output = process.env.FST_VISUAL_OUT ?? join(root, '.visual-output');
const songs: unknown = JSON.parse(
  readFileSync(join(root, 'contracts/fixtures/songs-demo.json'), 'utf8'),
);
if (!isSongsResponse(songs) || songs.count !== songs.songs.length) {
  throw new Error('Invalid synthetic songs fixture');
}
const metadataEdge: unknown = JSON.parse(
  readFileSync(join(root, 'contracts/fixtures/metadata-edge.json'), 'utf8'),
);
if (!metadataEdge || typeof metadataEdge !== 'object'
  || !('songs' in metadataEdge) || !isSongsResponse(metadataEdge.songs)
  || metadataEdge.songs.count !== 1
  || !('player' in metadataEdge) || !metadataEdge.player
  || typeof metadataEdge.player !== 'object'
  || !('accountId' in metadataEdge.player)
  || metadataEdge.player.accountId !== 'fixture-edge'
  || !('totalScores' in metadataEdge.player)
  || metadataEdge.player.totalScores !== 1
  || !('shop' in metadataEdge) || !metadataEdge.shop
  || typeof metadataEdge.shop !== 'object'
  || !('count' in metadataEdge.shop) || metadataEdge.shop.count !== 1) {
  throw new Error('Invalid coherent synthetic metadata edge fixture');
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
  test(`fixture-backed PWA profile discovery and selected Songs: ${viewport.id}`, async ({ page, api, appState }, testInfo) => {
    mkdirSync(output, { recursive: true });
    await page.setViewportSize({ width: viewport.width, height: viewport.height });
    const players = [
      { accountId: 'fixture-player-1', displayName: 'Fixture Player 1' },
      { accountId: 'fixture-player-2', displayName: 'Fixture Player 2' },
    ];
    api.override({
      method: 'GET', path: '/api/account/search', status: 200, body: { results: players },
    });
    api.override({ method: 'GET', path: '/api/songs', status: 200, body: songs });
    await gotoAppRoute(page, '/songs');
    const launcher = viewport.width <= 768
      ? page.getByTestId('mobile-header-profile')
      : page.getByRole('button', { name: 'Select Profile', exact: true });
    await expect(launcher).toBeVisible({ timeout: 15_000 });
    await launcher.click();
    const dialog = page.getByRole('dialog', { name: 'Search', exact: true });
    await expect(dialog).toBeVisible();
    await dialog.getByRole('textbox').fill('Fixture Player');
    await dialog.getByTestId('search-target-filter-players').click();
    await expect(dialog.getByTestId('search-player-result')).toHaveCount(2, { timeout: 15_000 });
    const targetBox = await dialog.getByTestId('search-target-filter-players').boundingBox();
    const resultBox = await dialog.getByTestId('search-player-result').first().boundingBox();
    if (!targetBox || !resultBox) throw new Error('Source search target/results are not painted');
    expect(targetBox.y > resultBox.y).toBe(viewport.width <= 768);
    await page.screenshot({
      path: join(output, `${testInfo.project.name}-${viewport.id}-profile-search-results.png`),
      animations: 'disabled',
    });
    await dialog.getByRole('button', { name: 'Close' }).click();

    const response = await fetch('http://127.0.0.1:8765/api/player/fixture-player-2');
    if (!response.ok) throw new Error(`Synthetic player fixture returned HTTP ${response.status}`);
    const profile: unknown = await response.json();
    if (!profile || typeof profile !== 'object'
      || !('accountId' in profile) || profile.accountId !== 'fixture-player-2'
      || !('totalScores' in profile) || profile.totalScores !== 3
      || !('scores' in profile) || !Array.isArray(profile.scores)) {
      throw new Error('Invalid original synthetic player-profile wire fixture');
    }
    api.override({
      method: 'GET', path: '/api/player/fixture-player-2', status: 200, body: profile,
    });
    await appState.selectPlayer('fixture-player-2', 'Fixture Player 2');
    await appState.setSettings({ songsHideInstrumentIcons: true, filterInvalidScores: false });
    await page.reload({ waitUntil: 'load' });
    const content = page.locator('#main-content');
    await expect(content).toContainText('Fixture Pulse', { timeout: 15_000 });
    await expect(content).toContainText('99,800', { timeout: 15_000 });
    const firstRun = page.getByTestId('fre-card');
    await expect(firstRun).toBeVisible({ timeout: 5_000 });
    await page.screenshot({
      path: join(output, `${testInfo.project.name}-${viewport.id}-profile-first-run.png`),
      animations: 'disabled',
    });
    await dismissObstructions(page);
    await expect(firstRun).toHaveCount(0);
    const selectedRow = content.getByRole('link', { name: /Fixture Pulse/ }).first();
    const title = selectedRow.getByText('Fixture Pulse', { exact: true });
    const score = selectedRow.getByText('99,800', { exact: true });
    await expect(title).toBeVisible();
    await expect(score).toBeVisible();
    await expect(selectedRow.getByText('Top 10%', { exact: true })).toBeVisible();
    const titleBox = await title.boundingBox();
    const scoreBox = await score.boundingBox();
    if (!titleBox || !scoreBox) throw new Error('Source selected-card text is not painted');
    expect(scoreBox.x).toBeGreaterThan(titleBox.x + titleBox.width);
    const metadata = selectedRow.locator('[data-metadata-key]');
    expect(await metadata.evaluateAll(nodes =>
      nodes.map(node => node.getAttribute('data-metadata-key')))).toEqual([
      'percentage', 'percentile', 'stars', 'seasonachieved', 'intensity', 'difficulty',
    ]);
    const bounds = [];
    for (let index = 0; index < 6; index++) {
      const box = await metadata.nth(index).boundingBox();
      if (!box) throw new Error(`Source metadata field ${index} has no painted bounds`);
      bounds.push(box);
    }
    const middles = bounds.map(box => Math.round(box.y + box.height / 2));
    const rows = [...new Set(middles)].map(middle =>
      middles.filter(value => value === middle).length);
    expect(rows).toEqual(viewport.width <= 768 ? [3, 3] : [6]);
    const accuracy = selectedRow.getByText('97.9%', { exact: true });
    await expect(accuracy).toBeVisible();
    const fcStyle = await accuracy.evaluate(element => ({
      color: getComputedStyle(element).color,
      fontStyle: getComputedStyle(element).fontStyle,
      transform: getComputedStyle(element).transform,
    }));
    expect(fcStyle.color).toBe('rgb(255, 215, 0)');
    expect(fcStyle.fontStyle).toBe('italic');
    expect(fcStyle.transform).not.toBe('none');
    await page.screenshot({
      path: join(output, `${testInfo.project.name}-${viewport.id}-songs-selected-player-two.png`),
      animations: 'disabled',
    });

    await appState.setSettings({ metadataShowScore: false });
    await page.reload({ waitUntil: 'load' });
    await dismissObstructions(page);
    const scoreHidden = page.locator('#main-content')
      .getByRole('link', { name: /Fixture Pulse/ }).first();
    await expect(scoreHidden.getByText('99,800', { exact: true })).toHaveCount(0);
    const promoted = scoreHidden.getByText('97.9%', { exact: true });
    const promotedBox = await promoted.boundingBox();
    const hiddenTitleBox = await scoreHidden.getByText('Fixture Pulse', { exact: true }).boundingBox();
    if (!promotedBox || !hiddenTitleBox) {
      throw new Error('Source score-hidden primary accuracy was not painted');
    }
    expect(promotedBox.x).toBeGreaterThan(hiddenTitleBox.x + hiddenTitleBox.width);
    const hiddenBottomKeys = await scoreHidden.locator('[data-metadata-key]')
      .evaluateAll(nodes => nodes.map(node => node.getAttribute('data-metadata-key')));
    if (viewport.width <= 768) {
      expect(hiddenBottomKeys).toEqual([
        'percentile', 'stars', 'seasonachieved', 'intensity', 'difficulty',
      ]);
    } else {
      // Removing Score lowers the page-wide inline threshold below tablet width.
      expect(hiddenBottomKeys).toEqual([]);
      const percentile = await scoreHidden.getByText('Top 10%', { exact: true }).boundingBox();
      const season = await scoreHidden.getByText('S9', { exact: true }).boundingBox();
      const difficulty = await scoreHidden.getByText('X', { exact: true }).boundingBox();
      if (!percentile || !season || !difficulty) {
        throw new Error('Source score-hidden inline metadata is not painted');
      }
      expect(promotedBox.x).toBeLessThan(percentile.x);
      expect(percentile.x).toBeLessThan(season.x);
      expect(season.x).toBeLessThan(difficulty.x);
    }
    await page.screenshot({
      path: join(output, `${testInfo.project.name}-${viewport.id}-songs-player-two-score-hidden.png`),
      animations: 'disabled',
    });
  });
}

for (const viewport of viewports.filter(entry => entry.id.endsWith('portrait'))) {
  test(`fixture-backed PWA default player instrument chips: ${viewport.id}`, async ({ page, api, appState }, testInfo) => {
    mkdirSync(output, { recursive: true });
    await page.setViewportSize({ width: viewport.width, height: viewport.height });
    const response = await fetch('http://127.0.0.1:8765/api/player/fixture-player-2');
    if (!response.ok) throw new Error(`Synthetic profile fixture returned HTTP ${response.status}`);
    const profile: unknown = await response.json();
    if (!profile || typeof profile !== 'object'
      || !('accountId' in profile) || profile.accountId !== 'fixture-player-2'
      || !('totalScores' in profile) || profile.totalScores !== 3
      || !('scores' in profile) || !Array.isArray(profile.scores)
      || !profile.scores.some((score: unknown) => score != null
        && typeof score === 'object' && 'ins' in score && score.ins === '04')) {
      throw new Error('Invalid coherent synthetic Lead and Drums profile fixture');
    }
    api.override({ method: 'GET', path: '/api/player/fixture-player-2', status: 200, body: profile });
    api.override({ method: 'GET', path: '/api/songs', status: 200, body: songs });
    await gotoAppRoute(page, '/songs');
    await appState.selectPlayer('fixture-player-2', 'Fixture Player 2');
    await appState.setSettings({ songsHideInstrumentIcons: false, filterInvalidScores: false });
    await page.reload({ waitUntil: 'load' });
    const content = page.locator('#main-content');
    await expect(content).toContainText('Fixture Pulse', { timeout: 15_000 });
    await dismissObstructions(page);
    const row = content.getByRole('link', { name: /Fixture Pulse/ }).first();
    const instruments = row.locator('img[data-instrument]');
    await expect(instruments).toHaveCount(9, { timeout: 15_000 });
    expect(await instruments.evaluateAll(nodes =>
      nodes.map(node => node.getAttribute('data-instrument')))).toEqual([
      'Solo_Guitar', 'Solo_Bass', 'Solo_Drums', 'Solo_Vocals',
      'Solo_PeripheralGuitar', 'Solo_PeripheralBass', 'Solo_PeripheralVocals',
      'Solo_PeripheralCymbals', 'Solo_PeripheralDrums',
    ]);
    expect(await instruments.evaluateAll(nodes => nodes.map(node => {
      const parent = node.parentElement;
      if (!parent) throw new Error('Instrument chip has no painted wrapper');
      return getComputedStyle(parent).backgroundColor;
    }))).toEqual([
      'rgb(255, 215, 0)', 'rgb(198, 40, 40)', 'rgb(46, 204, 113)',
      'rgb(198, 40, 40)', ...Array(5).fill('rgb(34, 48, 71)'),
    ]);
    const topEdges = await instruments.evaluateAll(nodes =>
      nodes.map(node => Math.round(node.getBoundingClientRect().top)));
    const rows = [...new Set(topEdges)].map(top =>
      topEdges.filter(value => value === top).length);
    expect(rows).toEqual(viewport.width <= 768 ? [5, 4] : [9]);
    await expect(row).not.toContainText('99,800');
    await page.screenshot({
      path: join(output, `${testInfo.project.name}-${viewport.id}-songs-player-two-default-chips.png`),
      animations: 'disabled',
    });
  });
}

for (const viewport of viewports.filter(entry => entry.id.endsWith('portrait'))) {
  test(`fixture-backed PWA long selected score and Shop: ${viewport.id}`, async ({ page, api, appState }, testInfo) => {
    mkdirSync(output, { recursive: true });
    await page.setViewportSize({ width: viewport.width, height: viewport.height });
    api.override({ method: 'GET', path: '/api/songs', status: 200, body: metadataEdge.songs });
    api.override({
      method: 'GET', path: '/api/player/fixture-edge', status: 200, body: metadataEdge.player,
    });
    api.override({ method: 'GET', path: '/api/shop', status: 200, body: metadataEdge.shop });
    await gotoAppRoute(page, '/songs');
    await appState.selectPlayer('fixture-edge', 'Fixture Edge Player');
    await appState.setSettings({ songsHideInstrumentIcons: true, filterInvalidScores: false });
    await page.reload({ waitUntil: 'load' });
    const content = page.locator('#main-content');
    await expect(content).toContainText('A Very Long Synthetic Festival Anthem', { timeout: 15_000 });
    await dismissObstructions(page);
    const row = content.getByRole('link', { name: /A Very Long Synthetic Festival Anthem/ }).first();
    const title = row.getByText(
      'A Very Long Synthetic Festival Anthem with an Extended Encore', { exact: true },
    ).first();
    const score = row.getByText('1,234,567', { exact: true });
    await expect(title).toBeVisible();
    await expect(score).toBeVisible();
    await expect(row).toContainText('Synthetic Quartet Featuring an Extended Ensemble · 2026 · 6:06');
    await page.screenshot({
      path: join(output, `${testInfo.project.name}-${viewport.id}-songs-long-seven-digit-shop.png`),
      animations: 'disabled',
    });
    const titleBox = await title.boundingBox();
    const scoreBox = await score.boundingBox();
    const rowBox = await row.boundingBox();
    if (!titleBox || !scoreBox || !rowBox) {
      throw new Error('Source long-title card has no painted geometry');
    }
    // The source marquee's intrinsic text bounds extend past its clipped viewport.
    expect(scoreBox.x).toBeGreaterThan(rowBox.x + rowBox.width / 2);
    expect(scoreBox.x + scoreBox.width).toBeLessThanOrEqual(rowBox.x + rowBox.width + 1);
    await expect(row.getByText('Top 100%', { exact: true })).toBeVisible();
    await expect(row.locator('[data-metadata-key="lastplayed"]')).toHaveCount(0);
    expect(await row.locator('[data-metadata-key]').evaluateAll(nodes =>
      nodes.map(node => node.getAttribute('data-metadata-key')))).toEqual([
      'percentage', 'percentile', 'stars', 'seasonachieved', 'intensity', 'difficulty',
    ]);
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

for (const viewport of viewports.filter(entry => entry.id.endsWith('portrait'))) {
  test(`fixture-backed PWA Songs Shop highlights: ${viewport.id}`, async ({ page }, testInfo) => {
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
    await gotoAppRoute(page, '/songs');
    await expect(page.locator('#main-content')).toContainText('Fixture Pulse', { timeout: 15_000 });
    await expect(page.locator('[class*="shopHighlightRed"]')).toHaveCount(1, { timeout: 15_000 });
    await expect(page.locator('[class*="shopHighlightGold"]')).toHaveCount(1);
    await page.screenshot({
      path: join(output, `${testInfo.project.name}-${viewport.id}-songs-shop-highlights.png`),
      animations: 'disabled',
    });
  });
}

test('fixture-backed PWA anonymous Item Shop sort reorders Songs', async ({ page }, testInfo) => {
  mkdirSync(output, { recursive: true });
  await page.setViewportSize({ width: 390, height: 844 });
  await page.route('**/api/shop*', async route => {
    const fixture = await fetch('http://127.0.0.1:8765/api/shop?scenario=shop-single');
    await route.fulfill({
      status: fixture.status,
      contentType: 'application/json',
      body: Buffer.from(await fixture.arrayBuffer()),
    });
  });
  await gotoAppRoute(page, '/songs');
  const firstRow = page.locator('#main-content').getByText('Fixture Orbit', { exact: true });
  const secondRow = page.locator('#main-content').getByText('Fixture Pulse', { exact: true });
  const inShop = page.locator('#main-content').getByText('In Shop', { exact: true });
  const notInShop = page.locator('#main-content').getByText('Not In Shop', { exact: true });
  await expect(firstRow).toBeVisible({ timeout: 15_000 });
  await expect(secondRow).toBeVisible();
  await page.getByRole('button', { name: 'Sort Songs', exact: true }).click();
  const dialog = page.getByRole('dialog', { name: 'Sort Songs' });
  await expect(dialog.getByRole('button', { name: 'Item Shop', exact: true })).toBeVisible();
  await dialog.getByRole('button', { name: 'Item Shop', exact: true }).click();
  await dialog.getByRole('button', { name: 'Apply Sort Changes', exact: true }).click();
  await expect.poll(async () =>
    (await secondRow.boundingBox())!.y < (await firstRow.boundingBox())!.y
  ).toBe(true);
  await expect(inShop).toBeVisible();
  await expect(notInShop).toBeVisible();
  await expect.poll(async () =>
    (await inShop.boundingBox())!.y < (await notInShop.boundingBox())!.y
  ).toBe(true);
  await page.screenshot({
    path: join(output, `${testInfo.project.name}-phone-portrait-songs-shop-sort-ascending.png`),
    animations: 'disabled',
  });
  await page.getByRole('button', { name: 'Sort Songs', exact: true }).click();
  await dialog.getByRole('button', { name: 'Descending', exact: true }).click();
  await dialog.getByRole('button', { name: 'Apply Sort Changes', exact: true }).click();
  await expect.poll(async () =>
    (await firstRow.boundingBox())!.y < (await secondRow.boundingBox())!.y
  ).toBe(true);
  await expect.poll(async () =>
    (await notInShop.boundingBox())!.y < (await inShop.boundingBox())!.y
  ).toBe(true);
});

test('fixture-backed PWA selected-player Shop Filter changes Songs', async ({ page, api, appState }, testInfo) => {
  mkdirSync(output, { recursive: true });
  await page.setViewportSize({ width: 390, height: 844 });
  let shopMode: 'shop-single' | 'demo' = 'shop-single';
  await page.route('**/api/shop*', async route => {
    const fixture = await fetch(`http://127.0.0.1:8765/api/shop?scenario=${shopMode}`);
    await route.fulfill({
      status: fixture.status,
      contentType: 'application/json',
      body: Buffer.from(await fixture.arrayBuffer()),
    });
  });
  const response = await fetch('http://127.0.0.1:8765/api/player/fixture-player-2');
  if (!response.ok) throw new Error(`Synthetic profile returned HTTP ${response.status}`);
  const profile: unknown = await response.json();
  if (!profile || typeof profile !== 'object'
    || !('accountId' in profile) || profile.accountId !== 'fixture-player-2'
    || !('scores' in profile) || !Array.isArray(profile.scores)) {
    throw new Error('Invalid coherent synthetic selected-player profile');
  }
  api.override({ method: 'GET', path: '/api/player/fixture-player-2', status: 200, body: profile });
  api.override({ method: 'GET', path: '/api/songs', status: 200, body: songs });
  await gotoAppRoute(page, '/songs');
  await expect(page.locator('#main-content')).toContainText('Fixture Pulse', { timeout: 15_000 });
  await dismissObstructions(page);
  const filter = page.getByRole('button', { name: /^Filter(?: Songs)?$/i }).first();
  await expect(filter).toHaveCount(0);
  await appState.selectPlayer('fixture-player-2', 'Fixture Player 2');
  await page.reload({ waitUntil: 'load' });
  await dismissObstructions(page);
  const content = page.locator('#main-content');
  const pulse = content.getByText('Fixture Pulse', { exact: true });
  const orbit = content.getByText('Fixture Orbit', { exact: true });
  await expect(pulse).toBeVisible({ timeout: 15_000 });
  await expect(orbit).toBeVisible();
  await expect(filter).toBeVisible({ timeout: 15_000 });
  await filter.click();
  const dialog = page.getByRole('dialog', { name: 'Filter Songs' });
  await expect(dialog).toBeVisible();
  await dialog.getByRole('button', { name: /^Item Shop/ }).click();
  const inShop = dialog.getByRole('button', { name: /In the Shop/ }).first();
  await expect(inShop).toBeVisible();
  await page.screenshot({
    path: join(output, `${testInfo.project.name}-phone-portrait-player-shop-filter-default.png`),
    animations: 'disabled',
  });
  await inShop.click();
  await dialog.getByRole('button', { name: 'Apply Filter Changes', exact: true }).click();
  await expect(orbit).toHaveCount(0);
  await expect(pulse).toBeVisible();
  await page.screenshot({
    path: join(output, `${testInfo.project.name}-phone-portrait-player-shop-filter-in-shop.png`),
    animations: 'disabled',
  });

  shopMode = 'demo';
  await page.reload({ waitUntil: 'load' });
  await dismissObstructions(page);
  await expect(pulse).toBeVisible({ timeout: 15_000 });
  await expect(orbit).toBeVisible();
  await filter.click();
  await dialog.getByRole('button', { name: /^Item Shop/ }).click();
  await dialog.getByRole('button', { name: /Leaving Tomorrow/ }).first().click();
  await dialog.getByRole('button', { name: 'Apply Filter Changes', exact: true }).click();
  await expect(pulse).toHaveCount(0);
  await expect(orbit).toBeVisible();
  await page.screenshot({
    path: join(output, `${testInfo.project.name}-phone-portrait-player-shop-filter-leaving.png`),
    animations: 'disabled',
  });
});

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
