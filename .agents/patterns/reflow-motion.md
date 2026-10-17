# Reflow motion: content glides and fades when a layout changes

> **What:** how content moves when a page's layout changes under it: a split pane opening or closing, a window crossing a column threshold, cards rewrapping. Moved content glides to its new place, content that arrives or leaves fades, and motion goes away under Reduce Motion. **Read when:** you change how a split pane opens or closes, change a page's column count or wrap, or add a layout that reflows on resize.

Status: **current**, 2026-10-16. Provenance: #669 (Windows, split from #666; agent decision below). Apple and Android precedents: `OnDemandSplit` geometry animation (#344, #583), `DualSourceLayout` regions, Android `animateContentSize`.

## Intent

A layout change reads as the same content rearranging, not as a new page. A card that moved can be followed with the eye to its new place, and a pane that opens or closes visibly arrives from or leaves toward its edge. Nothing reloads, no load stagger replays, and the reader keeps their place.

## Web source (behavior reference)

| Web | Behavior |
|---|---|
| `FortniteFestivalWeb/src` (none) | The web has no reflow motion: CSS grids and its panels re-lay out instantly on resize. This is native motion behavior (Apple's and Fluent's motion guidance), not a web parity item. |

## Rules

1. **R1. Moved content glides.** When a reflow event (a split opening or closing, a column-count change, cards rewrapping) moves content that stays on screen, it animates from where it was drawn to its new place over the reflow duration. Layout itself is final at once; only the drawing moves.
2. **R2. Arriving and leaving content fades.** A pane or card that a reflow brings into view fades in, and a pane that a reflow removes fades out while it leaves, instead of appearing or vanishing in one frame. A split pane also slides from or toward its trailing edge as it fades.
3. **R3. Reflow is not a reload.** A reflow never starts a read, shows a spinner, changes an item's identity, replays a load stagger ([load-transition](load-transition.md)) or loses the reader's place ([wide-columns](wide-columns.md) R4, [back-keeps-place](back-keeps-place.md)). Content still running its load stagger finishes that stagger instead of gliding.
4. **R4. Reduce Motion removes it.** With the system's reduced-motion setting (Windows: Settings › Accessibility › Visual effects › Animation effects, `UISettings.AnimationsEnabled`; Apple Reduce Motion; Android Remove animations) or the app's Reduce Motion switch, a reflow is instant: no glide, no fade, no slide, and a move already running stops in place.
5. **R5. Reflow motion costs nothing per frame on the UI thread.** It runs only on reflow events, never per scroll frame. Where a platform's layout pass is too slow to repeat every frame (Windows: a list relayout is 30–60 ms), the motion is drawn by the compositor from one final layout instead of animating widths.
6. **R6. Timing.** 300 ms on a decelerate curve: Windows Fluent `(0, 0, 0, 1)` ("Fast Out, Slow In"), Apple `.smooth(duration: 0.3)`, Android `tween(300)`. An interrupted reflow starts from where the content is drawn now.

**Agent decision (#669, 2026-10-16; the owner may override with `/choose`).** The owner: "Reflow is not animated and content doesn't nicely fade in/out; reflow should animate and content should animate move, fade in, fade out, etc." Options for the Windows split: A, the list re-lays out once at its new width while the compositor slides and fades the pane in from its trailing edge, and on close slides and fades it out over the widened list, uncovering it with an animated clip (chosen: the WinUI `SplitView`/`NavigationView` pane behavior, compositor-only, Fluent "use implicit animations … to animate layout changes"); B, animate the list column's width every frame like Apple's `OnDemandSplit` (rejected: measured 30–60 ms per list relayout on Debug and Release builds, about 10–15 frames per second, which breaks R5 and the scroll-perf budget); C, a crossfade of the whole section (rejected: content does not move, so the eye cannot follow it, against R1). Card reflows (Suggestions, Profile/Statistics sections, Item Shop grid) use one FLIP glide per card (old position minus new, animated to zero on the compositor) and fade in cards that arrive. Fluent motion: "Fast Out, Slow In" for elements entering, and "Motion is … connected" so layout changes are not abrupt; Fluent timing guidance and the shared 300 ms of the Apple and Android splits set the duration.

## Canonical implementation

| Sub-behavior | Apple | Android | Windows |
|---|---|---|---|
| Split pane open/close (R1, R2) | `apple/Sources/FestivalUI/App/Layout/OnDemandSplit.swift` `OnDemandSplitLayout` (split geometry `.animation`, nil under Reduce Motion) | `android/app/src/main/java/com/festivalscoretracker/android/ui/common/OnDemandSplit.kt` `OnDemandSplit` (leading width over 300 ms, instant under Reduce Motion) | `windows/Festival.App/Controls/OnDemandSplitHost.cs` `OnDemandSplitHost` (`ApplyLayout`, `StartMove`, `EndMove`) with `windows/Festival.App/Controls/ReflowMotion.cs` `ReflowMotion.SlidePane`, `SettlePane` |
| Card glides and fades (R1–R3) | `apple/Sources/FestivalUI/App/Layout/DualSourceLayout.swift` (regions `.smooth(0.3)`, nil under Reduce Motion) | `animateContentSize` in `GraphCardList`, `FloatingToolbar` (not a card FLIP) | `windows/Festival.App/Controls/ReflowMotion.cs` `ReflowMotion` (`Move`, `Enter`, `Capture`, `Play`, `PlayAfterLayout`, `KeepFocus`); `windows/Festival.App/Controls/LeaderboardsCardGridLayout.cs` (Profile/Statistics sections); `windows/Festival.App/Pages/SuggestionsPage.xaml.cs` `UpdateColumns`; `windows/Festival.App/Pages/ShopPage.xaml.cs` `OnGridSizeChanged` |
| Timing and policy (R4–R6) | `.smooth(duration: 0.3)` | `tween(300)` | `windows/Festival.Core/Domain/MotionPolicy.cs` `ReflowTiming` (`Duration`, `Spline`, `PaneOffset`, `AnimatesSplit`, `InView`, `Near`); `windows/Festival.App/Services/Motion.cs` `Motion.Allowed` |

**Windows details.** The split host changes its columns once. Opening, the pane slides from its trailing edge (`ReflowTiming.PaneOffset`, pane width to 0) while fading in. Closing, the pane stays laid out over the widened list's trailing half and slides out while fading, as an `InsetClip` on the list's right edge uncovers it; when the compositor reports the batch complete (or Reduce Motion is on) the pane collapses and the list is unclipped. Focus returns to the opener as before (#652). A card reflow captures each realized card's position keyed by its item (Suggestions rebuilds its line containers, so element identity cannot be the key), skips containers a list parks far outside its viewport (`ReflowTiming.Near`), and starts the glides on the first `LayoutUpdated` after the reflow: inside `SizeChanged`, `UpdateLayout` does not lay the new arrangement out, and `CompositionTarget.Rendering` would draw one frame at the new place first. Keyboard focus survives a reflow that recycles its container (R3): `ReflowMotion.KeepFocus` redirects the list's programmatic focus move out of the host (to the title bar's Back) to the control that now carries the same Automation ID, within one second of the reflow, and leaves user moves (Tab, clicks) alone. R4 in flight: turning Animation effects off or the app's Reduce Motion on raises `Motion.Changed`. `UISettings.AnimationsEnabledChanged` did not arrive within a 3 s move in a desktop app, so the shell also listens for the `WM_SETTINGCHANGE` broadcast for `SPI_SETCLIENTAREAANIMATION` on its window subclass (`OcclusionTracker.AnimationsSettingChanged`), which Settings sends. A Reduce Motion change can re-apply the split layout before `Motion.Changed` arrives; that settle counts as the stop too. `OnDemandSplitHost` observes it while loaded and ends a running move through its usual settle (an opening pane shows in place; a closing one leaves). `ReflowMotion` observes it only while a glide or fade runs, and then stops every one at its settled state (no translation, full opacity). Debug/automation hooks: `FST_DEBUG_REFLOW_MS` stretches moves (300–10000 ms) so automation can switch mid-move, and `FST_DEBUG_MOTION_KEY=1` adds Ctrl+Alt+Shift+M, which flips the app's Reduce Motion.

**Tests (Windows).**
- **Unit:** `MotionPolicyTests` (`Reflow*`: duration, curve, progress, pane offset, `Near`, `InView`, split gate, the stretch hook's bounds).
- **Journeys:** `tools/windows/reflow_journey.py`, with the judges in `tools/windows/reflow_trace.py` (`tests/test_reflow_trace.py` runs in CI). `ci_ui.py` runs it as the `reflow` runner.
  - The Rivals split opens and closes, runs its whole move and returns focus to the opener.
  - Suggestions, Statistics and the Item Shop grid glide cards across a wide ↔ medium resize without re-arming a load stagger.
  - The `--reduce-motion` variants, and Statistics with the app's own Reduce Motion setting (`statistics-setting-reduced`), are instant: card-grid traces report `moved=0 entered=0`.
- **Accessibility:** `tools/windows/journeys/a11y-reflow.json`.
  - Split open/close focus and reading order.
  - Suggestions keeps focus on its row and its reading order across a resize.
  - Profile/Statistics keeps focus on a Bass stat tile, Level 2 headings and Lead → Bass order across a resize.
  - The Shop grid after a resize.
  - Suggestions and Statistics stay one column at 225% text.
  - Each of these runs in the matrix's `no-animations` and `app-reduced` modes, where `reflow_trace` requires instant reflows.
  - R4 in flight: `reflow-stop-split-rivals` and `reflow-stop-statistics` turn Animation effects off (`animations:off`, restored by the matrix) and the app's Reduce Motion on mid-move. `reflow_stops` requires each split to settle `stopped=1` before its move would end, and a `reflow-stop` after each moving card reflow.

## Consumers

| Surface | Apple | Android | Windows |
|---|---|---|---|
| On-demand split (Rivals, All Rivals, Leaderboards, Song Detail) | adopts | adopts (width) | adopts (#669) |
| Settings list/detail (split-panes R6) | adopts | — | follow-up: its page-level halves switch instantly |
| Suggestions columns | adopts | — | adopts (#669) |
| Profile/Statistics instrument sections | adopts | — | adopts (#669) |
| Item Shop grid | — | — | adopts (#669) |
| Songs instrument chip rows | — | — | exempt: recycled virtualized rows; per-row motion would cost scroll frames (R5) |

## Known debt

- Windows Settings list/detail (split-panes R6) still switches between one column and halves instantly.
- Android and Apple card reflows other than their split geometry are not audited against R1–R2.

## Guards (`tools/pattern_guard.py`)

None yet.
