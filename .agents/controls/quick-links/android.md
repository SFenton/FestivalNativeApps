# Quick Links — Android notes

> **What:** the Android Quick Links idiom per window size, the reusable Compose API and adoption steps. **Read when:** adding section navigation to any Android page. Behavior: [spec.md](spec.md); references: [ios.md](ios.md), [windows.md](windows.md).

## Design decision (M3 first, Fluent second)

| Size | Presentation | Why |
|---|---|---|
| Compact window (< 600 dp) | `Toc` action ("Quick Links, current section X") in the shell's **floating toolbar** opens a **modal bottom sheet** of `NavigationDrawerItem`s; the current section is the selected item | M3: bottom sheets hold supplementary lists on phones, are thumb-reachable, scroll for long lists (Songs buckets) and support predictive back. Replaces the web FAB and modal |
| Medium and wider windows (tablet, unfolded foldables) | Top-app-bar action opens an anchored **dropdown menu**; the current item is bold with "Current" | M3 menus pick one of a short set of destinations without covering the page. **No side pane** (operator 2026-09-28: the right-side sheet on foldables is dropped) |
| Separating vertical hinge in the page (book posture, half-open) | The page list stays on the start side of the hinge (`QuickLinks.hingeSplit`, `ui/settings/HingeSplit.kt`); the menu anchors to the button in that pane | No row straddles the fold |

No setting toggles Quick Links (spec). Needs ≥ 2 sections.

## API (`core/quicklinks/QuickLinks.kt`, `ui/quicklinks/QuickLinksUi.kt`)

```kotlin
val listState = rememberLazyListState()
val quickLinks = rememberQuickLinks(listState, "Quick Links", sections) { id -> indexOfItem(id) }
FestivalScreen(title, isRoot, actions = { QuickLinksAction(quickLinks, windowWidthDp) }) { … LazyColumn(state = listState) … }
```

- `QuickLinkSection(id, title, icon token | instrument, depth, spokenTitle)`; reuse the web IDs.
- Grid pages: `rememberQuickLinks(gridState: LazyStaggeredGridState, …)` drives a masonry grid the same way (item tops from `layoutInfo`, several items may share a row); the player page uses it.
- Tracking: `QuickLinkTracker` (pure; Apple/Windows port) fed from `snapshotFlow` of the lazy layout info. Items above the first visible one count as "far above"; items below are unknown. `activeId` only changes when the active section changes, so scrolling does not recompose the page.
- Jump: target active immediately, `animateScrollToItem` (instant under reduce motion), then `settle` (ownership; near-end targets stay active while visible).
- Programmatic jumps do not reach the top bar's nested-scroll state, so pass `FestivalScreen(scrolled = listState.canScrollBackward)` or content shows through the transparent bar.
- TalkBack: entry label includes the current section; items expose `selected` + "Current section" state; the sheet has a pane title. Test IDs `fst.quick-links.open`, `.sheet`, `.menu`, `.list`, `.item.<id>`.

## Adoption

| Page | Status |
|---|---|
| Settings | Done: `app-settings`, `diagnostics` (debug), `item-shop`, `show-instruments`, `show-metadata`, `accessibility` (native), `version`, `service-info`, `first-run`, `licenses`, `reset` (no `refresh-profile-name`/`export` rows) |
| Player / Statistics | Done: `global` "Global Statistics", `instrument:<wire>` per visible chart, `top-songs`, `bands` (staggered grid; with a separating hinge the grid splits at the fold and Quick Links stay in the top bar instead of taking a panel) |
| Songs, Song Detail, Band, Compete, Rivals, Rivalry, Rival Detail, Leaderboards | Owning lanes: follow the spec IDs/labels with the API above. Songs keeps its section index for Title/Artist/Year and uses Quick Links for other sorts (as iPhone) |

## Open

- Pages built on non-lazy `Column`s need a lazy list or grid (or another `QuickLinkScroller` that reports item offsets) to use the tracker.
