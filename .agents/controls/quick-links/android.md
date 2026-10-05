# Quick Links — Android notes

> **What:** the Android Quick Links idiom per window size, the reusable Compose API and adoption steps. **Read when:** adding section navigation to any Android page. Behavior: [spec.md](spec.md); references: [ios.md](ios.md), [windows.md](windows.md).

## Design decision (M3 first, Fluent second)

| Size | Presentation | Why |
|---|---|---|
| Compact window (< 600 dp) | `Toc` action ("Quick Links, current section X") in the shell's **floating toolbar** opens a **modal bottom sheet** of `NavigationDrawerItem`s; the current section is the selected item. On Songs it shares the pinned toolbar with search, Sort and Filter (issue #84); on other pages the toolbar follows M3 "exit always" hide-on-scroll and returns on scroll up | M3: bottom sheets hold supplementary lists on phones, are thumb-reachable, scroll for long lists (Songs buckets) and support predictive back. Replaces the web FAB and modal. The bottom floating toolbar is already the M3 Expressive equivalent of the iOS #42 accessory, so no other page changed for #84 |
| Medium and wider windows (tablet, unfolded foldables) | Top-app-bar action opens an anchored **dropdown menu**; the current item is bold with "Current" on its own line under the title (`QuickLinkMenuLabel`), never as a trailing label | M3 menus pick one of a short set of destinations without covering the page. **No side pane** (operator 2026-09-28: the right-side sheet on foldables is dropped) |
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
- Landing hold (issues #106, #111): landing 32 dp low leaves the section above as the lazy layout's first visible item, i.e. its scroll anchor. Sections that start reading when first composed (Statistics and Player Profile Rank History, bands) grow after `scrollToItem`; on the player page the Rank History card's 300 dp spinner block or chart pushed Top Songs and Pro Drums half a screen down on FST_Phone/FST_Tablet. After a jump the controller watches the layout (`keepLanded`) for `QuickLinks.LANDING_HOLD_MS` (10 s, long enough for a live-service Rank History read) and at most `QuickLinks.MAX_LANDING_CORRECTIONS` (8) re-landings: it re-lands whenever `QuickLinks.needsReland` sees the target more than `COMPLETE_THRESHOLD_DP` (8 dp) off the landing line, or pushed off the laid-out items, and the list can still scroll that way (a near-end target cannot reach the line and is left alone). Any user scroll (`isScrollInProgress`), a new jump or leaving the page ends the hold. An instant programmatic scroll (a TalkBack/semantics scroll-to-index, Suggestions' scroll-to-top on a new mix) is never "in progress" when the hold sees it, so the hold also ends when the scroll position (`QuickLinkScroller.position`: first visible index and offset, or `ScrollState.value`) moves between its own landings; content growing above the anchor leaves that position unchanged (issue #137: CI caught the hold dragging a scroll-to-top back to the jumped section). Off for `pinnedHeaders` (Songs' sticky headers do not shift). Tests: `quicklinks/QuickLinksTest` (`heldJumpRelandsOnlyWhenScrollingCanMoveTheTargetBack`, `relandingCorrectsOnlyDriftTheListCanScrollAway`) and `QuickLinksControllerUiTest` (landing hold region, including `aProgrammaticScrollAfterTheJumpEndsTheLandingHold`).
- Staggered lanes: `LazyStaggeredGridState` resets its lane cache only when the lane count changes. A grid whose spans change at a constant lane count (the player grid splitting at a fold) must swap in a fresh state (`rememberProfileGridState`), or a later jump to the first section leaves a lane gap (#111 on FST_Book_Fold).
- One controller per list: `rememberQuickLinks` keys only on the scroller, `pinnedHeaders` and density; `title` and `sections` are snapshot state set each composition. The shell's floating toolbar re-runs a page's `actions` only on state reads, so a controller recreated by a title change (Songs' "<Sort> Quick Links") left a stale entry with no sections and hid `fst.quick-links.open` (Linux CI flake in `SongsParityUiTest`). Covered by `QuickLinksControllerUiTest`.
- Programmatic jumps do not reach the top bar's nested-scroll state, so pass `FestivalScreen(scrolled = listState.canScrollBackward)` or content shows through the transparent bar.
- TalkBack: entry label includes the current section; items expose `selected` + "Current section" state; the sheet has a pane title. Test IDs `fst.quick-links.open`, `.sheet`, `.menu`, `.list`, `.item.<id>`.
- Order (issue #46 cross-check of iOS #6): both the sheet (`LazyColumn`) and the `DropdownMenu` list `controller.sections` in declared order, which is the page order; Compose does not reverse a bottom-anchored menu. Checked on FST_Phone with fixtures: Settings and the player profile, from both the portrait bottom-toolbar sheet and the landscape top-bar menu. Order, jump and `selected`/`checked` were correct, so no change was needed. The order is guarded by `QuickLinksPageOrderUiTest` (Settings, profile) and `QuickLinksPageSweepUiTest` (every other page, #158), and was re-validated on every AVD in #154 and #158.

## Adoption

| Page | Status |
|---|---|
| Settings | Done: `app-settings`, `diagnostics` (debug), `item-shop`, `show-instruments`, `show-metadata`, `accessibility` (native), `version`, `service-info`, `first-run`, `licenses`, `privacy-policy`, `reset` (no `refresh-profile-name`/`export` rows) |
| Player / Statistics | Done: `global` "Global Statistics", `instrument:<wire>` per visible chart, `top-songs`, `bands` (staggered grid; with a separating hinge the grid splits at the fold and Quick Links stay in the top bar instead of taking a panel) |
| Songs | Done: sort buckets (`<webId>:<token>`, e.g. `duration:lt2`, `shop:in-shop`, `hasfc:fc`) for every sort except Title/Artist/Year, which keep the section index (as iPhone) |
| Song Detail (pushed page only) | Done: `intensity`, `score-history` (only when the page shows the card: one `showHistory` flag feeds `SongDetailLayout.items` and `.quickLinks`), `instrument-<wire>` per visible chart, `band-<wire>` per band size |
| Compete | Done: `leaderboards`, `rivals` (staggered grid headers; none while a full-page issue shows) |
| Leaderboards | Done: `rank-history` (selected player), `instrument:<wire>`, `band:<wire>` |
| Band Detail (one pane) | Done: `members`, `summary`, `statistics`, `rank-history`, `songs` (`rememberScrollQuickLinks`; no Quick Links in two panes) |
| Rivals, Rival Detail, Rivalry | Done: the loaded hub cards (`common`, combo, `<wire>` / `leaderboard.<wire>`), `rival-category:<key>`, `<songId>:<wire>:<index>` per song |

## Validation (issue #137)

Checked on the live public service (Settings page) on every FST AVD, light/dark system theme, font scale 1.0/2.0, portrait/landscape. States `hidden-single-section`, `menu-closed`, `menu-open`, `active-section`, `jumped`.

| Configuration | Finding |
|---|---|
| FST_Phone portrait | Toolbar sheet; opens partially expanded when > 8 sections (drag up for the rest, M3 default). The selected pill was inset 24 dp start / 12 dp end; **fixed** to 24 dp both sides (`SectionList` `end = 12.dp`) |
| FST_Phone landscape, FST_Tablet, FST_Resizable medium/expanded, unfolded folds | Anchored menu. At font 2.0 the trailing "Current" label shared M3's 280 dp item cap and broke "Show Instrument Metadata" mid-word; **fixed** by `QuickLinkMenuLabel` (title, then "Current" beneath). Long titles now wrap only between words and the menu scrolls |
| FST_Book_Fold / FST_Passport_Fold folded, FST_TriFold folded | Compact sheet, as the phone |
| FST_Book_Fold half-open (vertical hinge) | Page on the start pane, menu anchored to the end-side button; no row straddles the hinge |
| FST_Resizable shrunk to phone | Quick Links correct; the shell's modal navigation drawer can stay open after the resize (shell, not this control) |
| Light system theme | App stays on its dark scheme; nothing breaks |

- M3 alignment: sheet = `ModalBottomSheet` + `NavigationDrawerItem` (selected = `secondaryContainer`-equivalent pill), menu = `DropdownMenu`/`DropdownMenuItem` (280 dp cap, scrolls), 48 dp targets. Deliberate deviations: 30 dp `Toc` glyph in the 48 dp button (web parity); `NavigationDrawerItem` exposes Role.Tab (M3 default); dark scheme only.
- Tests: `QuickLinksUiTest` (Robolectric, every state, inset, menu label) on `testing/QuickLinksHarness.kt`; `androidTest/…/quicklinks/QuickLinksDeviceTest` (ATF checks, TalkBack order, animator scale 0, 2× sheet targets, 2× menu titles break only at spaces — glyph wrapping needs a device).

## Validation (issue #154)

Re-check of the #46 order on the live public service (Settings with 12 sections in debug: `app-settings` … `privacy-policy`, `reset`; player profile `SFentonX`: Global, 9 instruments, Top Songs, Bands). Each case opened Quick Links, jumped (Settings → Service Info, profile → Top Songs; on phone landscape → Show Instrument Metadata / Drums), then reopened it. **The order matches the page everywhere, so no app change was needed.**

| Configuration | Entry point | Finding |
|---|---|---|
| FST_Phone portrait, dark 1.0 / light 2.0 | Toolbar sheet | Page order. After a drag up, the jumped item is selected on reopen. At 2.0 titles wrap and nothing clips |
| FST_Phone landscape, dark 1.0 / light 2.0 | Top-bar menu (scrolls) | Page order. Jump lands, and "Current" shows under the item on reopen. Rows are 48 dp |
| FST_Tablet landscape dark 1.0, portrait light 2.0 | Top-bar menu | Page order, jump and reopen state correct. Rows are 48 dp, and 2-line titles wrap only between words |
| FST_Resizable phone / tablet portrait / desktop | Sheet / menu / menu | Compact, medium and expanded all correct |
| FST_Book_Fold folded / unfolded / half-open | Sheet / menu / menu | Correct. Half-open anchors the menu in the end pane; no row crosses the hinge |
| FST_Passport_Fold folded / unfolded / half-open | Sheet / menu / menu | Correct |
| FST_TriFold folded / partial / unfolded | Sheet / menu / menu | Correct. Unfolded places the menu right of the second hinge |

- Tooling note: right after a cold boot, `uiautomator dump` sometimes failed and aborted `device.py drive`. A warm-up dump before launching fixes it, and FST_Tablet portrait at 2.0 passed on rerun. This is not an app fault.
- Tests: `quicklinks/QuickLinksPageOrderUiTest` (Robolectric) reads the real Settings and profile pages. For both the sheet (411 dp) and the menu (1280 dp and phone landscape), it asserts that every section is listed once in the page's `IndexForKey` order, that the jump updates the entry label, and that exactly the jumped item is `selected` on reopen. Reversing `controller.sections` in the sheet or the menu fails all 6 tests. `QuickLinksDeviceTest` passes on FST_Phone and FST_Tablet.
- M3 (material-3 skill): bottom sheet at compact width, menu for larger windows, 48 dp targets, menu small shape at level 2, modal sheet extra-large at level 1. Deliberate deviations are unchanged from #137.

## Validation (issue #158)

Check of #50 on every page with Quick Links, against the live public service (`SFentonX`, "Everlong"; anonymous for the no-player case). Each case opened Quick Links on Song Detail and Compete and read the `fst.quick-links.item.*` ids from the a11y tree, sorted by position. Phone portrait also covered Leaderboards and the Rivals hub. **Every menu lists sections in on-page top-to-bottom order, and Score History is listed exactly when the page shows it. #50's inversion does not reproduce, so there is no app change.**

| Configuration | Entry point | Song Detail | Compete |
|---|---|---|---|
| FST_Phone portrait, dark 1.0 / light 2.0 | Toolbar sheet | `intensity`, `score-history`, instruments… (anonymous: no `score-history`) | `leaderboards`, `rivals` |
| FST_Phone landscape, dark 1.0 / light 2.0 | Top-bar menu | `intensity`, `score-history`, instruments… | `leaderboards`, `rivals` |
| FST_Tablet landscape dark 1.0, portrait light 2.0 | Top-bar menu | `intensity`, `score-history`, 9 instruments, `band-Band_Duets`/`Trios`/`Quad` (matches the page) | `leaderboards` (Current), `rivals` |
| FST_Resizable compact / medium / expanded | Sheet / menu / menu | Compact: `intensity`, `score-history`, instruments…; medium/expanded: full list as the tablet | Expanded: `leaderboards`, `rivals` |
| FST_Book_Fold folded / half-open / unfolded | Sheet / menu / menu | Page order. Half-open shows Intensity and Score History side by side, listed start pane first, and the menu stays in the end pane | Unfolded: `leaderboards`, `rivals` |
| FST_Passport_Fold folded / unfolded | Sheet / menu | Page order (`intensity`, `score-history`, instruments, bands) | Folded and unfolded: `leaderboards`, `rivals` |
| FST_TriFold folded / partial / unfolded | Sheet / menu / menu | Page order; the menu stays within one panel | Unfolded: `leaderboards`, `rivals` |

Phone portrait also checked Leaderboards (`rank-history`, then instruments) and the Rivals hub (Lead … Pro Drums, as on the page).

- Tooling note: when other lanes switch AVDs, every job cold-boots, and the first `uiautomator dump` after launch often fails. Two or three `shell:uiautomator dump` warm-up steps before the first `waitfor` fixed Passport folded and TriFold partial/unfolded. Other lanes install their own builds of the same package, so reinstall the APK in the same lock hold as each check.
- Tests: `quicklinks/QuickLinksPageSweepUiTest` (Robolectric, 15 cases) scrolls each real page through the fixture service, records its section anchors top to bottom, and asserts that the open menu lists the same ids in the same order. It covers the compact sheet (411 dp) and the menu (1280 dp). Pages: Song Detail with history (`score-history` second), without a player, and with a player but no history for the song (no `score-history`); Compete; Leaderboards; Band Detail; the Rivals hub (song and leaderboard tabs); Rival Detail; Rivalry. Together with `QuickLinksPageOrderUiTest` (Settings, profile) this covers every Quick Links page. Inverting `showHistory` in `SongDetailLayout.quickLinks` fails all 4 Song Detail cases, and reversing `RivalQuickLinks.compete()` fails both Compete cases. Wide Compete opens through `CompeteRoute`, because the permanent drawer has no Compete destination. Close the menu by tapping an item, not Back: Back also pops a pushed page. `QuickLinksDeviceTest` (ATF checks, TalkBack order, animator scale 0, 2.0 targets) passes on FST_Phone and FST_Tablet.
- M3 (material-3 skill: `layout-and-responsive`, `component-catalog`, `typography-and-shape`): a modal bottom sheet at compact width and an anchored menu for medium and expanded windows, 48 dp rows, menu items with leading icons. There are no new deviations; the #137 list stands.

## Open

- Pages built on non-lazy `Column`s need a lazy list or grid (or another `QuickLinkScroller` that reports item offsets) to use the tracker.
