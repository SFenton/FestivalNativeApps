# Navigation accessories (iPhone, Duo, pre-26)

> **What:** Lane A2's decision record for where each page's controls go: the top navigation bar, the tab-bar bottom accessory (Music's mini-player slot), search, or the page content. Covers iOS 26.1+ (Liquid Glass), iOS 17–26.0, and the iPhone Duo vertical bar. **Read when:** adding a toolbar item, search field or persistent action to any Apple page.

"Nav bar accessory" in operator requests means the **tab-bar bottom accessory**: the Liquid Glass capsule above the floating tab bar that holds Music's mini player (`tabViewBottomAccessory`). The web calls its tab bar "BottomNav", hence the name.

## APIs (iOS 27.1 SDK, verified in the swiftinterface and on the iOS 26.5 simulator)

| API | Availability | Finding |
|---|---|---|
| `tabViewBottomAccessory { }` / `(isEnabled:)` | 26.0 / **26.1** | One accessory per `TabView`, attached at the root. It sits above the tab bar and moves **inline** beside the minimized tab bar (`tabViewBottomAccessoryPlacement` `.expanded`/`.inline`). `isEnabled:` hides it per page. iPhone only; nothing on iPad/Mac |
| `tabBarMinimizeBehavior(.onScrollDown)` | 26.0 | Collapses the tab bar to the selected tab on scroll; the accessory goes inline (Music) |
| `.searchable` in a tab's `NavigationStack` | 15+ | Field in the nav-bar drawer under the large title (the old placement) |
| `searchToolbarBehavior(.minimize)` | 26.0 | Field becomes a **top** toolbar button, trailing, **after** the avatar (breaks the avatar-rightmost rule). Tapping morphs it into a top field |
| `DefaultToolbarItem(kind: .search, placement: .bottomBar)` | 26.0 | Inside a `TabView` the bottom toolbar renders **behind** the floating tab bar: unusable (screenshot evidence, same collision as [iphone.md](iphone.md)'s bottom Sort) |
| `.searchable(isPresented:)` set programmatically | 17+ | Did **not** activate the minimized field on 26.5 (from a button or a `.task`), so an accessory cannot open system search |
| `TextField` inside the accessory | 26.1 | Renders, but taps did not focus it, and the tab bar does not ride above the keyboard: rejected |
| `Tab(role: .search)` + `tabViewSearchActivation(.searchTabSelection)` | 18 / 26 | The system "search tab". Meant for app-wide search with its own landing page; ours is a filter over one page's list with sort, filters and scrubber. Rejected (a sixth tab duplicating Songs) |
| `safeAreaBar(edge:)` | 26.0 | Custom bar that insets the safe area and extends scroll-edge effects; rises above the keyboard. Used for the Songs editing field |
| `ToolbarItemPlacement.subtitle` / `.largeSubtitle` / `.largeTitle` | 26.0 | Text beneath/around the title. Not used yet; candidate for a player's "Selected" state |
| `ToolbarItemVisibilityPriority`, `toolbarMinimizationBehavior` | **27.0** | Duo overflow priority (W1 uses `.high` for the bell). Not available on the 26.5 iPhone |

## Rules

1. **The accessory holds one control: the page's primary, persistent, thumb-reach action.** Today: Songs search and a player page's Select/Switch/Deselect. Everything else stays in the top toolbar (HIG: toolbars hold a view's actions and navigation; the tab bar and its accessory are persistent chrome).
2. **Pages own the content; the root owns the slot.** `.festivalTabAccessory(token:isEnabled:) { … }` registers while the page is visible; `.festivalTabAccessoryHost()` on the iPhone `TabView` shows the newest registration (`Common/TabAccessory/TabAccessory.swift`). The content renders in the root's environment: pass closures, not page environment actions.
3. **Every accessory has a fallback.** Read `@Environment(\.isTabAccessoryAvailable)`; it is false before iOS 26.1, on the Duo vertical bar and on iPad/Mac. Fall back to a `Label` toolbar item (vertical bars need the symbol, overflow needs the title) or classic `.searchable`.
4. **No glass on glass.** The system draws the accessory's glass; buttons inside use flat `.borderedProminent`/`.bordered` fills.
5. **Tab roots keep the avatar rightmost** ([app-navigation/ios.md](../../controls/app-navigation/ios.md)): page actions use `.topBarTrailing` and the page ends its toolbar with `FestivalRootTrailingItems`.
6. The tab bar minimizes on scroll only while an accessory is shown, so journeys on other tabs keep a full tab bar.

## Decisions per page

| Page | iOS 26.1+ iPhone | iOS 17–26.0 | Duo vertical bar |
|---|---|---|---|
| Songs (root) | **Accessory:** "Search Songs" pill showing the query plus Clear. Tap hides the tab bar and docks a focused glass field (`fst.songs.search`) above the keyboard via `safeAreaBar`; losing focus returns to the pill. Top bar: Sort, Filter, Quick Links (Duration/Shop sorts), bell, avatar | `.searchable` drawer field; same top bar | `.searchable` in the bar (list column's horizontal bar once W2 splits it) |
| Player `/player/:id` (pushed) and Statistics (root) | **Accessory:** avatar, name, "Public/Selected Profile", then **Select**, **Switch** (confirms) or **Deselect** (confirms). Paused states (unverified/changed publication) show no action and keep their header footnote. Top bar: Quick Links (+ bell, avatar on Statistics) | Toolbar item `Label("Select Profile" …)`: `.primaryAction` pushed, `.topBarTrailing` before the bell on Statistics | Same toolbar item, so it lands **in the rail** (operator request; W1 owns rail order) |
| Song Detail | Top: Item Shop, Paths, Quick Links | Same | Same (vertical bar) |
| Leaderboards (root) | Top: metric menu, Quick Links, bell, avatar | Same | Same |
| Full / Band Rankings | Top: instrument + rank-by menus. Pager stays in content (a bottom bar collides with the tab bar) | Same | `.bottomBar` pager items (W3, [duo.md](duo.md)) |
| Compete, Settings (roots) | Top: Quick Links **before** bell + avatar | Same | Same |
| Suggestions (root) | Top: Filter **before** bell + avatar (fixed: `.primaryAction` put it right of the avatar) | Same | Same |
| Rivals (pushed on iPhone; tab root on iPad and Duo unfolded) | Top: Find Rival, Quick Links; as a tab root Find Rival is `.topBarTrailing` and the toolbar ends with bell + avatar (fixed: `.primaryAction` put it right of the avatar). Find Rival opens a player-search sheet, not an in-page filter, so it is not the Songs accessory pattern | Same | Same; the rail keeps bell + avatar, overflowing the hamburger (W3) |
| All Rivals, Rival Detail, Rivalry | Top: Quick Links | Same | Same |
| Bands, Band Detail, Player Bands | Top: Quick Links (Band Detail) | Same | Same |
| Shop | Top: Grid/List toggle (regular width only) | Same | Same |
| Player History, song leaderboards | Top: principal instrument/band-size switcher, Sort | Same | Same |

## Quick Links: accessory? No

Quick Links stays a **top toolbar `Menu`** ([quick-links/ios.md](../../controls/quick-links/ios.md)):

- The accessory is a single app-level slot, and the pages with Quick Links already need it (Player/Statistics use it for Select/Deselect; Songs for search). Two page controls cannot share it.
- Quick Links is secondary, in-page navigation; HIG puts navigation controls in the toolbar and keeps the tab area for persistent chrome. A jump menu opening upward from the bottom would cover the sections it jumps to.
- It is already rail-ready: a `Label` toolbar item moves into the Duo vertical bar automatically, and iPad/Mac get an inspector.
- `toolbarTitleMenu` (tap the title) was also considered: HIG reserves title menus for document-level commands (rename, duplicate), not jump lists.

## Open issues

- `TODO(orchestrator)`: search placement for Duo unfolded list/detail (W2): `.searchable` in the list column is the plan.
- The Songs editing field is custom (the system cannot focus search from an accessory); re-test `.searchable(isPresented:)` on each iOS release and switch to the system field when it works.
- The accessory is not in the Duo vertical bar; revisit if Apple adds a rail accessory.
