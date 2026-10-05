# Load transition

> **What:** first-load gates, reload swaps and row entrances for pages, boards and data-backed modal content. **Read when:** a load, refresh, selector, page or modal switch changes visible data.

Status: **current**, 2026-10-05. Provenance: #30, #60, #70, #71, #149.

## Intent

Loading must communicate a deliberate state change rather than a hard cut: first loads gate incomplete content, reloads replace stale content through a spinner, and row entrances run once per reveal rather than while the reader scrolls.

## Web source (behavior reference)

| Web | Behavior |
|---|---|
| `FortniteFestivalWeb/src/hooks/data/useLoadPhase.ts` (`useLoadPhase`) | Load/reload phase machine and spinner timing. |
| `FortniteFestivalWeb/src/components/page/LoadGate.tsx` (`LoadGate`) | First-load spinner gate and content reveal. |
| `FortniteFestivalWeb/src/components/leaderboard/PaginatedLeaderboard.tsx` (`PaginatedLeaderboard`) | Board reload spinner, row stagger and pinned footer. |
| `FortniteFestivalWeb/src/pages/songinfo/components/path/PathsModal.tsx` | Cancellable Paths image/text switch with its distinct minimum spinner durations. |

## Rules

- **R1. Separate first load from reload.** A first-load gate shows one spinner until the initial content is ready; a selector, page or retry reload uses the shared swap rather than a local Boolean or skeleton implementation.
- **R2. Reloads are latest-wins.** Hide or fade the old result, show the spinner while the newest request settles, fade the spinner, then reveal the committed result and its row stagger. Apple’s immediate old-content removal is the approved #71 variant that prevents new labels on stale rows. Stale content never shows under the spinner: content that keeps its slot beside the spinner (a pinned "your score" row whose slot holds the pager in place, #93) is invisible, absent from the accessibility tree and ignores touches until the new result commits, with or without reduced motion (Android `LoadSwap.pinnedContentModifier`, opt-in for pinned rows only, #149).
- **R3. Use the shared timings.** Board/page swaps use 300 ms content-out and 500 ms spinner-out; Apple gates retain the web 150 ms spinner-in and 400 ms minimum spinner. Paths uses 300 ms fades with a 400 ms image or 500 ms text minimum.
- **R4. Keep controls usable.** Pickers, pagers and modal selectors live outside the gated result area; a new selection supersedes pending work instead of waiting for it. A pager stays visible and tappable while the next page loads, showing the last loaded page count until the new one commits (web `placeholderData: (previous) => previous`); it hides only for the first load and on failure. The stale-content hiding of R2 never applies to controls (Android band pagers, #149).
- **R5. Do not replay entry motion while scrolling.** A page-level fade window closes after scroll movement; already-running fades finish, but lazily realized old content appears immediately. Suggestions alone reveals newly generated batches.
- **R6. Honor reduced motion.** Motion-disabled platforms swap without fades or stagger; retain only the minimum spinner hold needed to avoid a blink. HIG Motion: "Add motion purposefully; gratuitous or excessive animation distracts and can cause physical discomfort." MD3: the easing/duration system is used for "transitions (entering, exiting, shared-axis)."

## Canonical implementation

| Sub-behavior | Apple | Android | Windows |
|---|---|---|---|
| First-load gate | `FestivalUI/Common/FestivalReloadGate.swift` `FestivalReloadGate`; `Common/FadeInOnLoad.swift` `FestivalFadeInScope` | `ui/common/LoadGate.kt` `FestivalLoadGate`; `core/shell/LoadGatePhase.kt` `LoadGatePolicy` | `Festival.App/Controls/FadeIn.cs` `FadeIn` |
| Reload swap | `FestivalCore/ReloadTransition.swift` `ReloadTransition`; `Common/FestivalReloadGate.swift` | `ui/common/LoadSwap.kt` `rememberLoadSwap`; `core/shell/LoadSwapPhase.kt` `LoadSwapPolicy` | `Festival.Core/Domain/LoadSwap.cs` `LoadSwap`; `Festival.App/Controls/LoadSwapVisual.cs` `LoadSwapVisual` |
| Paths swap | `FestivalCore/PathSwitchTransition.swift` `PathSwitchTransition` | `presentation/songs/SongPathsViewModel.kt` `PathSwapPhase` | `Festival.Core/ViewModels/SongPathsViewModel.cs` `PathSwapTiming` |

## Known debt

| Debt | Breaks | Plan |
|---|---|---|
| None verified. | — | — |

## Guards (`tools/pattern_guard.py`)

- `load-transition/apple-reload-gate`
- `load-transition/android-load-swap`
- `load-transition/windows-load-swap`
