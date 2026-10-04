# Navigation accessories (iPhone, Duo, iPad)

> **What:** Decision record for where each page's controls go on iPhone, iPhone Duo and iPad: the top navigation bar, the tab bar's Search tab, an inline list filter, or the page content (issue #92 replaced the tab-bar accessory dock of #42/#84/#89). **Read when:** adding a toolbar item, search field or persistent action to any Apple page.

The tab-bar bottom accessory (`tabViewBottomAccessory`, Music's mini-player slot) is **not used** since issue #92: nothing rides on the tab bar. macOS keeps its own window toolbar and search (`.agents/platforms/apple/macos.md`).

## APIs (iOS 27.1 SDK; verified in the swiftinterface and on the iOS 26.5 simulator)

| API | Availability | Finding |
|---|---|---|
| `Tab(value:role: .search)` | 18 | Separate trailing round Search button beside the tab capsule on iOS 26 (iPhone), a separate item at the end of the folded Duo rail. **Counts toward the five-tab limit**: five sections + Search put Search under **More** (26.5, measured again for #92), so compact phone tabs drop one section (rule 3) |
| `tabViewSearchActivation(.searchTabSelection)` | 26.0 | Choosing the Search tab focuses its `.searchable` field: keyboard up at once. The system **Close** button beside the field dismisses search |
| `.searchable(text:isPresented:)` in the Search tab | 17+ | `isPresented` going false is the Close tap; the shell then returns to the previous tab. Close also clears the query (system) |
| `.searchable(placement: .navigationBarDrawer(displayMode: .always))` | 15+ | Pinned field under the large title; stays while the list scrolls |
| `tabBarMinimizeBehavior(.onScrollDown)` | 26.0 | Collapses the tab bar to the selected tab and Search on scroll; kept on the horizontal tab bar |
| `ToolbarSpacer(.fixed, placement:)` | 26.0 | Splits trailing items into separate Liquid Glass groups |
| `ToolbarItemVisibilityPriority`, `toolbarMinimizationBehavior` | **27.0** | Duo overflow priority (bell, profile, Quick Links `.high`). Not on the 26.5 iPhone |
| `tabViewBottomAccessory` | 26.1 | Removed (#92). Findings kept for history: a `Menu` there never opened, a `TextField` there did not focus, and the content's bottom safe area did not reliably follow the minimized bar |
| `searchToolbarBehavior(.minimize)` | 26.0 | Field becomes a top toolbar button after the avatar (breaks the avatar-rightmost rule): unused |
| `DefaultToolbarItem(kind: .search, placement: .bottomBar)` | 26.0 | Inside a `TabView` the bottom toolbar renders behind the floating tab bar: unusable |

## Rules (issue #92, 2026-10-04)

HIG sources: `apple-hig/references/hig/toolbars.md`, `search-fields.md`, `searching.md`, `tab-bars.md`, `designing-for-iphone-duo` (via `duo.md`), `buttons.md`.

1. **Top bar, trailing, on every page.** Reading right to left: **Profile** always last; **Notifications** to its left only with a selected profile; **Quick Links** to its left only on pages with Quick Links; other page actions further left in page order (Songs: Sort, then Filter). Songs therefore reads Sort · Filter · Quick Links | Notifications · Profile. HIG Toolbars: "Trailing: important always-available items." Tab roots end with `FestivalRootTrailingItems`; pushed pages get the same account items from `.pageTrailingItems()` (`PageTrailingItems`, `Features/Search/GlobalSearchView.swift`), which steps aside when the page already provides them (`FestivalRootTrailingProvidedKey`) or the Mac shell owns the toolbar.
2. **Two Liquid Glass groups:** page tools (Sort, Filter, Quick Links, other page actions), then account (Notifications, Profile), separated by `ToolbarSpacer(.fixed)` in horizontal bars (`RootChromeTrailingGroups.separatesAccount`; pages without tools have one group). HIG Toolbars: "generally use no more than three groups". The Duo vertical bar adds no fixed spacer (HIG iPhone Duo: "system spacing adapts, so don't add fixed spacing"). Page actions use `.festivalPageAction` (never `.primaryAction`, `PushedPageAvatarPlacementTests`), icon-only system symbols with their own accessibility labels; standard bar buttons get the system's ≥ 44 pt hit expansion (HIG Buttons: "the hit region is at least 44x44 pt").
3. **Global search is a Search tab.** A trailing `Tab(role: .search)` (`RootTab.search`) shows `GlobalSearchTab` with the keyboard up. HIG Search fields: a separate trailing tab "focuses the field and opens the keyboard immediately… choose it for fast, transient search that returns to the previous tab on exit"; HIG Tab bars: "A dedicated Search tab may be trailing." The section underneath stays selected: **Close** or tapping that section returns to it with its stack intact, and a chosen result is pushed on it (`RootTabTransition`, unit-tested). The query and scope survive while closed, but the system clears the text on Close. **No other global-search entry point** on iOS: no accessory, dock, toolbar button or floating capsule; ⌘F/⌘K select the Search tab. Five-tab limit: `FestivalTabPolicy.fittingSearchTab` drops **Statistics** first from compact phone tabs (player: Songs · Suggestions · Compete · Settings · Search); the drawer's Statistics row pushes it. Songs, Compete and Settings are never dropped (the drawer has no Compete row or pushable Settings). On folded Duo this also returns the rail's Profile slot (with six rail tabs only the bell fit beside `…`).
4. **iPad:** a regular-width window keeps the sidebar; a **Search** row heads it (`fst.nav.sidebar.search`) and shows the same search page in the detail column, field **unfocused** (HIG Search fields: "on iPad with only a virtual keyboard, leave it unfocused to avoid unexpected keyboard coverage"), with the account items in that column's bar. Compact iPad windows use the phone tabs, Search tab included. The column that owns a page shows its top-bar items.
5. **Inline list filter where the web has one.** Songs uses `.searchable(text:placement: .navigationBarDrawer(displayMode: .always), prompt: "Filter Songs")`: pinned above the list, filtering it with the current sort and filters (HIG Search fields: "Use an inline field when adjacency clarifies that it filters one view rather than searches globally… Put a top inline field above its list and consider pinning it"; "Use placeholder text to state what is searchable"; HIG Searching: Music "filters current songs/albums"). No second magnifier button. Only Songs has a list text filter on the web (`SongsToolbar.tsx`); Item Shop and the player page have none, so they get no field.
6. **Overflow on narrow bars.** HIG Toolbars (iOS): "Put only essential actions in the main area; use More for the rest." On the horizontal iPhone tab bar, `SongsToolbarFold.folds` folds Sort and Filter into one **Sort and Filter** menu (`slider.horizontal.3`, not an ellipsis: HIG iPhone Duo "reserve ellipsis for overflow") below 390 pt or at accessibility text sizes; Quick Links, Notifications and Profile stay visible. The Duo vertical bar and the iPad sidebar keep system overflow, with Quick Links, bell and profile at `visibilityPriority(.high)` (`RootChromeRailItem`).
7. **Tab bar minimizes on scroll** on the horizontal iPhone tab bar (`RootTabBarBehavior`), with nothing riding on it; Duo rail and iPad keep `.automatic`.
8. **Player page Select / Switch / Deselect** is its own header button (text, prominent for Select/Switch; `ProfileIdentityToolbarItem`), `VerticalBarActionItem` in the Duo rail.
9. **Sheets apply immediately.** Songs Filter and Sort have no Cancel/Apply: every change applies, and a trailing **Done** closes the standard `festivalSheet` modal. Sheets open at the large detent.
10. **Header legibility:** every page gets `TopEdgeScrim` (`Common/Chrome/PageChrome.swift`): iOS 26 `scrollEdgeEffectStyle(.soft, for: .top)` plus a dark gradient behind the bar region over the artwork, at most 150 pt and ending 32 pt below the bar (`TopEdgeScrim.height(topInset:)`, issue #286), so it never dims a Quick Links landing under a short iPad, landscape or Duo bar. Collapsed inline titles are 20 pt semibold, Dynamic Type scaled (`NavigationTitleStyle`).
11. **Monogram avatar** renders to a cached image (`MonogramLabel`/`MonogramImageCache` in `App/Shell/RootChrome.swift`) so it stays a standard bar button with the system hit expansion (issue #15); a custom-view item would not get it.

## Decisions per page

| Page | Top bar, trailing (iPhone) | Duo vertical bar, iPad |
|---|---|---|
| Every page | Page tools \| Notifications (selected profile) · Profile | Same items; rail overflow by priority |
| Songs (root) | Sort · Filter · Quick Links (non-Title sorts) \| bell · avatar; pinned "Filter Songs" field. ≤ 390 pt or AX text: Sort and Filter menu · Quick Links \| bell · avatar | Sort, Filter, Quick Links; "Filter Songs" field |
| Player, Statistics | Select/Switch/Deselect, Quick Links \| bell · avatar | Rail: `VerticalBarActionItem` |
| Song Detail | Item Shop, Paths, Quick Links \| bell · avatar | Toolbar |
| Leaderboards, Compete, Settings, Rivals, Band Detail | Page actions, Quick Links \| bell · avatar | Toolbar |
| Full / Band Rankings | Instrument + rank-by menus \| bell · avatar; page-owned pager above the tab bar (Full Rankings: shared pinned `RankingsPagerView`, issue #294; Band Rankings: floating pager) | `.bottomBar` pager |
| Search tab | — (transient; system Close beside the field) | iPad sidebar Search: bell · avatar |

## Small widths

`FST_DEBUG_CANVAS_WIDTH=375` (Debug) lays the app out in a 375 pt canvas on the 402 pt iPhone 17 Pro. Captured with SFentonX for #92: Songs folds Sort and Filter into one menu; Quick Links, bell and avatar stay visible, nothing clipped.

## Drawer

Matches the web sidebar (`Sidebar.tsx`): Songs, Suggestions*, Statistics*, Rivals*, Leaderboards, Item Shop (*player), the current destination highlighted; the profile row (name → profile, **Deselect**) or **Select Profile**, then **Settings** pinned at the bottom. Bands and Licenses are not listed (Bands: search and leaderboard links; Licenses: Settings).

## Open issues

- `TODO(orchestrator)`: Duo unfolded list/detail (W2) keeps the tools in the rail as toolbar items.
- The Duo inner display's regular section set (six sections + Search) relies on the system bar's overflow; not yet captured after #92.
