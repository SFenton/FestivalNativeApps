# Quick Links — Android notes

> **What:** the Android Quick Links idiom per window size, the reusable Compose API and adoption steps. **Read when:** adding section navigation to any Android page. Behavior: [spec.md](spec.md); references: [ios.md](ios.md), [windows.md](windows.md).

## Design decision (M3 first, Fluent second)

| Size | Presentation | Why |
|---|---|---|
| Compact window (< 600 dp) | Top-app-bar action (`Toc` icon, "Quick Links, current section X") opens a **modal bottom sheet** of `NavigationDrawerItem`s; the current section is the selected item | M3: bottom sheets hold supplementary lists on phones, are thumb-reachable, scroll for long lists (Songs buckets) and support predictive back. Replaces the web FAB and modal |
| Medium window, page < 960 dp | Same action opens an anchored **dropdown menu**; the current item is bold with "Current" | M3 menus pick one of a short set of destinations without covering the page |
| Page ≥ 960 dp (tablet, unfolded book/tri-fold with room) | Persistent trailing **pane** (240 dp, `NavigationDrawerItem`s, pane title) beside the content; selecting scrolls without closing | Web ≥1440 px rail; M3 supporting pane. Decided by **page** width, so the navigation rail/drawer and hinges are accounted for |

No setting toggles Quick Links (spec). Needs ≥ 2 sections.

## API (`core/quicklinks/QuickLinks.kt`, `ui/quicklinks/QuickLinksUi.kt`)

```kotlin
val listState = rememberLazyListState()
val quickLinks = rememberQuickLinks(listState, "Quick Links", sections) { id -> indexOfItem(id) }
FestivalScreen(title, isRoot, actions = { if (!pane) QuickLinksAction(quickLinks, windowWidthDp) }) { … LazyColumn(state = listState) … }
if (pane) QuickLinksPane(quickLinks)   // beside the list, when QuickLinks.usesPane(pageWidthDp)
```

- `QuickLinkSection(id, title, icon token | instrument, depth, spokenTitle)`; reuse the web IDs.
- Tracking: `QuickLinkTracker` (pure; Apple/Windows port) fed from `snapshotFlow { listState.layoutInfo }`. Items above the first visible one count as "far above"; items below are unknown. `activeId` only changes when the active section changes, so scrolling does not recompose the page.
- Jump: target active immediately, `animateScrollToItem` (instant under reduce motion), then `settle` (ownership; near-end targets stay active while visible).
- TalkBack: entry label includes the current section; items expose `selected` + "Current section" state; the pane has a pane title. Test IDs `fst.quick-links.open`, `.sheet`, `.menu`, `.pane`, `.list`, `.item.<id>`.

## Adoption

| Page | Status |
|---|---|
| Settings | Done: `app-settings`, `diagnostics` (debug), `item-shop`, `show-instruments`, `show-metadata`, `accessibility` (native), `version`, `service-info`, `first-run`, `licenses`, `reset` (no `refresh-profile-name`/`export` rows) |
| Songs, Song Detail, Player/Statistics, Band, Compete, Rivals, Rivalry, Rival Detail, Leaderboards | Owning lanes: follow the spec IDs/labels with the API above. Songs keeps its section index for Title/Artist/Year and uses Quick Links for other sorts (as iPhone) |

## Open

- Pages built on non-lazy `Column`s need a lazy list (or an adapter that reports item offsets) to use the tracker.
