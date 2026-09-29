# Song Detail — Windows notes

> **What:** what the Windows Song Detail page implements and its open gaps. **Read when:** changing `windows/Festival.App/Pages/SongDetailPage*`, `SongDetailViewModel` or `SongPathsView*`. Behavior: [spec.md](spec.md).

## Implemented

- Route `AppRoute.SongDetail(songId, instrument?)`, resolved against the current catalogue (missing → not-found status).
- Header: 128 px art, title (heading 1), `artist · year · duration`, **Paths** (brand-purple accent) and **Item Shop** (official link via `Launcher`, validated `https://www.fortnite.com/item-shop/jam-tracks/…` only) actions. There is no "Item Shop: …" chip (operator 2026-09-28): the Item Shop button's fill breathes in the status colour (`Controls/ShopPulseFill`, web `shopBreathe*`: 3 s ease-in-out from the `#F5121826` surface to gold `#CFA500` New, red `#EF4444` Leaving Tomorrow or green `#1E7F46` in the Shop) while Shop highlighting is on; highlighting off, Reduce Motion / Animation effects off or a hidden window hold the colour still. The UIA name carries the status ("Open in Item Shop, Leaving Tomorrow"). A failed Shop read shows a warning `InfoBar` (`fst.song-detail.shop-error`); hidden Shop shows neither.
- Pinned header: once the full header scrolls away, a compact bar (40 epx art, marquee title/subtitle, **Paths** command) stays at the top (`fst.song-detail.pinned-header`, `fst.song-detail.pinned-paths`), on the near-opaque `FSTPinnedHeaderBrush` (no blur).
- Intensity card for **every charted** chart (hidden ones included), web `IntensityCard` cells: 36 epx icon + bars (name in the tooltip and UIA name), three per row (3×3 for nine charts) at compact/medium and all on one row when they fit (`SongDetailLayout.IntensityColumns`).
- At most **two** leaderboard cards per row, even on wide windows (web `isTwoCol`).
- Rows: rank, name, score, then the accuracy badge (web `AccuracyDisplay`, `Controls/ScoreBadge`): a full combo is the gold skewed outline badge; others a red→green tinted pill. No separate FC chip.
- Leaderboards: Band Leaderboards links (Duos/Trios/Quads → `AppRoute.SongBandLeaderboard`), then one card per **visible** charted instrument, loaded lazily when realized (`?top=10`, plus `leeway` when Filter Invalid Scores is on). The icon + name header sits **above** the card (`Controls/CardHeader`) with "N total entries" as its subtitle when the service allows totals (`showLeaderboardEntryTotals`). Rows are the top ten, then the selected player's own row as **row eleven** when they rank outside it (built from their profile score); a player inside the top ten is highlighted in place. **View Full Leaderboard** is a full-width purple accent button below the rows (`fst.song-detail.view-all.<instrument>`). A chart with no scores says "No scores recorded yet" as the header subtitle (web `songDetail.noScores`), the web's `noScoresSubtitle` sentence in the card and no View Full Leaderboard. The gold "Your score: …" line only shows while no row stands for the player (syncing, paused, no score). **View {chart} Score History** links `AppRoute.PlayerHistory`.
- Paths: modal `ContentDialog` (focus contained and restored) sized to the window; see [chopt-paths/windows.md](../../controls/chopt-paths/windows.md).

## Open

Band preview cards; FC/stars styling of preview rows; scrolling to the initial instrument; Quick Links.
