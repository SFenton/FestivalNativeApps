# All Rivals — Android notes

> **What:** Android state of `/rivals/all`. **Read when:** changing `AllRivalsScreen` / `AllRivalsViewModel` in `android/`. Full Rivals notes (data, scope, IDs, tests): [../rivals/android.md](../rivals/android.md).

- `AllRivalsRoute(scope)` carries a `RivalScope` token; `settings:common|combo` resolve against Settings at load (`RivalScopes.resolveList`), and an unresolvable scope shows "This rivals list could not be identified."
- Common Rivals intersects every chart's full list. Charts without rivals are ignored, as their web 404 leaves no data. A chart whose read fails (e.g. a live 503) is left out, like the hub's Common card (`loadCommonLists`); the page fails only when every chart fails. A leaderboard list shows "Your rank: #N · Total Score"; combos list their charts.
- Rows (above, then below) push Rival Detail with the same scope, in the adaptive grid (1–2 columns, split at a separating hinge). States: loading, shared service status (freeze countdown), empty, no player.

## Header (decision, issue #108)

- The top app bar alone carries the title ("Lead Rivals", "Common Rivals", the combo name). M3 `top-app-bar.md`: "Use when: Every screen needs a title and optional actions", with the title in Title Large. Repeating it as a content heading read it twice to TalkBack and cost a row on phones. Player Bands uses the same `title = null` pattern.
- An optional subtitle row (`fst.all-rivals.subtitle`, `bodyLarge`, secondary text, 28 dp instrument icon for a single chart) carries the rank line or the chart list. It keeps the full combo chart list when the bar truncates the title (Passport folded).

## Validation (issue #108, live service, SFentonX)

| Configuration | Finding |
|---|---|
| FST_Phone portrait, font 1.0 / 2.0 | Fixed: at 2.0 the "songs behind" pill was clipped (`IntrinsicSize.Min` + `FlowRow` under-reports its height). `RivalRow` now draws its 4 dp tint bar with `drawBehind` (RTL-mirrored), so the row measures to its wrapped pills. |
| FST_Phone, Common scope | Fixed: live `Solo_PeripheralBass` returned 503 during a post-process freeze, and the whole page showed the service status. It now lists the rivals of the charts that loaded. |
| FST_Phone, landscape | One column, pills on one line. |
| FST_Tablet landscape / portrait, font 2.0 | Two columns in row-major order (landscape), one column (portrait); rows grow at 2.0 with nothing clipped. The rail hides labels at 2.0 (shared navigation). |
| FST_Resizable phone / foldable / tablet / desktop | One, one, two and two columns; rows stay readable at desktop width, so no extra max-width cap. |
| FST_Book_Fold folded / unfolded / half-open | Folded pills wrap at 2.0; unfolded one column; half-open two columns meeting at the hinge, filled masonry-style by the shared `AdaptiveCardGrid` (TalkBack follows list order). |
| FST_Passport_Fold folded / unfolded (combo) | Unfolded shows the full combo title. Folded truncates the bar title, and the subtitle keeps the whole chart list. |
| FST_TriFold folded / partial / unfolded | One column, one column with the rail, two columns with the rank subtitle. |
| Light theme | The app stays dark: dark-only by design ([../../design/android.md](../../design/android.md)). |
| Reduced motion (animator scale 0) | Rows appear at once; with animations on, the staggered fade-in and scrolling stay smooth. |

- TalkBack (Phone): title → Search → Notifications → Profile → "Your rank: #4 · Total Score" → each row as one button ("Name, ahead of you|you lead, N songs ahead, N songs behind"). Back is labelled "Back".
- Touch targets: the bar buttons are 48 dp and rows are 85 dp tall. Pill text contrast on the real backgrounds: win about 9.9:1, lose about 7.4:1.

## Tests

`AllRivalsUiTest` (Robolectric: leaderboard rank line and accessible rows, single chart without header and anonymous rows, Common with a failed chart, combo chart list, loading → rows, every chart failing → status → Retry, empty, unresolvable combo, wide two-column grid), `RivalRowUiTest.wrappedPillsGrowTheCardAtLargeText` (fails on the old `IntrinsicSize.Min` row; shared with issue #107), `RivalsViewModelTest.commonRivalsLeavesOutFailedChartsAndFailsOnlyWhenEveryChartFails`. Connected: `RivalsDeviceJourneyTest.allRivalsListFitsAndOpensDetail` on FST_Phone and FST_Book_Fold half-open.
