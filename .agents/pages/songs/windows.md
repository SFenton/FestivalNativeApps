# Songs — Windows notes

> **What:** what the Windows Songs page implements, native decisions and open gaps. **Read when:** changing `windows/Festival.App/Pages/SongsPage*`, `SongsViewModel`, `SongListPipeline` or `SongRowProjection`. Behavior: [spec.md](spec.md).

## Implemented

- Live keyless `GET /api/publication` + `/api/songs` (+ `/api/shop` and the selected player's `/api/player/{id}`, both best-effort) through the shared gate. Catalogue shared with the background and Song Detail via `FestivalSession`.
- Pipeline (`Domain/SongListPipeline.cs`): search → chart/difficulty → Shop filter → player score filter → sort → group. A saved choice that can't apply **pauses** with an `InfoBar` notice instead of guessing: Shop hidden, Shop feed missing, or catalogue/Shop/session publications differ; player filters while scores are loading/202/failed/mismatched, while Filter Invalid Scores is on, or while every checked chart is hidden in Settings.
- Rows (`SongRowItem`, projected once per rebuild): same-publication Shop border (gold New, red Leaving Tomorrow); with a selected player and scores **available for the catalogue's publication**, either nine status chips (icons on, no chart filter) or Settings-ordered metadata pills for the first visible/filtered chart; otherwise an explicit row state (`Loading scores`, `Scores syncing`, `Scores unavailable`, `Player scores paused until songs update`, `No score`).
- Sort: Title/Artist/Year/Duration + **Item Shop** (members first ascending; buckets Leaving Tomorrow / In Shop / Not In Shop in first-seen order, unlabeled when only one). Item Shop is hidden from the choices while Hide Item Shop is on.
- Filter flyout: chart + 1–7 difficulty (public), In Item Shop / Leaving Tomorrow (disabled but clearable when Shop is hidden), and with a player four global switches plus a per-chart grid (AND within a chart, OR across charts). Apply scopes checks to visible charts; hidden checks are disclosed. Confirmed deselect clears player checks only.
- A damaged saved player filter shows "Saved Filters Can't Be Read" with Reset (`fst.songs.filter-invalid`) instead of the list.
- Jump index: `SemanticZoom` over group headers plus a **Jump** toolbar button (`fst.songs.section-index-button`); disabled when there is a single unlabeled group.
- First-paint gate: the first reveal waits (≤ 900 ms) for the first 12 rows' art to decode, then fades in (instant under reduced motion).
- `MarqueeText` for titles/subtitles (see [design/windows.md](../../design/windows.md#motion)).

## Layout by window size

| Width | Toolbar | Row trailing content |
|---|---|---|
| Compact (< 640 epx page) | Search full width; Sort/Filter/Jump (icon) below | Chips/pills wrap under the title (`FlowPanel`) |
| Medium | One row: search (≤ 440) + Sort/Filter/Jump | Chips inline from 760 epx list width; first pill top-right, rest wrap right-aligned |
| Wide (≥ 1100 epx list) | Same | Every pill inline |

## Native decisions

| Web / iPhone | Windows | Why |
|---|---|---|
| Filter only with a player/band | Filter always available (chart, difficulty, Shop); player section only with a player | Public filters are useful without a profile on desktop |
| Shop filter pauses without a player (iPhone) | Shop filter applies without a player | Shop membership is public data |
| Right-edge scrubber | `SemanticZoom` + Jump button | Windows-native quick jump (Start, Mail, Photos) |
| Marquee always scrolls on overflow | Scrolls only while the row is hovered or keyboard-focused | No per-frame work while idle beside a game |
| Cancel on a changed draft confirms discard | Light-dismiss flyout discards | Fluent flyout convention |

## UI journeys

`python tools/windows/songs_journey.py [--sizes compact,medium,wide] [--shots DIR]` (fixture `tools/mock_service.py`, throwaway `FST_SETTINGS_PATH`): selected-player rows → Item Shop sort → Leaving Tomorrow filter → reset → Song Detail; Item Shop grid/list/compact → Song Detail; Paths image → text → not generated; Karaoke warning dismissal; no player; hidden Shop. Rows expose `fst.songs.row.<songId>`. IDs must sit on UIA-visible elements (text, buttons), not `Border`/`StackPanel`.

## Gotchas

- `SongsViewModel` re-reads the catalogue, Shop and scores on `FestivalSession.PublicationAdvanced`; until the catalogue is re-read, Shop accents and scores stay paused (`ShopOffersForCatalog` is null on mismatch).
- Trailing content is built in the phase-1 `ContainerContentChanging` pass (text renders first); crossing the 760 epx breakpoint re-realizes rows.

## Open

Quick Links rail (Settings lane owns the pattern); profile/FC/band sort modes; invalid-score fallback variants and the warning action; band rows; UIA journeys for sort/filter drafts; Narrator pass.
