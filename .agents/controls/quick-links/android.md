# Quick Links — Android notes

> **What:** the Android Quick Links idiom per window size, the reusable Compose API and adoption steps. **Read when:** adding section navigation to any Android page. Behavior: [spec.md](spec.md); references: [ios.md](ios.md), [windows.md](windows.md).

## Design decision (M3 first, Fluent second)

| Size | Presentation | Why |
|---|---|---|
| Compact window (< 600 dp) | `Toc` action ("Quick Links, current section X") in the shell's **floating toolbar** opens a **modal bottom sheet** of `NavigationDrawerItem`s; the current section is the selected item. On Songs it shares the pinned toolbar with search, Sort and Filter (issue #84); on other pages the toolbar follows M3 "exit always" hide-on-scroll and returns on scroll up | M3: bottom sheets hold supplementary lists on phones, are thumb-reachable, scroll for long lists (Songs buckets) and support predictive back. Replaces the web FAB and modal. The bottom floating toolbar is already the M3 Expressive equivalent of the iOS #42 accessory, so no other page changed for #84 |
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
- Jump: target active immediately, `scrollToItem(index, scrollOffset)` (an instant "teleport", operator batch 7.15), then `settle` (ownership; near-end targets stay active while visible).
- Landing (#51, iOS #12): a jump lands the section's item top **32 dp below the visible top** of the page (`QuickLinks.LANDING_OFFSET_DP`, the web's default offset), and the activation line is the same 32 dp so the landed section is the highlighted one. Scrollers report item tops in viewport coordinates (`offset - viewportStartOffset`) and land with `scrollOffset = beforeContentPadding - landing` (`QuickLinks.lazyLandingScrollOffset`), so pages with their own list top padding (Leaderboards, Compete, Player) land the same; one `scrollToItem` positions lazily built items too. `rememberScrollQuickLinks` (Band) clamps `QuickLinks.scrollLandingTarget`. Pages whose heading has its own top padding inside the item (Compete's 8 dp) show the title that much lower. Songs passes `pinnedHeaders = true`: sticky bucket headers land flush with a 16 dp activation line (web virtualizer case).
- Hold landing (issue #106): landing 32 dp low leaves the section above as the lazy layout's first visible item, i.e. its scroll anchor. On the player page that card composes for the first time on the jump, starts its Rank History read and grows by its 300 dp spinner block or chart, pushing the target half a screen down (Top Songs and Pro Drums on FST_Phone/FST_Tablet). After a jump the controller keeps watching the layout (`keepLanded`): while the user is not scrolling, for at most `QuickLinks.MAX_LANDING_CORRECTIONS` (8) re-lands within `LANDING_HOLD_MILLIS` (10 s), it re-lands whenever `QuickLinks.needsRelanding` sees the target drift by more than `COMPLETE_THRESHOLD_DP` (8 dp) from the landing line and the list can still scroll that way (a near-end target cannot reach the line and is left alone). Any user scroll, a new jump or leaving the page ends the hold. Off for `pinnedHeaders` (Songs' sticky headers do not shift). Tests: `QuickLinksTest.relandingCorrectsOnlyDriftTheListCanScrollAway`, `QuickLinksControllerUiTest.aJumpStaysLandedWhileTheSectionAboveItGrows`.
- One controller per list: `rememberQuickLinks` keys only on the scroller, `pinnedHeaders` and density; `title` and `sections` are snapshot state set each composition. The shell's floating toolbar re-runs a page's `actions` only on state reads, so a controller recreated by a title change (Songs' "<Sort> Quick Links") left a stale entry with no sections and hid `fst.quick-links.open` (Linux CI flake in `SongsParityUiTest`). Covered by `QuickLinksControllerUiTest`.
- Programmatic jumps do not reach the top bar's nested-scroll state, so pass `FestivalScreen(scrolled = listState.canScrollBackward)` or content shows through the transparent bar.
- TalkBack: entry label includes the current section; items expose `selected` + "Current section" state; the sheet has a pane title. Test IDs `fst.quick-links.open`, `.sheet`, `.menu`, `.list`, `.item.<id>`.
- Order (issue #46 cross-check of iOS #6): both the sheet (`LazyColumn`) and the `DropdownMenu` list `controller.sections` in declared order, which is the page order; Compose does not reverse a bottom-anchored menu. Checked on FST_Phone with fixtures: Settings and the player profile, from both the portrait bottom-toolbar sheet and the landscape top-bar menu. Order, jump and `selected`/`checked` were correct, so no change was needed.

## Adoption

| Page | Status |
|---|---|
| Settings | Done: `app-settings`, `diagnostics` (debug), `item-shop`, `show-instruments`, `show-metadata`, `accessibility` (native), `version`, `service-info`, `first-run`, `licenses`, `reset` (no `refresh-profile-name`/`export` rows) |
| Player / Statistics | Done: `global` "Global Statistics", `instrument:<wire>` per visible chart, `top-songs`, `bands` (staggered grid; with a separating hinge the grid splits at the fold and Quick Links stay in the top bar instead of taking a panel) |
| Songs | Done: sort buckets (`<webId>:<token>`, e.g. `duration:lt2`, `shop:in-shop`, `hasfc:fc`) for every sort except Title/Artist/Year, which keep the section index (as iPhone) |
| Song Detail, Band, Compete, Rivals, Rivalry, Rival Detail, Leaderboards | Owning lanes: follow the spec IDs/labels with the API above |

## Open

- Pages built on non-lazy `Column`s need a lazy list or grid (or another `QuickLinkScroller` that reports item offsets) to use the tracker.
