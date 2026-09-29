# Songs — Windows notes

> **What:** what the Windows Songs page implements, native decisions and open gaps. **Read when:** changing `windows/Festival.App/Pages/SongsPage*`, `SongsViewModel`, `SongListPipeline` or `SongRowProjection`. Behavior: [spec.md](spec.md).

## Implemented

- Live keyless `GET /api/publication` + `/api/songs` (+ `/api/shop` and the selected player's `/api/player/{id}`, both best-effort) through the shared gate. Catalogue shared with the background and Song Detail via `FestivalSession`.
- Pipeline (`Domain/SongListPipeline.cs`): search → chart/difficulty → Shop filter → player score filter → sort → group. A saved choice that can't apply **pauses** with an `InfoBar` notice instead of guessing: Shop hidden, Shop feed missing, or catalogue/Shop/session publications differ; player filters while scores are loading/202/failed/mismatched, while Filter Invalid Scores is on, or while every checked chart is hidden in Settings.
- Rows (`SongRowItem`, projected once per rebuild): same-publication Item Shop **pulse ring** (`Controls/ShopPulseRing`, `Domain/SongRowShopPulse`): a 2 epx ring over the card, green `#2ECC71` in Shop, gold `#FFD700` New, red `#EF4444` Leaving Tomorrow, opacity 0 → 0.7 (gold 0.75) → 0 every 2 s ease-in-out like the web's `shopPulse`; static at the peak when motion is off; none when highlighting is disabled or the Shop is hidden. Every ring follows one shared compositor clock sampled at 30 steps/s (one keyframe animation however many rows are realized), held still while the window is hidden; with a selected player and scores **available for the catalogue's publication**, either nine status chips (icons on, no chart filter) or Settings-ordered metadata pills for the first visible/filtered chart; otherwise an explicit row state (`Loading scores`, `Scores syncing`, `Scores unavailable`, `Player scores paused until songs update`, `No score`).
- Sort: Title/Artist/Year/Duration + **Item Shop** (members first ascending; buckets Leaving Tomorrow / In Shop / Not In Shop in first-seen order, unlabeled when only one) + **Has FC** (web `hasfc`: on the filtered chart with a matching score index, scored rows first then No FC before FC; buckets No FC / FC / No Score; without a chart filter or scores it is title order, as the web's empty per-chart score map gives). Item Shop is hidden from the choices while Hide Item Shop is on.
- Sticky section headers with nothing showing through (operator batches 3 + 5): the current section's label sits in a bar (`StickyHeader`) **above** the list viewport, so rows disappear at the list's top edge instead of passing beneath a header. In-list headers (`AreStickyGroupHeadersEnabled=False`, no template divider/padding/min height) scroll up into it; the first section has no in-list header because the bar names it. The label follows `ItemsStackPanel.FirstVisibleIndex` on scroll view changes only.
- A new sort scrolls back to the top (operator batch 5).
- Jump index: Escape, Back (title-bar Back, Alt+Left, XButton1, via `IPageBack`), a click beside the letters, or any new search/sort/filter result returns to the list without jumping (gap 5b, operator batch 6.1); focus returns to Jump.
- Compact: rows end 12 epx from the right edge like the left; the list reserves no gutter for its overlaying scroll indicator (operator 7.24; was 16 epx). Anonymous rows are 64 epx: the art spans the wrapped second row only while it has chips (6.3).
- Filter flyout: chart + 1–7 difficulty (public), In Item Shop / Leaving Tomorrow (disabled but clearable when Shop is hidden), and with a player four global switches plus a per-chart grid (AND within a chart, OR across charts). Apply scopes checks to visible charts; hidden checks are disclosed. Confirmed deselect clears player checks only.
- A damaged saved player filter shows "Saved Filters Can't Be Read" with Reset (`fst.songs.filter-invalid`) instead of the list.
- Sections (operator 2026-09-28, all platforms): Year sorts group by **decade** ("1970s" … "Unknown Year"); Duration sorts use one-minute buckets "Under 1 Minute", "1–2 Minutes" … "9–10 Minutes", "Over 10 Minutes", "Unknown Duration" (`SongCatalogQuery.DecadeBucket` / `DurationBucket`). **This deliberately deviates from the web**, whose Duration quick links use four buckets (`songQuickLinks.ts`); Quick Links take the section labels.
- Jump index: `SemanticZoom` over group headers plus a **Jump** toolbar button (`fst.songs.section-index-button`); disabled when there is a single unlabeled group and under the **Year** sort (no quick-jump there, operator 2026-09-28).
- Rows stagger in with the shared fade (`FadeIn`, after the art-priming gate) and re-stagger on sort/filter/search changes.
- First-paint gate: the first reveal waits (≤ 900 ms) for the first 12 rows' art to decode, then fades in (instant under reduced motion).
- Songs in the Item Shop carry a small bag badge on the album art, coloured like the row's pulse (green / gold New / red Leaving; operator batch 7.19). Metadata pills, stars and the intensity meter share one 22 epx height (7.18); the primary metric stays top-right, so a long title never pushes it down.
- Player sorts (web `SortModal` + `compareByMode`): with a player, **Last Played** (the filtered chart, else each song's latest play across visible charts); with a player and one chart, **Score, Percentage, Percentile, Stars, Season, Intensity, Difficulty, Max Score %, Max Score Diff** (`SongListPipeline.MetricSort`). Unscored rows sort after scored ones before the direction applies (so descending lists them first, as on the web), except Max Score % / Diff, which keep scored rows first; one unlabeled section; without the score index or chart they fall back to Title. Profile presets sort like the web updaters: Songs Played / FCs by Score, a star level by Stars, a placement band keeps the sort.
- Sort flyout: Sort By radio list, then Ascending / Descending rows with the web descriptions ("A–Z, low–high") as subtitles (7.21); Sort and Filter Reset are the web's full-width red button (7.10).
- `MarqueeText` for titles/subtitles (see [design/windows.md](../../design/windows.md#motion)).

## Layout by window size

| Width | Toolbar | Row trailing content |
|---|---|---|
| Compact (< 640 epx page) | Search full width; Sort/Filter/Jump (icon) below | Chips/pills wrap under the title (`FlowPanel`) |
| Medium | One row: search (≤ 440) + Sort/Filter/Jump | Chips inline from 760 epx list width; first pill top-right, rest wrap right-aligned |
| Wide (≥ 1100 epx page) | List + detail columns; list toolbar as compact | Chips/pills wrap under the title |

## Two columns (wide)

From a **1100 epx page** (e.g. a 1440 epx window with the expanded pane) the page splits into a 560 epx list and the selected song's Song Detail (`DetailFrame`, `fst.songs.detail-pane`; operator 2026-09-28, mirroring Android foldables/iPad). The list switches to single selection, the first row is selected so the detail is never empty, a sort/filter keeps the selection when the song survives (else the first row), and keyboard arrowing loads the detail 180 ms after it stops. Clicks select instead of pushing. The list column uses the narrow toolbar (search on its own row) and wraps chips under titles. With no rows, or below 1100 epx, it is a single column again and the embedded page is released. Links inside the embedded detail push full pages on the Songs stack.

## Native decisions

| Web / iPhone | Windows | Why |
|---|---|---|
| Filter only with a player/band | Filter hidden without a profile (operator 2026-09-28), except while a saved filter is still active so it can be cleared; player section only with a player | Web parity; a saved public filter still applies, like the web |
| Shop filter pauses without a player (iPhone) | Shop filter applies without a player | Shop membership is public data |
| Right-edge scrubber | `SemanticZoom` + Jump button | Windows-native quick jump (Start, Mail, Photos) |
| Marquee always scrolls on overflow | Same (operator 2026-09-28): scrolls whenever it overflows, phase-aligned; stops when motion is off, the window is hidden or the row is unrealized | Composition animation only; see perf notes in [design/windows.md](../../design/windows.md#motion) |
| Cancel on a changed draft confirms discard | Light-dismiss flyout discards | Fluent flyout convention |

## UI journeys

`python tools/windows/songs_journey.py [--sizes compact,medium,wide] [--shots DIR]` (fixture `tools/mock_service.py`, throwaway `FST_SETTINGS_PATH`): selected-player rows → Item Shop sort → Leaving Tomorrow filter → reset → Song Detail; Item Shop grid/list/compact → Song Detail; Paths image → text → not generated; Karaoke warning dismissal; no player; hidden Shop. Rows expose `fst.songs.row.<songId>`. IDs must sit on UIA-visible elements (text, buttons), not `Border`/`StackPanel`.

## Gotchas

- `SongsViewModel` re-reads the catalogue, Shop and scores on `FestivalSession.PublicationAdvanced`; until the catalogue is re-read, Shop accents and scores stay paused (`ShopOffersForCatalog` is null on mismatch).
- Trailing content is built in the phase-1 `ContainerContentChanging` pass (text renders first); crossing the 760 epx breakpoint re-realizes rows.

## Open

Quick Links rail (Settings lane owns the pattern); profile/FC/band sort modes; invalid-score fallback variants and the warning action; band rows; UIA journeys for sort/filter drafts; Narrator pass.
