# Load transition

> **What:** first-load gates, reload swaps, graph card list swaps and row entrances for pages, boards and data-backed modal content. **Read when:** a load, refresh, selector, page or modal switch changes visible data.

Status: **current**, 2026-10-05. Provenance: #30, #60, #61, #70, #71, #149, #169, #260, #261.

## Intent

Loading must communicate a deliberate state change rather than a hard cut: first loads gate incomplete content, reloads replace stale content through a spinner, and row entrances run once per reveal rather than while the reader scrolls.

## Web source (behavior reference)

| Web | Behavior |
|---|---|
| `FortniteFestivalWeb/src/hooks/data/useLoadPhase.ts` (`useLoadPhase`) | Load/reload phase machine and spinner timing. |
| `FortniteFestivalWeb/src/components/page/LoadGate.tsx` (`LoadGate`) | First-load spinner gate and content reveal. |
| `FortniteFestivalWeb/src/components/leaderboard/PaginatedLeaderboard.tsx` (`PaginatedLeaderboard`) | Board reload spinner, row stagger and pinned footer. |
| `FortniteFestivalWeb/src/pages/songinfo/components/path/PathsModal.tsx` | Cancellable Paths image/text switch with its distinct minimum spinner durations. |
| `FortniteFestivalWeb/src/hooks/chart/useListAnimation.ts` (`useListAnimation`) with `components/common/GraphCard.tsx` | Graph card list swap for already-loaded data: old cards out, height transition, new cards in. |

## Rules

- **R1. Separate first load from reload.** A first-load gate shows one spinner until the initial content is ready; a selector, page or retry reload uses the shared swap rather than a local Boolean or skeleton implementation.
- **R2. Reloads are latest-wins.** Hide or fade the old result, show the spinner while the newest request settles, fade the spinner, then reveal the committed result and its row stagger. Apple’s immediate old-content removal is the approved #71 variant that prevents new labels on stale rows. Stale content never shows under the spinner: content that keeps its slot beside the spinner (a pinned "your score" row whose slot holds the pager in place, #93) is invisible, absent from the accessibility tree and ignores touches until the new result commits, with or without reduced motion (Android `LoadSwap.pinnedContentModifier`, opt-in for pinned rows only: the song and song band leaderboards, #149).
- **R3. Use the shared timings.** Board/page swaps use 300 ms content-out and 500 ms spinner-out; Apple gates retain the web 150 ms spinner-in and 400 ms minimum spinner. Paths uses 300 ms fades with a 400 ms image or 500 ms text minimum.
- **R4. Keep controls usable.** Pickers, pagers and modal selectors live outside the gated result area; a new selection supersedes pending work instead of waiting for it. A pager stays visible and tappable while the next page loads, showing the last loaded page count until the new one commits (web `placeholderData: (previous) => previous`); it hides only for the first load and on failure. The stale-content hiding of R2 never applies to controls (Android band pagers, #149). A page header naming what is loaded (the song leaderboard header, [song-leaderboard-header](song-leaderboard-header.md) R5) also stays outside the gate.
- **R5. Do not replay entry motion while scrolling.** A page-level fade window closes after scroll movement; already-running fades finish, but lazily realized old content appears immediately. Suggestions alone reveals newly generated batches.
- **R6. Honor reduced motion.** Motion-disabled platforms swap without fades or stagger; retain only the minimum spinner hold needed to avoid a blink. HIG Motion: "Add motion purposefully; gratuitous or excessive animation distracts and can cause physical discomfort." MD3: the easing/duration system is used for "transitions (entering, exiting, shared-axis)."
- **R7. Graph card lists follow the web list sequence.** When a graph card's selector changes already-loaded data, its list under the card (Score History's best scores) is not a reload and shows no spinner. The old rows fade out and drift up 8 units (150 ms ease-in, 40 ms stagger; the phase lasts 200 + 40 × (rows − 1) ms). Then the list eases to its new height over 300 ms (`ease`) with no rows visible, and the new rows fade in from 12 units below (300 ms ease-out, 60 ms stagger). A newer change cancels the running one, and the same rows update in place. The list follows the selection at once rather than a graph fade, and the card's View All button sits outside the list, toggling with the selection as in the web `GraphCard`. Reduced motion swaps at once (R6).
- **R8. Graph card chart swaps keep the card's size.** When a graph card's selector switches charts, the graph fades out (150 ms), swaps and fades in (250 ms) while the card keeps its width and height, so nothing below it moves (owner, #61). Rows only some charts need stay reserved on every chart (the pager row while any selectable chart pages). The new chart opens with no bar selected (web `useChartPagination`), and a detail row the switch closes keeps its space, empty, until the reader picks or clears a bar or the data reloads. Agent decision (#261, 2026-10-05): reserve rather than ease to the shorter height (the web detail-card shrink moved the content below) or carry the selection over (no web precedent; a screen reader would announce a bar the reader never picked); owner may override. Reduced motion swaps at once and keeps the same reserved rows (R6).

## Canonical implementation

| Sub-behavior | Apple | Android | Windows |
|---|---|---|---|
| First-load gate | `FestivalUI/Common/FestivalReloadGate.swift` `FestivalReloadGate`; `Common/FadeInOnLoad.swift` `FestivalFadeInScope` | `ui/common/LoadGate.kt` `FestivalLoadGate`; `core/shell/LoadGatePhase.kt` `LoadGatePolicy` | `Festival.App/Controls/FadeIn.cs` `FadeIn`; `Festival.Core/Domain/MotionPolicy.cs` `StaggerArm` |
| Reload swap | `FestivalCore/ReloadTransition.swift` `ReloadTransition`; `Common/FestivalReloadGate.swift` | `ui/common/LoadSwap.kt` `rememberLoadSwap`; `core/shell/LoadSwapPhase.kt` `LoadSwapPolicy` | `Festival.Core/Domain/LoadSwap.cs` `LoadSwap`; `Festival.App/Controls/LoadSwapVisual.cs` `LoadSwapVisual` |
| Paths swap | `FestivalCore/PathSwitchTransition.swift` `PathSwitchTransition` | `presentation/songs/SongPathsViewModel.kt` `PathSwapPhase` | `Festival.Core/ViewModels/SongPathsViewModel.cs` `PathSwapTiming` |
| Graph card chart swap (R8) | `Features/SongDetail/SongScoreHistorySection.swift` `pinnedHeight` | `core/songs/SongHistoryChart.kt` `SongHistorySwap` | `Festival.Core/Domain/ScoreHistorySwap.cs` `ScoreHistorySwapper`; `Festival.Core/ViewModels/SongScoreHistoryViewModel.cs` `ShowPagerSlot`, `ShowDetailSlot` |
| Graph card list (R7) | Not mirrored yet (see debt) | `ui/common/GraphCardList.kt` `GraphCardList`; `core/shell/GraphListPhase.kt` `GraphListPolicy` | Not mirrored yet (see debt) |

## Known debt

| Debt | Breaks | Plan |
|---|---|---|
| Apple and Windows Score History lists are not verified against R7 (Android adopted it in #169). | R7 | Cross-platform check from #169's blast radius. |
| Apple and Android release the held card height after a switch closes a selected bar's detail row, so the card shrinks after the fade (Windows reserves it since #261). | R8 | Cross-platform check from #261's blast radius. |

## Guards (`tools/pattern_guard.py`)

- `load-transition/apple-reload-gate`
- `load-transition/android-load-swap`
- `load-transition/windows-load-swap`
- `load-transition/android-graph-list`

Windows R5 window (#260, agent decision after the PR #274 review; the owner may override): the stagger arm lives in `Festival.Core/Domain/MotionPolicy.cs` `StaggerArm`, shared by `FadeIn` and Song Detail's board cards. A load arm (`Restagger` start 0) closes on the first scroll movement of at least 1 DIP from the offset settled after the arm's first layout, or after its 1 s window, whichever comes first; rows realized after that appear without a fade. An appended Suggestions batch (start > 0) stays open while the reader scrolls to it, so only newly generated cards fade. A batch appended while the load arm is still open is merged into it; the first scroll then drops the load rows and keeps the batch.

Windows R5 behavior check (#260): with `--perf-log`, `FadeIn` writes a `fade-arm` line per stagger arm, a `fade-play` line per played entrance, a `fade-close` line when scrolling closes an arm and a `fade-skip` line for a row realized inside the window that a purely time-based window would have faded but the scroll close kept still (other rows that simply appear write nothing). `tools/windows/suggestions_journey.py --only fade` lengthens the window (Debug/automation `FST_DEBUG_FADE_WINDOW_MS`, since UI Automation can't scroll within 1 s), opens Suggestions, scrolls to the end straight after the list is ready and back to the top. It asserts that the scroll closed the load window inside that window, that only the new batch the scroll kept faded, and that the recycled first-screen cards came back without a fade (`fade-skip`). It then asserts that a generated batch fades only its new cards and that scrolling back replays nothing; `tools/windows/search_journey.py --only fade-delayed-results` asserts that results arriving after the spinner fade once. `tools/windows/tests/test_fade_trace.py` runs in CI and fails if the Suggestions `CardsAdded`, Search `SectionShown`, `FadeIn` scroll-close or Song Detail board-arm wiring is removed, since CI cannot run WinUI journeys.
