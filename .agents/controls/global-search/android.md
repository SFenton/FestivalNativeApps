# Global search — Android notes

> **What:** the Compose/Material 3 design for the app-wide search entry point on every Android form factor and posture (phone, book and passport foldables, tri-fold, tablet, resizable windows), plus keyboard, predictive back, TalkBack and the implementation plan. **Read when:** implementing or changing global search in `android/` (lane `and-search`). Behavior and test IDs: [spec.md](spec.md). Adaptive shell: [design/android.md](../../design/android.md).

## Decision

**Material 3 search: a search action that expands into a full-screen search view on compact widths, and a persistent docked search bar with a docked results panel from medium width up.** The layout is chosen by window size class, never by device name or pixels.

| Width class (window) | Entry point | Expanded surface |
|---|---|---|
| Compact (< 600 dp): phone, book/passport cover screens, tri-fold folded | Magnifier `IconButton` in every page's `TopAppBar` actions, before the bell and avatar (`fst.global-search.open`) | `ExpandedFullScreenSearchBar`: covers the window, field at the top, scope segments under it, results below |
| Medium (600–839 dp): tri-fold partial, portrait tablet, small resizable windows | Same action icon (the top bar is still title + actions) | `ExpandedDockedSearchBar` anchored under the top bar at the end edge, ≤ 720 dp wide, a **fixed** 2/3 window height (tabletop: to the fold) |
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
- Under the field: a full-width row of three pill-shaped M3 `FilterChip`s **Songs · Players · Bands** (operator batch 6, 6.21: more pill-like than the earlier segmented row), equal widths with 8 dp gaps, no icons, ≥ 48 dp touch height, `selectableGroup` + `Selected` semantics; at most one is selected and tapping it again clears to all (web `aria-pressed` pills), `fst.global-search.scopes` / `fst.global-search.scope.*`. When a measured label does not fit its equal share (font scale 2.0 on a 360 dp tri-fold cover), the row scrolls horizontally with natural-width chips instead of truncating ("Playe"; `GlobalSearchLayout.scopeChipsFitEqually`, issue #141). Web puts chips below results on phones for thumb reach; on Android the IME covers the bottom, so chips go **above** results (Material search view layout).
- `LazyColumn` with no section titles (issue #299, 2026-10-04: the scope chips already name the scope; Material 3 search is an "Expandable search overlay" whose results are a plain list): song rows reuse the Songs row composable (no status chips), then player rows (`ListItem`s with an avatar monogram). Each scope and settled query starts at the top of a fresh scroll position (issue #141). Loading is one indeterminate `FestivalLoading` ring (36 dp, label "Searching", `fst.global-search.loading`) centred horizontally and vertically in the region between the scope chips and the bottom edge/keyboard (the docked surface already sits above the keyboard, see below); All waits for Songs **and** Players like the web, the Songs scope never waits for Players (`GlobalSearchViewModel.UiState.isBusy`). A players failure or freeze is `ServiceStatusInline(onRetry = null)` (`fst.global-search.players-error`), so it never shows Retry. An empty Players envelope is never an inline row (issue #99): All hides the section beside song rows, and when the shown scope(s) are empty `UiState.emptyState` drives `EmptyResults` (`fst.global-search.empty`): the shared `FestivalEmptyState` title (heading) + subtitle, no action, centred in a scrollable full-height box (300% font scale scrolls). With Retry gone, the IME Search action (`GlobalSearchViewModel.submit`) re-runs a failed or empty settled query; a loaded one is not re-requested. The under-two-characters hint is per scope (`GlobalSearchResults.enterQueryHint`), Bands included: Bands shows its hint until the query is long enough, then the band explanation (Robolectric `GlobalSearchContentUiTest`, `GlobalSearchViewModelTest`).
- No visible "N songs, X players" line (operator batch 6); the count is a TalkBack-only polite live region (undrawn 1 dp node, `fst.global-search.status`).
- The surface never resizes while typing (6.21): `GlobalSearchContent` fills the surface and hint, progress and results share one full-height region; the docked panel has one fixed height and Material's `DockedSearchBarLayoutImpl` already applies `imePadding()` to its surface, so content adds **no** keyboard inset of its own (a second `imeOverlap` padding hid the empty state under the keyboard on FST_Tablet, issue #141). Full screen keeps the whole window with the keyboard up or dismissed (FST_Phone, fixture, 2026-09-28); its field is `GlobalSearchLayout.fieldHeight` tall (body line at the current font scale + 32 dp, ≥ 56 dp) because `ExpandedFullScreenSearchBar` measures the field at the collapsed anchor's height (font scale 2.0 clipped a fixed 56 dp, issue #141).
- Bands segment → no request; an info card with the [spec](spec.md#band-scope-blocked) explanation and a "Band Rankings" `TextButton` (`fst.global-search.bands-unavailable`).
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

- The M3 search bar collapses with the system predictive-back animation when expanded. Back with text clears nothing: it collapses search (text is kept only for the session, not restored after navigation). `SearchBar` supports predictive back automatically since Material3 1.3.0 ([predictive back](https://developer.android.com/guide/navigation/custom-back/predictive-back-gesture)). Docked exception (issue #141): the expanded docked bar is a `Popup` whose overlay-priority back callback closed the panel *and* the keyboard in one Back and swallowed Escape. The popup's `dismissOnBackPress` is off; a default-priority `OnBackInvokedCallback` (API 33+) plus a Back key handler close it, so Back hides the keyboard first, then closes, and Escape clears then closes.
- TalkBack: the field's label is "Search songs and players"; scope pills expose selected state; there are no section headings (issue #299), so heading navigation lands on the empty-state title only; the centred spinner's label is "Searching"; after a settled query, a polite announcement "{n} songs, {m} players" via an undrawn status node (content description + `liveRegion = LiveRegionMode.Polite`) (not `announceForAccessibility`, which is deprecated). Traversal: close → field → clear → chips → results; `isTraversalGroup` on the surface so focus doesn't leak to the page underneath; order with `traversalIndex` as the Compose search sample does ([semantics](https://developer.android.com/develop/ui/compose/accessibility/semantics)).
- Focus restoration: collapsing returns accessibility focus to the search action / bar.
- Respect font scale (field and rows grow; chips scroll rather than truncate), system animation scale (no custom stagger), dark/high-contrast text.

## Implementation and evidence (`android/app/src/main/java/com/festivalscoretracker/android/`)

| Area | Where / decision |
|---|---|
| Engine | `core/search/GlobalSearch.kt`: `SearchScope`, `GlobalSearchResults` (limits, `SongSearch` port, selected player → `SearchDestination.Section(Statistics)`, announcement), `GlobalSearchLayout` (presentation by **window** width; anchor geometry), `ShellShortcuts`. `presentation/search/GlobalSearchViewModel.kt`: activity-scoped, `SavedStateHandle` (query/scope/open), one spinner until the scope's results settle (All waits for songs and players), scrape-freeze countdown via the shared `ServiceRetryBackoff` |
| Surface | `ui/search/GlobalSearch.kt`: `GlobalSearchEntry` — a magnifier icon at **every** width (operator 2026-09-28: no persistent search field, it read as a website), in the floating toolbar on compact windows and the top app bar elsewhere; one per window. `GlobalSearchHost` (one shell-level invisible anchor the M3 bar grows from, then `ExpandedFullScreenSearchBar` / `ExpandedDockedSearchBar`), `GlobalSearchContent` |
| Anchor | Material positions the docked popup at `SearchBarState.collapsedCoords`. The shell owns that anchor (never a screen's node, which may be disposed mid-animation): full screen grows from the tapped icon; docked (≥ 600 dp) is end-aligned to the requester, ≤ 720 dp, never across a separating vertical hinge, and follows the entry's live bounds through rotation/fold/resize; a tabletop hinge caps the panel above the fold |
| Open/close | The view model owns "open"; a collapse Material makes itself (back, scrim, Escape) closes it. Closing **resets** query and scope ([spec](spec.md#query-scopes-and-fetching): web resets on close); posture/size changes never close it, so text, scope and results survive every fold/rotate/resize (activity handles those config changes) |
| Shell seam | `ShellActions.search: SearchChrome` + `FestivalScreen` actions: page actions → search → `notifications` slot → avatar. `ui/shell/ShellKeyboard.kt`: `ShellShortcutBridge` (from `MainActivity.dispatchKeyEvent`, listed via `onProvideKeyboardShortcuts`) and `RegisterPageFind { … }` for Ctrl+F (no page registers one yet → global search) |
| Test tags | Compose tags are UIAutomator ids (`testTagsAsResourceId` on the app root **and** on the search surface, which is its own dialog/popup window) |
| Unit/UI tests | `src/test/.../search/GlobalSearchCoreTest.kt`, `GlobalSearchViewModelTest.kt`, `src/test/.../ui/search/GlobalSearchUiTest.kt` (Robolectric phone, medium, expanded and font scale 2.0; fake transport asserts no `/api/bands/search`), `GlobalSearchContentUiTest.kt` (stateless states, native-graphics chip label fit) |
| Device tests | `src/androidTest/.../journeys/GlobalSearchDeviceTest.kt` (`device.py test com.festivalscoretracker.android.journeys.GlobalSearchDeviceTest --avd FST_Phone`, `--avd FST_Tablet`, `--avd FST_Book_Fold --posture half`): ATF on every interaction, logged reading order per state (hint, results, scoped, bands, empty, players freeze, navigated), 48 dp targets, no hinge straddling, the empty state above the keyboard, keyless requests without selected-profile headers or band search; animator scale 0 |
| Journeys | `python tools/android/search_journey.py [names]`: logging fixture (paths only) + one `device.py drive` hold per form factor; fails on any `/api/bands/search`. The shared fixture's `fixture-player-*` IDs are not 32-hex and the Android client rejects them, so the journey fixture remaps search rows to synthetic hex IDs. TODO(orchestrator): give `tools/mock_service.py` 32-hex fixture account IDs |

## Validation (issue #141, 2026-10-04)

Live public service (keyless, `/api/songs` + `/api/account/search` only), debug build, dark theme, emulators via `device.py drive`; fixture-only states (loading, players freeze/error, empty) were checked with `GlobalSearchDeviceTest` and Robolectric instead.

| Configuration | Presentation | Findings |
|---|---|---|
| `FST_Phone` portrait, font 1.0 / 2.0 | Full screen | Font 2.0 clipped typed text in the 56 dp field → fixed (`fieldHeight`). Chips fit at 411 dp |
| `FST_Phone` landscape (≥ 600 dp) | Docked | One Back hid the keyboard **and** closed the panel; Escape was swallowed → fixed (docked back callback). The keyboard covers most of the short panel: accepted platform behaviour |
| `FST_Tablet` landscape / portrait, font 1.0 / 2.0, rotation while open | Docked over the list pane | Empty state (then with Retry, removed by #299) hidden under the keyboard (gone at 2.0) → fixed (double IME inset removed). Players → All kept the list scrolled to the players, hiding the songs → fixed (fresh list state per scope/query). Rotation re-anchors with query kept |
| `FST_Resizable` phone / foldable (841 dp) / foldable rotated (≈ 701 dp) / tablet / desktop | Full screen → docked live | Switches presentation on resize keeping the query; flat fold is non-separating, spanning is fine |
| `FST_Book_Fold` folded / half (book) / unfolded, folded font 2.0 | Full screen / docked in the left pane / docked | Half-open panel clamped left of the hinge; nothing straddles (device test) |
| `FST_Passport_Fold` folded / half / unfolded | Full screen / docked left pane / docked | No issues |
| `FST_TriFold` folded (360 dp) / partial / unfolded, folded font 2.0 | Full screen / docked / docked | Font 2.0 truncated chip labels ("Playe") → fixed (scrolling chip row) |
| System light theme | — | The app is dark-only by design; light mode leaves search dark with the same contrast |
| Animator scale 0 | — | Connected tests run with scales 0: open, results, close and navigation complete without waiting on motion |

Material 3 review (`material-3` skill, Compose): search uses `ExpandedFullScreenSearchBar` (compact) and `ExpandedDockedSearchBar` (≥ 600 dp), `FilterChip`s for scopes, `ListItem`-style rows, a plain result list without section headings (issue #299). Deliberate deviations: a magnifier action at **every** width instead of a persistent expanded-width `SearchBar` (operator 2026-09-28, the persistent field read as a website); a fixed 2/3-height docked panel so results don't jump while typing (6.21); brand dark palette instead of dynamic colour ([design/android.md](../../design/android.md)). The field's accessible name "Search songs and players" differs from its placeholder "Search songs or players" by contract (same pair on Windows).
