# Global search — Android notes

> **What:** the Compose/Material 3 design for the app-wide search entry point on every Android form factor and posture (phone, book and passport foldables, tri-fold, tablet, resizable windows), plus keyboard, predictive back, TalkBack and the implementation plan. **Read when:** implementing or changing global search in `android/` (lane `and-search`). Behavior and test IDs: [spec.md](spec.md). Adaptive shell: [design/android.md](../../design/android.md).

## Decision

**Material 3 search: a search action that expands into a full-screen search view on compact widths, and a persistent docked search bar with a docked results panel from medium width up.** The layout is chosen by window size class, never by device name or pixels.

| Width class (window) | Entry point | Expanded surface |
|---|---|---|
| Compact (< 600 dp): phone, book/passport cover screens, tri-fold folded | Magnifier `IconButton` in every page's `TopAppBar` actions, before the bell and avatar (`fst.global-search.open`) | `ExpandedFullScreenSearchBar`: covers the window, field at the top, scope chips under it, results below |
| Medium (600–839 dp): tri-fold partial, portrait tablet, small resizable windows | Same action icon (the top bar is still title + actions) | `ExpandedDockedSearchBar` anchored under the top bar at the end edge, ≤ 720 dp wide, ≤ 2/3 window height |
| Expanded and wider (≥ 840 dp): book fold unfolded, passport unfolded, tri-fold unfolded, landscape tablet, desktop windows | **Persistent collapsed `SearchBar`** in the app-level top bar of the content pane, next to the bell/avatar ("Search songs or players") on every page | `ExpandedDockedSearchBar` under the bar |

Why: Material 3 reserves the full-screen search view for compact windows and the docked view for larger ones, and places search either as a top-app-bar action (pages with their own title) or as a search app bar (search-first screens) [M3 search](https://m3.material.io/components/search/guidelines), [Compose search bar](https://developer.android.com/develop/ui/compose/components/search-bar). Material3 1.4.0 (stable) has `SearchBar`, `ExpandedFullScreenSearchBar`, `ExpandedDockedSearchBar` and `rememberSearchBarState()`; `AppBarWithSearch` is still `@ExperimentalMaterial3Api` in the 1.5.0 alphas, so build the expanded-width bar from `SearchBar` inside our own top bar and adopt it once stable. Our pages have titles and actions, so compact/medium use the action; at expanded widths there is room for a persistent bar, which also mirrors the web's always-visible header button and the Windows title-bar box.

Rejected:

| Alternative | Why not |
|---|---|
| Persistent `SearchBar` on every page at every width | On compact screens it displaces page titles and page actions (Sort/Filter); M3 uses it only on search-first home screens |
| Search as the navigation rail's FAB / header item (`WideNavigationRail` header) | The rail header is for the primary action and the menu; search is not a create action, and the rail disappears on compact bottom-bar layouts, so it would need a second entry anyway. `NavigationSuiteScaffold`'s `primaryActionContent` is "typically a FAB"; no guidance puts search there ([adaptive navigation](https://developer.android.com/develop/ui/compose/layouts/adaptive/build-adaptive-navigation)) |
| A sixth navigation destination "Search" | Duplicates Songs and breaks the web's tab rules ([app-navigation](../app-navigation/spec.md)) |
| Songs filter field reused as global search | Songs' field filters one list with sort/filters; the web keeps them separate ([spec](spec.md#page-local-search-songs-is-separate)) |
| Modal bottom sheet copying the web mobile sheet | Not a Material search pattern; loses the search view's predictive back and IME handling |

## Surface content (all widths)

- `SearchBarDefaults.InputField` with placeholder "Search songs or players", leading back arrow when expanded (content description "Close search", `fst.global-search.close`), trailing clear `IconButton` when text is non-empty (`fst.global-search.clear`).
- Under the field: `FilterChip` row **Songs · Players · Bands** (single-select, tap again to clear = all), `fst.global-search.scope.*`. Web puts chips below results on phones for thumb reach; on Android the IME covers the bottom, so chips go **above** results (Material search view layout).
- `LazyColumn`: sticky section headers Songs → Players (`semantics { heading() }`), song rows reuse the Songs row composable (no status chips), player rows are `ListItem`s with an avatar monogram. Players section has its own `LinearProgressIndicator`/Retry/hint.
- Bands chip → no request; an info card with the [spec](spec.md#band-scope-blocked) explanation and a "Band Rankings" `TextButton` (`fst.global-search.bands-unavailable`).
- Tapping a result collapses the search (`searchBarState.animateToCollapsed()`), clears it, then navigates on the current destination's back stack; selected player → Statistics.
- The IME opens when the user opens search (focus the field in the expand callback); `imeAction = Search` closes the IME only (web parity: Enter does not open a result).

## Form factors and postures

Read `currentWindowAdaptiveInfo()` (`windowSizeClass` + `windowPosture`) and Jetpack WindowManager `FoldingFeature`s: tabletop = `HALF_OPENED` + horizontal fold, book = `HALF_OPENED` + vertical fold ([fold-aware apps](https://developer.android.com/develop/ui/compose/layouts/adaptive/foldables/make-your-app-fold-aware)). Width classes: compact < 600, medium 600–839, expanded 840–1199, large 1200–1599, extra-large ≥ 1600 dp; the last two need `supportLargeAndXLargeWidth = true` and behave as expanded here ([window size classes](https://developer.android.com/develop/ui/compose/layouts/adaptive/use-window-size-classes)).

| Device / pose | Window class | Search |
|---|---|---|
| Phone portrait / landscape | Compact / medium (landscape ≥ 600 dp wide) | Action → full screen (portrait); action → docked (landscape medium) |
| Book fold (`FST_Book_Fold`) folded | Cover screen: compact | Action → full screen |
| Book fold unfolded (flat) | Expanded (≈ 850 dp) | Persistent bar in the list pane's top bar when list/detail is split; docked results stay **inside that pane**, never across the hinge |
| Book fold **book posture** (vertical half-opened fold) | Expanded, separating vertical fold | Same as unfolded; docked panel width clamped to the pane that holds the bar |
| Book fold **tabletop** (horizontal half-opened fold) | Separating horizontal fold | Results panel sized to the **top half** (above the fold) with the field at its top; the IME occupies the bottom half. No results under the hinge |
| Passport fold (`FST_Passport_Fold`) folded | Cover: compact | Action → full screen |
| Passport fold unfolded | Expanded (≈ 840 dp, landscape-first) | Persistent bar; docked panel |
| Tri-fold (`FST_TriFold`) folded / partial / unfolded | Compact (360 dp) / medium (720 dp) / expanded (1080 dp) | Full screen / docked from action / persistent bar. No tabletop posture exists ([tri-folds](https://developer.android.com/develop/adaptive-apps/guides/foldables/trifolds-and-landscape-foldables)). Folds are FLAT when open, so the panel may span them; if `isSeparating` is ever true, clamp like the book fold |
| Tablet (`FST_Tablet`) | Expanded landscape, medium portrait | Persistent bar (landscape); action → docked (portrait) |
| Resizable / desktop windowing (`FST_Resizable`) | Changes live | Re-evaluate on every size change |

**Continuity:** query, scope, expanded state and results live in a `GlobalSearchViewModel` scoped to the activity (and the query/scope/expanded flag in `SavedStateHandle`), so folding, unfolding, rotating or resizing switches the surface (full screen ↔ docked) without losing text, focus or in-flight results. Test every transition in the table with `device.py posture`.

## Keyboard (large screens, Chromebooks, desktop windowing)

| Keys | Action |
|---|---|
| **Ctrl+K** and the **Search** key (`KEYCODE_SEARCH`) | Open global search and focus the field |
| **Ctrl+F** | Page-local find where it exists (Songs filter, Find Rival); otherwise same as Ctrl+K |
| Tab / Shift+Tab, ↑/↓ | Field → chips → results; arrows move within the results list |
| Enter on a focused result | Open it |
| Escape | Clear the field, then collapse search |

Handle them at the activity root (`onPreviewKeyEvent` on the scaffold, plus `onKeyShortcut`-free fallback in `Activity.dispatchKeyEvent` for the Search key) and list them in the system Keyboard Shortcuts Helper via `onProvideKeyboardShortcuts` (Meta+/) ([shortcuts helper](https://developer.android.com/develop/ui/compose/touch-input/keyboard-input/keyboard-shortcuts-helper)). Android has no vendor search chord. The adaptive quality guidelines require Esc to clear search or remove focus (`Keyboard_Exit`) and desktop-class apps to match common web/desktop shortcuts (`Keyboard_Parity`), which justifies Ctrl+K and Ctrl+F ([adaptive app quality](https://developer.android.com/docs/quality-guidelines/adaptive-app-quality)).

## Predictive back and TalkBack

- The M3 search bar collapses with the system predictive-back animation when expanded; do not add a separate `BackHandler` that fires before it. Back with text clears nothing: it collapses search (text is kept only for the session, not restored after navigation). `SearchBar` supports predictive back automatically since Material3 1.3.0 ([predictive back](https://developer.android.com/guide/navigation/custom-back/predictive-back-gesture)).
- TalkBack: the field's label is "Search songs and players"; chips expose selected state; section headers are headings; the players progress row is `liveRegion = Polite`; after a settled query, a polite announcement "{n} songs, {m} players" via a status text with `liveRegion = LiveRegionMode.Polite` (not `announceForAccessibility`, which is deprecated). Traversal: close → field → clear → chips → results; `isTraversalGroup` on the surface so focus doesn't leak to the page underneath; order with `traversalIndex` as the Compose search sample does ([semantics](https://developer.android.com/develop/ui/compose/accessibility/semantics)).
- Focus restoration: collapsing returns accessibility focus to the search action / bar.
- Respect font scale (field and rows grow; chips wrap), system animation scale (no custom stagger), dark/high-contrast text.

## Implementation and evidence (`android/app/src/main/java/com/festivalscoretracker/android/`)

| Area | Where / decision |
|---|---|
| Engine | `core/search/GlobalSearch.kt`: `SearchScope`, `GlobalSearchResults` (limits, `SongSearch` port, selected player → `SearchDestination.Section(Statistics)`, announcement), `GlobalSearchLayout` (presentation by **window** width; anchor geometry), `ShellShortcuts`. `presentation/search/GlobalSearchViewModel.kt`: activity-scoped, `SavedStateHandle` (query/scope/open), songs first then players, scrape-freeze countdown via the shared `ServiceRetryBackoff` |
| Surface | `ui/search/GlobalSearch.kt`: `GlobalSearchEntry` — a magnifier icon at **every** width (operator 2026-09-28: no persistent search field, it read as a website), in the floating toolbar on compact windows and the top app bar elsewhere; one per window. `GlobalSearchHost` (one shell-level invisible anchor the M3 bar grows from, then `ExpandedFullScreenSearchBar` / `ExpandedDockedSearchBar`), `GlobalSearchContent` |
| Anchor | Material positions the docked popup at `SearchBarState.collapsedCoords`. The shell owns that anchor (never a screen's node, which may be disposed mid-animation): full screen grows from the tapped icon; docked (≥ 600 dp) is end-aligned to the requester, ≤ 720 dp, never across a separating vertical hinge, and follows the entry's live bounds through rotation/fold/resize; a tabletop hinge caps the panel above the fold |
| Open/close | The view model owns "open"; a collapse Material makes itself (back, scrim, Escape) closes it. Closing **resets** query and scope ([spec](spec.md#query-scopes-and-fetching): web resets on close); posture/size changes never close it, so text, scope and results survive every fold/rotate/resize (activity handles those config changes) |
| Shell seam | `ShellActions.search: SearchChrome` + `FestivalScreen` actions: page actions → search → `notifications` slot → avatar. `ui/shell/ShellKeyboard.kt`: `ShellShortcutBridge` (from `MainActivity.dispatchKeyEvent`, listed via `onProvideKeyboardShortcuts`) and `RegisterPageFind { … }` for Ctrl+F (no page registers one yet → global search) |
| Test tags | Compose tags are UIAutomator ids (`testTagsAsResourceId` on the app root **and** on the search surface, which is its own dialog/popup window) |
| Unit/UI tests | `src/test/.../search/GlobalSearchCoreTest.kt`, `GlobalSearchViewModelTest.kt`, `src/test/.../ui/search/GlobalSearchUiTest.kt` (Robolectric phone + expanded; fake transport asserts no `/api/bands/search`) |
| Journeys | `python tools/android/search_journey.py [names]`: logging fixture (paths only) + one `device.py drive` hold per form factor; fails on any `/api/bands/search`. The shared fixture's `fixture-player-*` IDs are not 32-hex and the Android client rejects them, so the journey fixture remaps search rows to synthetic hex IDs. TODO(orchestrator): give `tools/mock_service.py` 32-hex fixture account IDs |
