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
- Adaptive: one centered column (≤840 dp) on compact/medium; **two independently scrolling panes** (members/summary/statistics | history/songs) at ≥840 dp, or split exactly at a vertical separating hinge (`currentWindowAdaptiveInfo().windowPosture.hingeList`) with the hinge width as the gutter (book and passport folds open, tri-fold).

## IDs

`fst.band.screen`, `.title`, `.subtitle`, `.unresolved`, `.error`, `.content`, `.pane.leading`, `.pane.trailing`, `.members-section`, `.member.<accountId|unknown>`, `.summary-section`, `.statistics-section`, `.stat.<id>`, `.rank-by`, `.rank-by.<metric>`, `.history-section`, `.history-chart`, `.history-row.<date>`, `.history-empty`, `.songs-section`, `.best-songs`, `.worst-songs`, `.song-row.<songId>`.

## Open

- No instrument-combo filter (`?combo=`), no Select Band Profile, no Quick Links yet; rank links open page 1 of Band Rankings (no `rankBy`/page route parameters).
