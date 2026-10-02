# iPhone Duo redesign notes
Journey: Songs → Song Detail → Song Leaderboard, plus shell (rail, global search, profile sheet). Next journey: Leaderboards → Full Rankings → Player (Stages 1–3 below); then Profile/Statistics, Rivals.
Stack: SwiftUI (TabView + NavigationStack/NavigationSplitView, system toolbars); package iOS 17; Xcode 27.1 / iOS 27.1 SDK (App Store archive: 27.0 SDK, Duo APIs compiled out). Evidence: folded portrait in the iOS 27.1 sim; Device Hub poses still blocked (no Accessibility grant), so inner/book/landscape poses are hosted renders and unit tests only.
Stage: 5 (journey 1), 3 (journey 2)  Next: operator answers J1–J3; grant Accessibility for Device Hub scripting to capture inner poses and fold/unfold (D1, D6).

## Findings (journey 1)
- Build/size classes: Ready — `DeviceLayout` from size classes, safe area, regions; no `UIScreen.main` [T461, HIG].
- Containers and item content: Ready — system bars; every rail item a `Label` with a symbol; system bell badge [HIG, T462].
- Outer layout, profile sheet, fold/camera handling: Ready (sheet Close in its own side bar, operator #3) [T461, T466, HIG].
- Continuity: Change (open) — Songs/Solo-leaderboard row accessibility frames span 0–466 pt, under the rail (XCUI tree). `List` ignores padding-as-clearance (B6); needs a measured fix [HIG, T466].
- N/A: camera, multiwindow, scene accessories, `ArrangementView` (dual-source shelved), Game Center (route false match).

## Decisions
- Operator 2026-09-28 (stand): dual-source top/bottom shelved; two populated columns, never an empty pane; modal Close in the sheet's toolbar; rail keeps Bell + Profile.
- D1 Inner portrait (669 pt): chosen two columns, side by side, populated, flat or half-open (operator, 2026-10-02) — supersedes "portrait = one column"; reason: HIG alignment.
- D2 List/detail and regular section set gated on size classes (regular × regular), not hinge pose + 760 pt: chosen (operator, 2026-10-02).
- D3 Search `.high` with Bell/Profile, Sort `.automatic`: chosen (operator, 2026-10-02).
- D4 Song Detail Paths/Item Shop ahead of Quick Links: chosen (operator, 2026-10-02).
- D5 Paged leaderboards keep the tab bar; Previous/Next `.high`: chosen (operator, 2026-10-02). As built only Next is `.high`: the folded rail fits one bottom item, and two `.high` items kept the disabled Previous on page 1 (agent, measured).
- D6 Keep the stack↔split swap, restore list scroll: chosen (operator, 2026-10-02). Built as scroll-to-open-song after a switch.
- D7 default bar placement for single-Close sheets; D8 no table-pose layout; D9 system bar side: chosen (operator, 2026-10-02).

## Done / verified
- Shop item titled in the vertical bar — unit tests; sim: Item Shop in the Song Detail rail.
- No fixed spacer in the vertical bar — unit tests; sim: rail fits three root items.
- D1/D2 `DeviceLayout.isRegularInBothDimensions` gate — unit + hosted tests (inner portrait flat/half split, auto-selected); sim not run (no inner pose).
- D3 — sim: Songs rail Search, Bell, Profile, "…" (Sort/Filter/Menu in "…").
- D4 — sim: Song Detail rail Back, Item Shop, "…" (Paths, Quick Links in "…"); pinned title omitted in the rail.
- D5 — sim: with both `.high` the one bottom slot held the disabled Previous; after the Next-only change Full Rankings shows Next in the rail.
- D6 `ListDetailScrollRestore` — unit tests; runtime fold/unfold not run (no poses).
- Not run: Split View, PiP, keyboard overflow, Reduce Transparency, RTL, App Resizability, physical device.

## Journey 2 (Stages 1–3): Leaderboards → Full Rankings → Player (folded captured; inner code-only)
- Compete/Leaderboards root: Ready — rail Search, Bell, Profile, "…" (Menu, Quick Links) [HIG, T462].
- Full Rankings bar: Change — instrument icon + Rank By share one custom `HStack` item, forcing a horizontal top bar; the instrument menu is a 28×36 pt target [T462; HIG Accessibility 44 pt].
- Full Rankings pager: Ready — Next stays in the rail; First/Previous/Last/page label in "…" (D5) [HIG, T462].
- Full Rankings rows: Decision — names truncate to ~5 characters folded; worse in the inner list column [HIG Layout].
- Player: Ready — rail Back, Switch To This Profile (titled), "…" (Quick Links, Search, Profile) [HIG, T462].
- Detail columns: Change — 2-column dashboard grids key off the window size class, so a ~350 pt split detail would get two columns [HIG Layout].
- Pending J1 Instrument switcher: titled `Label` with the instrument image in the rail, or a pill in the content. Recommended: split Rank By into its own item; instrument as a titled `Label` if the rail accepts the image, else a content pill.
- Pending J2 Narrow rows: drop the songs-played column when the row can't fit it (`ViewThatFits`), or wrap to two lines. Recommended: `ViewThatFits`.
- Pending J3 Grids by column width (`onGeometryChange`) instead of the window size class. Recommended: yes.
