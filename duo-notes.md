# iPhone Duo redesign notes
Journey: (1) Songs → Song Detail → Song Leaderboard + shell; (2) Leaderboards → Full Rankings → Player; (3) Profile/Statistics → Rivals → Rival Detail/Rivalry (Stages 1–3).
Stack: SwiftUI (TabView + NavigationStack/NavigationSplitView, system toolbars); package iOS 17; Xcode 27.1 / iOS 27.1 SDK (App Store archive: 27.0 SDK, Duo APIs compiled out). Evidence: folded portrait live in the iOS 27.1 sim; Device Hub poses still blocked (no Accessibility grant, re-checked 2026-10-02), so inner/book/landscape poses are hosted renders and unit tests only.
Stage: 5 (journeys 1–2), 3 (journey 3)  Next: operator answers R1–R4 (journey 3) and the two open items (J1 target, row frames); grant Accessibility for Device Hub to capture inner poses.

## Decisions (all operator, 2026-10-02 unless noted)
- Journey 1: D1 inner portrait = two populated columns, flat or half-open; D2 size classes (regular × regular) gate list/detail; D3 Search `.high` with Bell/Profile; D4 Song Detail Item Shop/Paths before Quick Links; D5 paged boards keep the tab bar, Next `.high` (Previous dropped, measured); D6 keep stack↔split swap, restore list scroll; D7 default bar for single-Close sheets; D8 no table-pose layout; D9 system bar side. Standing (2026-09-28): dual-source shelved; modal Close in the sheet toolbar; rail keeps Bell + Profile.
- J1 Board switchers: instrument (or band size) and Rank By are separate titled rail items; instrument as a titled `Label` if the rail accepts its image, else an in-content pill; instrument target ≥ 44×44 pt.
- J2 Narrow rows drop songs played/total when they don't fit, so names don't truncate.
- J3 Duo split columns get their own width class via `DeviceLayout.column(width:)`.

## Done / verified (journey 2)
- J1 built (Full + Band Rankings, `ToolbarItemGroup` on vertical bar only) — sim folded: no top bar; rail Back, `…`, Next; `…` lists Search, "Lead" with its artwork, "Total Score", Profile, pager; instrument picker opens. The rail accepted the image, so no pill.
- J1 target: system metrics only (rail button 38×38, overflow row 250×42 pt; old custom item 28×36). Open: accept, or use the 44 pt pill on the vertical bar too.
- J2 built with the section-wide #38 fit (`rowInset: 32`), not per-row `ViewThatFits`, so columns stay aligned — sim folded: songs column hidden, names full ("Cardinalsfan0351"); VoiceOver value keeps songs; hosted test `paddedRowsDeclareTheirInset`.
- J3 built (`ListDetailPolicy.detailColumnWidth`, list column compact; sheets keep form size via `windowWidthClass`) — unit `duoSplitDetailColumnIsCompact` (349 / 561 / book 394 pt), hosted `duoSplitColumnsSeeCompactWidth` renders at 669×951 and 951×669 (`hig2/duo-j3-split-*.png`); not observed on the inner display.
- Row a11y frames under the rail: measured, not fixed. Songs rows {0, 466} in a 466 pt `CollectionView` (rail from x≈396); padding by the measured 98 pt safe area left the collection view full width (UIKit sizes it). Reverted. Open: accept system list behaviour, or move Songs/song leaderboards to `ScrollView` + `LazyVStack` (Full Rankings rows are 16–366, fine).
- Not run: Split View, PiP, keyboard overflow, Reduce Transparency, RTL, App Resizability, physical device, inner-display captures.
- Journey 1 (earlier pass): D1–D6 built; folded verified live, inner portrait via hosted renders; fold/unfold not run.

## Journey 3: Statistics → Rivals → Rival Detail/Rivalry (folded captured `hig2/j3-*`; inner code-only)
- Statistics root: Ready — rail Search, Bell (badge), Profile, `…` (Quick Links); stat tiles inside the safe area [HIG, T462].
- Player/Statistics dashboard: Ready — 2 instrument columns at regular width (even count), 1 in a split detail (J3) [HIG Layout, T463].
- Rivals hub bar: Decision — rail fits Back, Search, `…`; the page action Find Rival overflows behind global Search (D3) [HIG visibility priority].
- Rivals Leaderboard tab Rank By: Change — in-content footnote `Menu`, under 44 pt [HIG Accessibility 44×44].
- Segmented Song/Leaderboard control: Ready — content control, 350×31 system metric [HIG].
- Rival Detail/Rivalry: Ready (code) — Back, titled View Profile, Quick Links; not captured [HIG, T462].
- Inner display: Rivals list column (~320 pt) + Rival Detail, W2 auto-select: Ready (hosted renders only) [HIG split views].
- Find Rival sheet: Decision — custom inline field in a `Form` (list rows under the sheet's bar, as B6), vs system `.searchable` [HIG Search fields].
- N/A: camera, multiwindow, scene accessories, `ArrangementView`, table pose.
- Pending R1 Rivals rail: Find Rival `.high` on the Rivals hub (global Search moves to `…`), or keep D3. Recommended: Find Rival `.high`.
- Pending R2 Rivals Rank By: keep in content with a 44 pt target, or move to a titled toolbar item (only on the Leaderboard tab). Recommended: keep in content, 44 pt.
- Pending R3 Statistics inner portrait (~300 pt tiles): keep 2 columns, or one column below a tile width. Recommended: keep 2 until an inner capture shows the charts.
- Pending R4 Find Rival: keep the inline field, or adopt `.searchable` in the sheet. Recommended: keep (A2 owns the sheet-focus bug).
