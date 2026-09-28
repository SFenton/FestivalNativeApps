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

## Rules

1. **The accessory is global Search plus at most one page action.** Search is on every page (root or pushed), as a field-shaped button that opens the global search sheet. A page may add one primary, persistent action after it: today only the player page's Select/Switch/Deselect. Everything else goes in the top toolbar (HIG: toolbars hold a view's actions and navigation).
2. **Pages own their action; the root owns the slot.** `.festivalTabAccessory(token:isEnabled:) { … }` registers while the page is visible; `.festivalTabAccessoryHost()` on the iPhone `TabView` shows Search plus the newest registration (`Common/TabAccessory/TabAccessory.swift`). The content renders in the root's environment: pass closures, not page environment actions.
3. **Every accessory item has a fallback.** `@Environment(\.isTabAccessoryAvailable)` is false before iOS 26.1, in the Duo vertical bar and on iPad/Mac. Then Search is a toolbar button (roots and pushed pages) and page actions are `Label` toolbar items (vertical bars need the symbol, overflow needs the title).
4. **No glass on glass.** The system draws the accessory's glass; buttons inside use flat `.borderedProminent`/`.bordered` fills.
5. **Tab roots keep the avatar rightmost** ([app-navigation/ios.md](../../controls/app-navigation/ios.md)): page actions use `.topBarTrailing` and the page ends its toolbar with `FestivalRootTrailingItems` (declare it in `FestivalRootView.rootProvidesTrailingItems`).
6. The tab bar does **not** minimize on scroll (`.never`): a collapsed bar hides the other tabs' labels on every page and broke 6 Songs journeys that switch tabs after scrolling. `TODO(orchestrator)`: Music minimizes (`.onScrollDown`, accessory goes inline); opt in only with the operator's go-ahead and a test helper that expands a collapsed bar.

## Decisions per page

| Page | iOS 26.1+ iPhone | iOS 17–26.0 | Duo vertical bar |
|---|---|---|---|
| Every page | **Accessory:** Search (opens [global search](../../controls/global-search/ios.md)) | Toolbar Search button (roots: before bell + avatar; pushed: `.primaryAction`) | Same toolbar button, in the rail |
| Songs (root) | Inline `.searchable` "Filter Songs" (page-local filter, HIG inline field). Top bar: Sort, Filter, Quick Links (Duration/Shop sorts), bell, avatar | Same | Same |
| Player `/player/:id` (pushed) and Statistics (root) | **Accessory:** Search, then avatar + **Select**, **Switch** (confirms) or **Deselect** (confirms). Paused states (unverified/changed publication) offer no action and keep their header footnote. Top bar: Quick Links (+ bell, avatar on Statistics) | Toolbar item `Label("Select Profile" …)`: `.primaryAction` pushed, `.topBarTrailing` before the bell on Statistics | `VerticalBarActionItem` in the rail, its own group after Back (W1); operator: "Select Profile in the rail" |
| Song Detail | Top: Item Shop, Paths, Quick Links | Same | Same (vertical bar) |
| Leaderboards (root) | Top: metric menu, Quick Links, bell, avatar | Same | Same |
| Full / Band Rankings | Top: instrument + rank-by menus. Pager stays in content (a bottom bar collides with the tab bar) | Same | `.bottomBar` pager items (W3, [duo.md](duo.md)) |
| Compete, Settings (roots) | Top: Quick Links **before** bell + avatar | Same | Same |
| Suggestions (root) | Top: Filter **before** bell + avatar (fixed: `.primaryAction` put it right of the avatar) | Same | Same |
| Rivals (pushed on iPhone; tab root on iPad and Duo unfolded) | Top: Find Rival, Quick Links; as a tab root Find Rival is `.topBarTrailing` and the toolbar ends with bell + avatar (fixed: it sat right of the avatar). Find Rival is a players-only search whose result opens a rival, a different action from global search | Same | Same; the rail keeps bell + avatar, overflowing the hamburger (W3) |
| All Rivals, Rival Detail, Rivalry | Top: Quick Links | Same | Same |
| Bands, Band Detail, Player Bands | Top: Quick Links (Band Detail) | Same | Same |
| Shop | Top: Grid/List toggle (regular width only) | Same | Same |
| Player History, song leaderboards | Top: principal instrument/band-size switcher, Sort | Same | Same |

## Quick Links: accessory? No

Quick Links stays a **top toolbar `Menu`** ([quick-links/ios.md](../../controls/quick-links/ios.md)):

- The accessory is one app-level slot. It already carries global Search on every page, and the player page (which has Quick Links) also puts Select/Deselect there. A third control would not fit, even less when the accessory is inline beside the minimized tab bar.
- Quick Links is secondary, in-page navigation; HIG puts navigation controls in the toolbar and keeps the tab area for persistent chrome. A jump menu opening upward from the bottom would cover the sections it jumps to.
- It is already rail-ready: a `Label` toolbar item moves into the Duo vertical bar automatically, and iPad/Mac get an inspector.
- `toolbarTitleMenu` (tap the title) was also considered: HIG reserves title menus for document-level commands (rename, duplicate), not jump lists.

## Open issues

- `TODO(orchestrator)`: Duo unfolded list/detail (W2) keeps Search in the rail as a toolbar button; revisit if the accessory becomes available beside a vertical bar.
- The accessory cannot host a real text field (focus and keyboard); re-test on each iOS release.
