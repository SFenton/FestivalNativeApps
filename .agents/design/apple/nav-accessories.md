# Navigation accessories (iPhone, Duo, pre-26)

> **What:** Lane A2's decision record for where each page's controls go: the top navigation bar, the tab-bar bottom accessory (Music's mini-player slot), global search, or the page content. Covers iOS 26.1+ (Liquid Glass), iOS 17–26.0, and the iPhone Duo vertical bar. **Read when:** adding a toolbar item, search field or persistent action to any Apple page.

"Nav bar accessory" in operator requests means the **tab-bar bottom accessory**: the Liquid Glass capsule above the floating tab bar that holds Music's mini player (`tabViewBottomAccessory`). The web calls its tab bar "BottomNav", hence the name.

## APIs (iOS 27.1 SDK; verified in the swiftinterface and on the iOS 26.5 simulator)

| API | Availability | Finding |
|---|---|---|
| `tabViewBottomAccessory { }` / `(isEnabled:)` | 26.0 / **26.1** | One accessory per `TabView`, attached at the root. It sits above the tab bar and moves **inline** beside the minimized tab bar (`tabViewBottomAccessoryPlacement` `.expanded`/`.inline`). iPhone only; none in the Duo vertical bar, on iPad or Mac |
| `tabBarMinimizeBehavior(.onScrollDown)` | 26.0 | Collapses the tab bar to the selected tab on scroll; the accessory goes inline (Music) |
| `Tab(role: .search)` + `tabViewSearchActivation(.searchTabSelection)` | 18 / 26 | The system search tab **counts toward the five-tab limit**: with five sections the bar became Songs · Suggestions · Compete · Statistics · **More**, hiding Settings and Search. Rejected |
| `.searchable` in a tab's `NavigationStack` | 15+ | Field in the nav-bar drawer under the large title |
| `searchToolbarBehavior(.minimize)` | 26.0 | Field becomes a **top** toolbar button, trailing, **after** the avatar (breaks the avatar-rightmost rule) |
| `DefaultToolbarItem(kind: .search, placement: .bottomBar)` | 26.0 | Inside a `TabView` the bottom toolbar renders **behind** the floating tab bar: unusable |
| `.searchable(isPresented:)` set programmatically | 17+ | Did **not** activate a minimized field on 26.5 (from a button or a `.task`) |
| `TextField` inside the accessory | 26.1 | Taps did not focus it, and the accessory does not ride above the keyboard: rejected; the accessory opens a sheet instead |
| `safeAreaBar(edge:)` | 26.0 | Custom bar that insets the safe area and extends scroll-edge effects |
| `ToolbarItemPlacement.subtitle` / `.largeSubtitle` / `.largeTitle` | 26.0 | Text beneath/around the title. Not used yet |
| `ToolbarItemVisibilityPriority`, `toolbarMinimizationBehavior` | **27.0** | Duo overflow priority (W1/W3 use it for bell and avatar). Not on the 26.5 iPhone |

## Rules (operator, 2026-09-28, final: "search and profile in the header, page tools float")

1. **Header (top navigation bar):** global **Search** and the **profile avatar** are separate buttons on every page, avatar rightmost (`FestivalRootTrailingItems` on tab roots: Search, then the bell + avatar capsule; `.globalSearchToolbarItem()` on pushed pages). The avatar opens profile selection (select, switch, deselect).
2. **Page tools float above the tab bar** (iPhone, horizontal tab bar): Songs **Filter** and **Sort**, and **Quick Links** on pages that have them, as *separate* round glass buttons, trailing-aligned, grouped in a `GlassEffectContainer` (`FestivalGlassGroup`) with 12 pt spacing. They are a bottom `safeAreaInset` of each tab's `FestivalTabStack` (`FloatingPageControls`), so lists scroll clear of them and page-owned bottom bars (the Full Rankings pager, Lane PB) stack above them.
3. **Why not the tab-bar accessory:** `tabViewBottomAccessory` renders one shared capsule. Merging Search, tools and Select into it read as a search bar with attachments (operator: "why is profile select part of the search bar?"); HIG wants distinct controls for distinct actions and keeps navigation and search in the toolbar. Separate floating buttons mirror the web FABs and stay individually tappable. The accessory stays unused.
4. **Player page Select / Switch / Deselect** is its own header button (text, prominent for Select/Switch; `ProfileIdentityToolbarItem`), `VerticalBarActionItem` in the Duo rail.
5. **Duo vertical bar, iPad, Mac:** no floating controls (`isTabAccessoryAvailable == false`); the same tools are toolbar items.
6. **Pages register, the root publishes.** `.festivalTabAccessory(token:order:isEnabled:) { … }` registers a tool while its view is visible (`DockOrder`: Filter 10, Sort 20, Quick Links 30); `.quickLinks(…)` registers the Quick Links menu itself and `QuickLinksToolbarItem` steps aside. Tools render in the root's environment: pass closures and include every displayed value in `token`.
7. **Sheets apply immediately.** Songs Filter and Sort have no Cancel/Apply: every change applies, and a trailing **Done** closes the standard `festivalSheet` modal.
8. The tab bar does not minimize on scroll (`.never` was needed only for the accessory; nothing collapses it now).

9. **Header legibility:** every page gets `TopEdgeScrim` (`Common/Chrome/PageChrome.swift`): iOS 26 `scrollEdgeEffectStyle(.soft, for: .top)` plus a dark gradient behind the bar region over the artwork (the gradient alone before 26). Collapsed inline titles are 20 pt semibold, Dynamic Type scaled (`NavigationTitleStyle`).
10. **Bell only with a selected profile**; Search and the avatar always show. On a 375 pt-wide iPhone a tab root carries at most drawer + page action + Search + bell + avatar; titles collapse inline beside them rather than truncating (large titles sit below the bar).
11. **Sheets open at the large detent** (`festivalSheet`, both presets); `.compact` can still be dragged down to medium.

## Decisions per page

| Page | Header (iPhone) | Floating tools (iPhone) | Duo vertical bar, iPad, Mac |
|---|---|---|---|
| Every page | Search; avatar (+ bell) on tab roots | — | Search, bell, avatar in the toolbar / rail |
| Songs (root) | Drawer, inline "Filter Songs" field, Search, bell, avatar | Filter · Sort · Quick Links (Duration/Shop sorts) | Sort, Filter, Quick Links as toolbar items |
| Player `/player/:id`, Statistics | **Select** / **Switch** / **Deselect** button, Search (+ bell, avatar on Statistics) | Quick Links | Rail: `VerticalBarActionItem`; iPad/Mac: header button |
| Song Detail | Item Shop, Paths, Search | Quick Links | Toolbar |
| Leaderboards, Compete, Settings, Rivals, Rival Detail, Rivalry, Band Detail | Page actions (metric menu, Find Rival…), Search, bell + avatar on roots | Quick Links | Toolbar |
| Suggestions (root) | Filter **before** Search, bell + avatar (fixed: it sat right of the avatar) | — | Toolbar |
| Full / Band Rankings | Instrument + rank-by menus, Search | Page-owned pager (Lane PB) | `.bottomBar` pager (W3) |
| Shop, Bands, Player Bands, Player History, song leaderboards | Existing items, Search | — | Toolbar |

Rivals is a tab root on iPad and Duo unfolded: Find Rival is `.topBarTrailing` and the toolbar ends with Search, bell + avatar.

## Quick Links: accessory?

**Floating tool, not the accessory** (operator, 2026-09-28). This lane first kept Quick Links in the top toolbar; the operator then asked for the web's bottom FAB dock, and finally for separate floating buttons rather than one merged bar. On iPhone Quick Links is a floating round glass button after Filter/Sort; on the Duo rail, iPad and Mac it stays a toolbar `Menu` (inspector later). The menu opens upward; its checkmark marks the active section.

## Drawer

Matches the web sidebar (`Sidebar.tsx`): Songs, Suggestions*, Statistics*, Rivals*, Leaderboards, Item Shop (*player), the current destination highlighted; the profile row (name → profile, **Deselect**) or **Select Profile**, then **Settings** pinned at the bottom. Bands and Licenses are not listed (Bands: search and leaderboard links; Licenses: Settings).

## Open issues

- `TODO(orchestrator)`: Duo unfolded list/detail (W2) keeps the tools in the rail as toolbar items.
- Songs draft/discard journeys (4) are skipped pending a rewrite for immediate-apply sheets.
