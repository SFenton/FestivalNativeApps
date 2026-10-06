# Load transition

> **What:** first-load gates, reload swaps, graph card list swaps and row entrances for pages, boards and data-backed modal content. **Read when:** a load, refresh, selector, page or modal switch changes visible data.

Status: **current**, 2026-10-05. Provenance: #30, #60, #70, #71, #169, #304.

## Intent

Loading must communicate a deliberate state change rather than a hard cut: first loads gate incomplete content, reloads replace stale content through a spinner, and row entrances run once per reveal rather than while the reader scrolls.

## Web source (behavior reference)

| Web | Behavior |
|---|---|
| `FortniteFestivalWeb/src/hooks/data/useLoadPhase.ts` (`useLoadPhase`) | Load/reload phase machine and spinner timing. |
| `FortniteFestivalWeb/src/components/page/LoadGate.tsx` (`LoadGate`) | First-load spinner gate and content reveal. |
| `FortniteFestivalWeb/src/components/leaderboard/PaginatedLeaderboard.tsx` (`PaginatedLeaderboard`) | Board reload spinner, row stagger and pinned footer. |
| `FortniteFestivalWeb/src/pages/songinfo/components/path/PathsModal.tsx` | Cancellable Paths image/text switch with its distinct minimum spinner durations. |
| `FortniteFestivalWeb/src/contexts/PublicationBoundary.tsx` (`PublicationBoundary`) | A new publication (pushed over `/api/ws`) fades the current page out, shows the spinner and fades the rebuilt page in without leaving the route. |
| `FortniteFestivalWeb/src/hooks/chart/useListAnimation.ts` (`useListAnimation`) with `components/common/GraphCard.tsx` | Graph card list swap for already-loaded data: old cards out, height transition, new cards in. |

## Rules

- **R1. Separate first load from reload.** A first-load gate shows one spinner until the initial content is ready; a selector, page or retry reload uses the shared swap rather than a local Boolean or skeleton implementation.
- **R2. Reloads are latest-wins.** Hide or fade the old result, show the spinner while the newest request settles, fade the spinner, then reveal the committed result and its row stagger. Apple’s immediate old-content removal is the approved #71 variant that prevents new labels on stale rows.
- **R3. Use the shared timings.** Board/page swaps use 300 ms content-out and 500 ms spinner-out; Apple gates retain the web 150 ms spinner-in and 400 ms minimum spinner. Paths uses 300 ms fades with a 400 ms image or 500 ms text minimum. The publication refresh (R8) runs all four phases: content out 300 ms → spinner in 150 ms, held ≥400 ms and until the page has prepared for the new generation → spinner out 500 ms → rebuilt content in.
- **R4. Keep controls usable.** Pickers, pagers and modal selectors live outside the gated result area; a new selection supersedes pending work instead of waiting for it.
- **R5. Do not replay entry motion while scrolling.** A page-level fade window closes after scroll movement; already-running fades finish, but lazily realized old content appears immediately. Suggestions alone reveals newly generated batches.
- **R6. Honor reduced motion.** Motion-disabled platforms swap without fades or stagger; retain only the minimum spinner hold needed to avoid a blink. HIG Motion: "Add motion purposefully; gratuitous or excessive animation distracts and can cause physical discomfort." MD3: the easing/duration system is used for "transitions (entering, exiting, shared-axis)."
- **R7. Graph card lists follow the web list sequence.** When a graph card's selector changes already-loaded data, its list under the card (Score History's best scores) is not a reload and shows no spinner. The old rows fade out and drift up 8 units (150 ms ease-in, 40 ms stagger; the phase lasts 200 + 40 × (rows − 1) ms). Then the list eases to its new height over 300 ms (`ease`) with no rows visible, and the new rows fade in from 12 units below (300 ms ease-out, 60 ms stagger). A newer change cancels the running one, and the same rows update in place. The list follows the selection at once rather than a graph fade, and the card's View All button sits outside the list, toggling with the selection as in the web `GraphCard`. Reduced motion swaps at once (R6).
- **R8. A publication refresh keeps the reader on the page.** A new publication refreshes every open page and route in place through the shared publication boundary: no pop to a root, no explanatory card. While old content is hidden behind the spinner, VoiceOver keeps a stable page anchor (an invisible heading named with the page title, value "Loading new scores"); focus moves there only if it was established to be inside the page (on screen, uncovered, in the page's hierarchy and frame), and returns there after the rebuild unless the reader moved elsewhere during the spinner. Focus elsewhere (tab bar, navigation bar, a sheet, another column) is never moved; one on-screen page announces "Loading new scores" per publication instead. Where the platform cannot report the VoiceOver cursor (macOS), always announce and never move focus. Pages inside the boundary therefore set their title with `festivalNavigationTitle`. A root whose search field and page tools must stay usable (Apple Songs, #304 review) wraps only its result area, names the anchor with the boundary's `title`, reads the new generation in `prepare` (never from a revision-keyed task, so the fading list never draws new rows) and reveals through `onReveal`; its own reload gate is rebuilt already loaded, so the refresh shows one spinner, not two. When those results are a UIKit-backed `List`, it also passes `retainsHiddenContent: false`: `accessibilityHidden` does not reach `List` rows, so the faded-out list unmounts under the spinner rather than leaving old rows readable. HIG Focus and selection: "Avoid changing focus without people's interaction", with the exception "if the focused item disappears during discrete, directional input (keyboard, remote, game controller), moving focus to an item one step away keeps it findable" (VoiceOver swipes are discrete, directional input; the anchor is the nearest surviving item); HIG VoiceOver: "Announce visible content and layout changes."

## Canonical implementation

| Sub-behavior | Apple | Android | Windows |
|---|---|---|---|
| First-load gate | `FestivalUI/Common/FestivalReloadGate.swift` `FestivalReloadGate`; `Common/FadeInOnLoad.swift` `FestivalFadeInScope` | `ui/common/LoadGate.kt` `FestivalLoadGate`; `core/shell/LoadGatePhase.kt` `LoadGatePolicy` | `Festival.App/Controls/FadeIn.cs` `FadeIn` |
| Reload swap | `FestivalCore/ReloadTransition.swift` `ReloadTransition`; `Common/FestivalReloadGate.swift` | `ui/common/LoadSwap.kt` `rememberLoadSwap`; `core/shell/LoadSwapPhase.kt` `LoadSwapPolicy` | `Festival.Core/Domain/LoadSwap.cs` `LoadSwap`; `Festival.App/Controls/LoadSwapVisual.cs` `LoadSwapVisual` |
| Paths swap | `FestivalCore/PathSwitchTransition.swift` `PathSwitchTransition` | `presentation/songs/SongPathsViewModel.kt` `PathSwapPhase` | `Festival.Core/ViewModels/SongPathsViewModel.cs` `PathSwapTiming` |
| Graph card list (R7) | Not mirrored yet (see debt) | `ui/common/GraphCardList.kt` `GraphCardList`; `core/shell/GraphListPhase.kt` `GraphListPolicy` | Not mirrored yet (see debt) |
| Publication refresh (R3, R8) | `Common/PublicationRefreshBoundary.swift` `PublicationRefreshBoundary`; `FestivalCore/PublicationRefreshTransition.swift` `PublicationRefreshTransition`; `FestivalCore/PublicationRefreshFocus.swift` `PublicationRefreshFocus`; `Common/PublicationFocusProbe.swift` `PublicationFocusProbe`; `Common/PageTitle.swift` `festivalNavigationTitle` | — (not in #304 scope) | — (not in #304 scope) |

## Known debt

| Debt | Breaks | Plan |
|---|---|---|
| Apple and Windows Score History lists are not verified against R7 (Android adopted it in #169). | R7 | Cross-platform check from #169's blast radius. |
| Apple routes whose whole page is a `List` inside the boundary (Solo leaderboard, Player Bands) keep their toolbar inside it, so they cannot use `retainsHiddenContent: false`; VoiceOver hiding of their old rows under the spinner is unverified (#304 review). | R8 | Verify with an atomic-snapshot journey like `testLiveRolloverRefreshesSongsListInPlace`; if rows leak, hide them per row rather than unmounting the toolbar. |

## Guards (`tools/pattern_guard.py`)

- `load-transition/apple-reload-gate`
- `load-transition/apple-page-title`
- `load-transition/android-load-swap`
- `load-transition/windows-load-swap`
- `load-transition/android-graph-list`
