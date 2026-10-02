# Song Detail (`/songs/:songId`) — spec

> **What:** platform-neutral web behavior of the song page: entry, section order, previews, Paths, accessibility order, test matrix. **Read when:** changing Song Detail on any platform. Platform notes: [ios.md](ios.md) · [ipados.md](ipados.md).

Source: `FortniteFestivalWeb/src/pages/songinfo/SongDetailPage.tsx:109-731`, `src/pages/songinfo/components/{IntensityCard,InstrumentCard}.tsx`, `src/pages/songinfo/components/chart/ScoreHistoryChart.tsx`, `src/pages/songinfo/components/path/PathsModal.tsx:130-755`.

## Entry and navigation

- Opened from a Songs row, optionally with `?instrument=` as default; auto-scroll to that instrument needs explicit navigation state. Back returns through the current tab stack, not unrelated tab history.
- Header: static/dimmed song art, title, artist/year/duration. Links to full solo or band leaderboards, player pages, score history and optional Paths. Mobile web shows chart icons and a FAB Paths action (`FortniteFestivalWeb/src/pages/songinfo/SongDetailPage.tsx:663-731`).

## Section order

1. Intensity for **all charted** instruments (even ones hidden in Settings), using the [difficulty meter](../../controls/difficulty-meter/spec.md) (`raw: true`).
2. Optional player history (more than five scores exposes View All).
3. Promoted selected-band section.
4. Leaderboard cards for **visible** instruments: preview 10 solo scores per chart (up to 10 band scores), loading / empty / error / entries, highlighted selected player or member, rank outside the preview. A selected player's off-preview score opens the 25-row [solo leaderboard](../song-leaderboard/spec.md) with `page` and `navToPlayer`; card/View All opens page one. Every other preview row links to that player's profile (`/player/:accountId`), the selected player's own row to `/statistics` (`InstrumentCard.tsx:133-135,230-234`). Web places View All **after** the rows and only for non-empty, error-free previews (`InstrumentCard.tsx:300-327`).
5. Other Duet/Trio/Quad band previews.

Shop: a validated offer adds an official Shop action and availability badge ([shop-offers](../../controls/shop-offers/spec.md)).

## Paths

[CHOpt Paths control](../../controls/chopt-paths/spec.md): shown only with path-capable instruments; each opening resets instrument, Expert difficulty, saved image/text default and accordions; image and text have independent loading/error and revision cancellation; text column order writes back to Settings; the unavailable-instrument warning can be dismissed once or permanently. The web dialog claims modal semantics without a focus trap — natives deliberately contain focus and restore it.

## Accessibility order (target)

Back → header actions → h1/artist → optional Paths/Shop → intensity → history → promoted band → visible chart cards → other band previews → tab bar.

## Test matrix

Static artwork; seven meter levels; text sizes; missing artwork; no/one/many histories; empty/error previews; all instrument × difficulty × image/text Paths states including rapid selector changes; hidden instrument removes its card but keeps its Intensity; invalid-score leeway changes preview requests.

## Open gaps (all platforms)

Selected-player/member spotlight and history, promoted band rows, per-row profile navigation (done on iPhone), icon-based Intensity header, full Paths table/column reorder, complete focus order. Gap text: `python3 tools/parity_backlog.py --list`.
