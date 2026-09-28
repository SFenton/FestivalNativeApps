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

## Rules (operator, 2026-09-28: a bottom dock like the web's)

1. **iPhone page tools live in a bottom dock above the tab bar**, like the web app's search pill + Sort + Quick Links FAB dock: global **Search** first, then the page's controls (Songs **Filter**, **Sort**; **Quick Links** on pages that have them; profile **Select/Switch/Deselect**). Order: `DockOrder` (`filter` 10, `sort` 20, `quickLinks` 30, `pageAction` 40). Everything else stays in the top toolbar.
2. **iOS 26.1+:** the dock is the system `tabViewBottomAccessory` (one Liquid Glass capsule; controls inside use flat fills or plain icons: no glass on glass). **iOS 17–26.0:** the same row on a `festivalGlassCapsule` in a bottom `safeAreaInset` of each tab's `FestivalTabStack` (`DockInset`), above the classic tab bar.
3. **Duo vertical bar, iPad, Mac:** no dock (`isTabAccessoryAvailable == false`); the same controls are toolbar items (`Label`s, so the rail can show them), Search included.
4. **Pages register, the root hosts.** `.festivalTabAccessory(token:order:isEnabled:) { … }` registers a control while its view is visible; `.quickLinks(…)` registers the Quick Links menu itself and `QuickLinksToolbarItem` steps aside in the dock. Controls render in the root's environment: pass closures, not page environment actions, and include every displayed value in `token`.
5. **Tab roots keep the avatar rightmost** in the top bar ([app-navigation/ios.md](../../controls/app-navigation/ios.md)); declare pages that end their toolbar with `FestivalRootTrailingItems` in `FestivalRootView.rootProvidesTrailingItems`.
6. The tab bar does **not** minimize on scroll (`.never`): a collapsed bar hides the other tabs' labels and broke 6 Songs journeys that switch tabs after scrolling. `TODO(orchestrator)`: Music minimizes (`.onScrollDown`); opt in only with the operator's go-ahead.
7. **Page-owned bottom bars** (e.g. the Full Rankings pager, Lane PB) use the page's own `safeAreaInset(.bottom)`: it stacks above the dock in both presentations, so the two never overlap.

## Decisions per page

| Page | iPhone dock (26.1+ accessory / 17–26.0 inset) | Top bar (iPhone) | Duo vertical bar, iPad, Mac |
|---|---|---|---|
| Every page | Search (opens [global search](../../controls/global-search/ios.md)) | — | Toolbar Search button (roots: before bell + avatar; pushed: `.primaryAction`) |
| Songs (root) | Search · Filter · Sort · Quick Links (Duration/Shop sorts) | Inline `.searchable` "Filter Songs", bell, avatar | Sort, Filter, Quick Links as toolbar items |
| Player `/player/:id` and Statistics | Search · Quick Links · avatar + **Select** / **Switch** / **Deselect** (confirming). Paused states offer no action | Bell + avatar (Statistics) | Rail: `VerticalBarActionItem` after Back (W1); iPad/Mac: labelled toolbar item |
| Song Detail | Search · Quick Links | Item Shop, Paths | Toolbar |
| Leaderboards, Compete, Settings, Rivals, Rival Detail, Rivalry, Band Detail | Search · Quick Links | Page actions (metric menu, Find Rival…), bell + avatar on roots | Toolbar |
| Suggestions (root) | Search | Filter **before** bell + avatar (fixed: it sat right of the avatar) | Toolbar |
| Full / Band Rankings | Search | Instrument + rank-by menus; pager in the page's own bottom inset (Lane PB) | `.bottomBar` pager (W3) |
| Shop, Bands, Player Bands, Player History, song leaderboards | Search | Existing toolbar items | Toolbar |

Rivals is a tab root on iPad and Duo unfolded: Find Rival is `.topBarTrailing` and the toolbar ends with bell + avatar (fixed: it sat right of the avatar).

## Quick Links: accessory?

**Yes, on iPhone** (operator decision, 2026-09-28, reversing this lane's first answer). The first answer kept Quick Links in the top toolbar because the accessory held only one control; with the dock holding a row of tools (the web's own FAB dock does exactly this), Quick Links belongs beside Sort. It stays a toolbar `Menu` on the Duo rail, iPad and Mac (inspector later). The menu opens upward from the dock; its checkmark still marks the active section.

## Open issues

- `TODO(orchestrator)`: Duo unfolded list/detail (W2) keeps Search and page tools in the rail as toolbar items.
- The dock cannot host a real text field (focus and keyboard); Search opens the sheet. Re-test on each iOS release.
- A dock with Search + Filter + Sort + Quick Links + Select would be crowded; no page has all of them today.
