# Songs — Android notes

> **What:** what the Android Songs page implements, native decisions and open gaps. **Read when:** changing Songs on Android (`ui/songs/`, `core/songs/`, `presentation/SongsViewModel.kt`). Behavior: [spec.md](spec.md).

## Implemented

- Live keyless `/api/songs` through `FestivalApi.catalog()`; loading / service status / empty / populated; pull to refresh re-checks the publication.
- Pipeline `SongListPipeline.run` (pure, unit-tested): search (250 ms debounce) → chart + 1–7 difficulty filter → Shop filter → selected-player score/FC filter → sort → headers/sections. Saved Shop and score choices that can't apply **pause** with a notice card (`fst.songs.notice.*`) instead of guessing: Shop hidden, Shop feed not loaded, Shop/catalogue publication mismatch, score filters with hidden charts, no player, Filter Invalid Scores, or scores from another publication.
- Sort sheet (`fst.songs.sort`): Title/Artist/Year/Duration/**Item Shop** (removed while Shop is hidden) + direction, a **draft** with Reset/Cancel/Apply; swiping away or Cancel with changes asks to discard. Shop sort shows **Leaving Tomorrow / In Shop / Not In Shop** headers only when ≥2 buckets exist (`fst.songs.shop-section.*`).
- Filter sheet (`fst.songs.filter`, selected player only, like the web mobile dock): instrument (with icons), difficulty `RangeSlider`, In Shop / Leaving Tomorrow switches (disabled but resettable when Shop is hidden), global + per-chart Missing/Has Scores and Missing/Has FCs (`FilterChip`s). Hidden-chart checks are disclosed and dropped on Apply.
- Persistence (`data/songs/SongsPreferences`, keys `fst.songs.filters`, `fst.songs.playerScoreFilters`, `fst.shop.viewMode`, all `ResetPolicy.Kept`): the player filter is bounded typed JSON; a corrupt value blocks the list with **Reset Filters** (`fst.songs.filter-invalid`). Confirmed deselection clears only the player predicates (`watchDeselection`).
- Rows (`ui/songs/SongRow.kt`): glass card, 48 dp art, marquee title/subtitle (`basicMarquee`, draw-phase only; ellipsis under reduced motion), Shop accent border (red Leaving / gold New) + badge, then either **status chips** (balanced wrap: one row of nine on a phone card, centered) or **metadata pills** in Settings order with Last Played last, or an explicit score state (`Loading scores`, `Scores syncing`, `Player scores paused until songs update`, `No score`, …). One TalkBack stop speaking `SongRowModel.announcement`.
- Scores come from `container.selectedProfile` (profile lane) via `SelectedProfileState.songScoreSource`, which requires catalogue, score read and session to share the observed publication.
- First-paint gate: the first reveal waits ≤ 900 ms for the first 12 rows' artwork via Coil, then fades in (instant under reduced motion). Later updates never re-block.
- Section index (Title/Artist/Year): animates in/out, one accessibility element with the current section as its state and **Next/Previous section** custom actions.
- Expanded widths / separating hinge: list + Song Detail panes (`fst.songs.detail-pane`).

## Native decisions

| Web | Android | Why |
|---|---|---|
| Lower search dock | Search field as the first list item | Material; keeps the bottom bar for navigation |
| Nine chips wrap 5+4 at 390 px | One row when the card fits nine 34 dp chips (Pixel 9 does), else balanced rows | Same balancing rule as Apple `SongChipRows` |
| Metadata spacing via CSS | `FlowRow` right-aligned; first field top-trailing | Grows at large text instead of clipping |

## Tests

`core/songs/SongsCoreTest` (filters, pipeline pauses, sort, drafts, chips, metadata, projection), `data/songs/SongsDataTest`, `presentation/songs/SongsViewModelTest`, `ui/ShellUiTest` (search, sort draft apply, filter apply). Fixture screenshot: `android/reports/screenshots/songs-player-phone.png` (mock service, `fixture-player-1`).

## Open

Quick Links for Duration/Shop sorts, profile/FC sort modes, invalid-score fallback variants and the warning action, first-run carousel, band rows, device journeys on foldables.
