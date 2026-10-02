# iPhone Duo redesign notes
Journey: Songs → Song Detail → Song Leaderboard, plus shell (rail, global search, profile sheet). Next journeys: Leaderboards → Full Rankings → Player; Profile/Statistics; Rivals.
Stack: SwiftUI (TabView + NavigationStack/NavigationSplitView, system toolbars); package iOS 17; Xcode 27.1 / iOS 27.1 SDK (App Store archive: 27.0 SDK, Duo APIs compiled out). Evidence: folded portrait only, sim iOS 27.1; Device Hub poses blocked (no Accessibility grant), so folded landscape, inner and book poses are code-only.
Stage: 3  Next: operator answers the pending decisions below, then Stage 4.

## Findings
- Build/size classes: Ready — vertical bars present; `DeviceLayout` from size class, safe area, regions; no `UIScreen.main` [T461, HIG].
- List/detail gate: Decision — `pose != .standard` (from `onHingeChange`) + 760 pt width breakpoint [T461, T466 avoid breakpoints; T464 hinge never for layout].
- Containers: Ready — system `TabView`/`toolbar`/`NavigationSplitView`; page tools leave the tab accessory for the rail [T462].
- Items: Ready — every rail item is a `Label` with a symbol (Sort, Filter, Quick Links, Search, Paths, bell, Profile); bell uses the system badge [HIG, T462].
- Song Detail Shop: Change (done) — breathing custom view was missing from the rail and its overflow [HIG, T462].
- Fixed spacer before bell/profile: Change (done) — vertical bar now adds none; rail gained Sort [HIG].
- Overflow priority: Decision — Songs: Search overflows; Song Detail: Paths, Shop overflow while Quick Links stays; Song Leaderboard: First/Previous/Next/Last all in "…" [HIG, T462].
- Song Detail pinned title (principal custom view): Ready — not drawn in the rail, no forced top bar (observed) [T462].
- Outer layout: Ready — inset content, backgrounds behind bars; scrubber uses `cutoutInsets` [T461, T466].
- Profile sheet: Ready — Close in the sheet's own side bar (operator #3). Single-item opt-out: Decision [T462].
- Inner display: Ready (code) — split in landscape, 2-column dashboard grids, regular section set [HIG, T466].
- Fold/camera: Ready (code) — `NavigationSplitView` handles the fold; occlusion feeds `overlayInsets` [HIG, T463].
- Continuity: Decision — stack↔split swap on fold keeps the selection but loses scroll position and screen `@State` [HIG, T466].
- Continuity: Change — Songs and Solo-leaderboard row accessibility frames span 0–466 pt, under the rail (XCUI tree) [HIG, T466].
- Ready: 9 · N/A: camera, multiwindow, scene accessories, `ArrangementView` (dual-source shelved), Game Center (route false match; not a game).

## Decisions
- Already decided (operator, 2026-09-28): portrait (half or flat) = normal portrait layout, dual-source shelved; two populated columns when width allows, never an empty pane; modal Close in the sheet's own toolbar; rail keeps Bell + Profile, list/detail on the inner display.
- D1 Inner portrait (669 pt, regular): HIG expects several panes inside; operator #1 says one column. Recommended: keep one column as a recorded deviation; chosen pending.
- D2 Gate list/detail on size class plus vertical-bar presence, not hinge pose + 760 pt (same behavior). Recommended: yes; chosen pending.
- D3 Rail priority (Songs): Search vs Sort/Filter. Recommended: Search `.high` with Bell/Profile, Sort `.automatic`; chosen pending.
- D4 Song Detail priority: Paths and Item Shop ahead of Quick Links (page-unique actions). Recommended: yes; chosen pending.
- D5 Paged leaderboards: task-focused `.prefersToolbarItems`, or Previous/Next `.high`. Recommended: Previous/Next `.high`, keep tab bar; chosen pending.
- D6 Fold continuity: one always-present `NavigationSplitView` vs current swap. Recommended: keep swap until iPadOS phase, but restore list scroll; chosen pending.
- D7 Single-Close sheets: disable vertical bar? Recommended: no (default placement); chosen pending.
- D8 Table-pose layout: Recommended none (HIG: no per-pose layout; T466 optional); chosen pending.
- D9 Bar side in RTL/landscape: Recommended system default, no override [HIG, T461 tension]; chosen pending.

## Done / verified
- Shop item titled in the vertical bar (`SongDetailShopActionStyle`) — unit tests; sim: "Item Shop" now in Song Detail "…".
- No fixed spacer in the vertical bar (`RootChromeTrailingGroups.separatesSearch`) — unit tests; sim: rail shows Sort, Bell, Profile, "…".
- iPhone unchanged by both (gated on vertical bar) — code review only; iPhone sim not run.
- Not run: folded landscape, inner display, book pose, Split View, PiP, keyboard overflow, Reduce Transparency, RTL, App Resizability.
