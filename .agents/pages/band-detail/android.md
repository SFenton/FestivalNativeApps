# Band Detail — Android notes

> **What:** what the Android Band Detail page implements, its safe lookup and adaptive layout. **Read when:** changing `ui/bands/BandDetailScreen.kt` or `BandDetailViewModel`. Behavior: [spec.md](spec.md); references: [ios.md](ios.md), [windows.md](windows.md).

## Data (safe lookup only)

| Read | Endpoint | Notes |
|---|---|---|
| Band row | `GET /api/rankings/bands/{bandType}?teamKey=&rankBy=adjusted&page=1&pageSize=1` → `selectedBandEntry` | `null` → 404 → "Band not found" page. Never `/api/bands/{bandId}` or the bare `/api/rankings/bands/{bandType}/{teamKey}` ([service-safety](../../platforms/service-safety.md)) |
| Rank history | `…/{bandType}/{teamKey}/history?days=30` | Starts only after the band row loads; `historyStatus`/`historyMessage` → note under the heading |
| Best/worst | `…/{bandType}/{teamKey}/songs?limit=5` + catalogue (best effort) | 503 until the projection is published → inline status + Retry; unknown songs show `Unknown Song`, not tappable |

`BandRoute(bandId, name?, bandType?, teamKey?)` must carry the type and key from the originating row. A bare `bandId`, unknown type or unsafe key (`BandText.isValidTeamKey`: 1–4 `:`-joined safe IDs, ≤600 chars) shows **Band Not Available** and sends nothing. Debug: `FST_DEBUG_ROUTE=band:<bandId>:<bandType>:<teamKey>` (the key may contain `:`).

## Layout

- Top bar `Band`; header = joined member names (heading) + `<Size> · N appearances`.
- Members: glass cards (≥260 dp columns): name + 28 dp instrument icons; linkable members open `PlayerRoute`, anonymous members are dimmed and inert.
- Band Summary (Type, Appearances, Members) and Band Statistics tiles (2–4 columns by width). Rank By is an outlined button + dropdown menu (four long labels do not fit a phone segmented row); default Total Score. The rank tile links to `BandRankingsRoute`, Best Song Rank to Song Detail once the best song resolves.
- Band Rank History: static Canvas line (best rank at the top, redrawn only when data or metric change) plus the 10 newest snapshots (date, rank, metric value); `No band rank history yet.` when empty.
- Five Best / Five Worst Songs: 40 dp art, title, `artist · year`, `Top N%` pill, `#rank of total`.
- Adaptive (`core/bands/BandLayout.panes`, unit-tested): one centered column (≤840 dp) in compact/medium windows; **two independently scrolling panes** (members/summary/statistics | history/songs) when the **window** is expanded (≥840 dp, e.g. book fold open: 851 dp) or a vertical hinge is separating (half-open). The split sits exactly on the most central vertical fold/hinge (`windowPosture.hingeList`) when it is separating, or when it is flat but leaves each pane ≥40% of the width (book fold open); the hinge width is the gap. Otherwise (no fold, or a tri-fold's off-centre flat folds) the panes are equal, 24 dp apart.

## Quick Links

Web `BandPage` items (`BandQuickLinks.sections()`): Members, Summary, Statistics, Rank History, Songs (TalkBack: Band Summary / Band Statistics / Band Rank History / Band Songs), in the top bar or phone floating toolbar while the page is one scrolling column. The page is a `verticalScroll` column, so `ui/quicklinks/ScrollQuickLinks.kt` adapts it to the shared controller (sections record content offsets; jumps are one instant `scrollTo`). Two panes show every section side by side, so no Quick Links there.

## IDs

`fst.band.screen`, `.title`, `.subtitle`, `.unresolved`, `.error`, `.content`, `.pane.leading`, `.pane.trailing`, `.members-section`, `.member.<accountId|unknown>`, `.summary-section`, `.statistics-section`, `.stat.<id>`, `.rank-by`, `.rank-by.<metric>`, `.history-section`, `.history-chart`, `.history-row.<date>`, `.history-empty`, `.songs-section`, `.best-songs`, `.worst-songs`, `.song-row.<songId>`.

## Open

- No instrument-combo filter (`?combo=`), no Select Band Profile (both need a selected-band identity); rank links open page 1 of Band Rankings (no `rankBy`/page route parameters).
