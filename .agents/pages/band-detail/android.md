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
- Members: glass cards: name + 28 dp instrument icons; linkable members open `PlayerRoute`, anonymous members are dimmed and inert. Columns come from `BandLayout.memberColumns` (≥260 dp, wider when the widest member's icons and a 96 dp name need it, so an 800 dp tablet column keeps one card per row); the card stacks the name above a wrapping icon row whenever `BandLayout.memberInline` says the name would not fit beside the icons (large text, or a ~290 dp fold pane).
- Band Summary (Type, Appearances, Members) and Band Statistics tiles (2–4 columns by width; `BandLayout.statColumns` drops to one tile per row at large text on narrow windows so values never clip). Rank By is an outlined button + dropdown menu (four long labels do not fit a phone segmented row); default Total Score; the current metric carries a check icon and `Selected` state (M3 menus: the selected item is visibly distinct), and reselecting it only closes the menu. At large text the Statistics heading stacks above Rank By; otherwise an 8 dp top inset keeps the 48 dp button off the tiles above. The rank tile links to `BandRankingsRoute`, Best Song Rank to Song Detail once the best song resolves.
- Band Rank History: static Canvas line (best rank at the top, redrawn only when data or metric change) plus the 10 newest snapshots (date, rank, metric value); `No band rank history yet.` when empty.
- Five Best / Five Worst Songs: 40 dp art, title, `artist · year`, `Top N%` pill, `#rank of total`; at large text the pill and rank move under the title so titles wrap at word boundaries.
- Empty and status texts use Body Medium (M3 body role), matching the section notes.
- Adaptive (`core/bands/BandLayout.splits` + `panes`, unit-tested): one centered column (≤840 dp) in compact/medium windows; **two independently scrolling panes** (members/summary/statistics | history/songs) when the **window** is expanded (≥840 dp, e.g. book fold open: 851 dp) or a vertical hinge is separating (half-open), unless TalkBack or large text on a narrow window force one column. The screen makes this decision once, and both the pane layout and Quick Links read it (a copy pushed up from the content through a `LaunchedEffect` once left Quick Links showing beside two panes after a resize). The split sits exactly on the most central **separating** vertical fold/hinge (`windowPosture.hingeList`, book posture); the hinge width is the gap. A flat (fully unfolded) fold never anchors it: flat, with no fold, or on a tri-fold the panes are equal, 24 dp apart, meeting at the midpoint of the content area beside the rail (owner override #361, [split-panes](../../patterns/split-panes.md)).

## Quick Links

Web `BandPage` items (`BandQuickLinks.sections()`): Members, Summary, Statistics, Rank History, Songs (TalkBack: Band Summary / Band Statistics / Band Rank History / Band Songs), in the top bar or phone floating toolbar while the page is one scrolling column. The page is a `verticalScroll` column, so `ui/quicklinks/ScrollQuickLinks.kt` adapts it to the shared controller (sections record content offsets; jumps are one instant `scrollTo`). Two panes show every section side by side, so no Quick Links there.

## IDs

`fst.band.screen`, `.title`, `.subtitle`, `.unresolved`, `.error`, `.content`, `.pane.leading`, `.pane.trailing`, `.members-section`, `.member.<accountId|unknown>`, `.summary-section`, `.statistics-section`, `.stat.<id>`, `.rank-by`, `.rank-by.<metric>`, `.history-section`, `.history-chart`, `.history-row.<date>`, `.history-empty`, `.songs-section`, `.best-songs`, `.worst-songs`, `.song-row.<songId>`.

## Open

- No instrument-combo filter (`?combo=`), no Select Band Profile (both need a selected-band identity); rank links open page 1 of Band Rankings (no `rankBy`/page route parameters).

## Validation (issue #119, live public service)

Quads band route (4 members × 7 instruments), `FST_*` AVDs, animator scale 0 except the motion recording.

| Configuration | Result |
|---|---|
| FST_Phone portrait/landscape, font 1.0 | One column, Quick Links in the floating toolbar; Rank By menu marks Total Score with a check |
| FST_Phone font 2.0 portrait/landscape | Fixed: stat values clipped, names and song titles broke mid-word, Statistics heading wrapped beside Rank By. Now one tile per row, stacked members and song rows, heading above Rank By |
| FST_Tablet landscape (1280 dp) / portrait (800 dp) | Two panes / one column. Fixed: portrait member names truncated in 2 columns (now 1 per row); Rank By touched the summary tiles (now 8 dp inset) |
| FST_Resizable phone / foldable (841 dp flat fold) / tablet / desktop, font 1.0 and 2.0 | Fixed: ~290 dp fold pane truncated member names (now stacked); Quick Links could stay visible beside two panes after a resize (now one pane decision) |
| FST_Book_Fold folded / unfolded / half-open, font 1.0 and 2.0, folded landscape | Folded: one column; open/half: panes split at the fold |
| FST_Passport_Fold folded / unfolded, font 1.0 and 2.0 | Folded: one column; unfolded (~895 dp): two panes, members stacked in the narrow pane; font 2.0: one column |
| FST_TriFold folded / partial / unfolded, font 1.0 and 2.0 | Folded and partial: one column; unfolded: equal panes (off-centre flat folds do not anchor) |

- Theme: the app is dark-only by design ([design/android.md](../../design/android.md)), a deliberate deviation from M3 dynamic light/dark; the system light setting leaves the page unchanged.
- Rank history on the live service is empty (`historyStatus` says history writes are disabled); the chart state is covered by Robolectric fixtures.
- TalkBack (real, FST_Phone): top bar → heading → subtitle → Members → member cards (name + instruments) → Summary → Statistics → `Rank by Total Score` button → tiles → History → songs → bottom navigation → Quick Links, current section. Clickable cards use M3 `Surface(onClick)` (actionable, no Button role), like the rest of the app.
- Tests: `BandsUiTest` (states, rank-by selection state, large text reflow, expanded panes), `BandsCoreTest` (`splits`, `panes`, `statColumns`, `memberColumns`, `memberInline`), connected `BandsSettingsJourneyTest` with the ATF accessibility validator.
