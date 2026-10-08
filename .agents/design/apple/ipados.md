# iPadOS design

> **What:** iPad shell, sidebar, list/detail, grids, keyboard and pointer decisions, each with the HIG file it follows (`apple-hig` skill, `~/.claude/skills/apple-hig/references/hig/`). **Read when:** building or changing any iPad layout.

iPadOS ships inside the one universal iOS app, **FestivalMobile** (`com.sfenton.festivalscoretracker.native`, `TARGETED_DEVICE_FAMILY` `1,2`; operator, 2026-10-02). iPhone stays portrait-locked (`UISupportedInterfaceOrientations`); iPad runs all four orientations (`UISupportedInterfaceOrientations~ipad`) with no `UIRequiresFullScreen`, so Split View, Slide Over and resizable windows work ([build-and-run](../../platforms/apple/build-and-run.md)). The shell is picked at run time by size class, never by idiom or orientation (HIG `layout.md`: "choose layout from size classes, not device type"; `multitasking.md`: adapt to every window size), so every iPad decision below is a size-class or `sectionChrome == .sidebar` branch that leaves iPhone unchanged. The single universal 1024 px `AppIcon` also produces the iPad icon entries; `UILaunchScreen` is shared (`launching.md`).

The Home Screen name is **FST**, the same as the iPhone app ([iphone.md](iphone.md#home-screen-name)).

## Shell

| Decision | Detail | HIG |
|---|---|---|
| Sidebar at regular width, phone tabs at compact | `ShellPresentation.usesSidebarShell(supportsSidebar:widthClass:)`: iPad + regular → `NavigationSplitView` sidebar; iPad + compact (Slide Over, narrow Split View, narrow Stage Manager window) → the iPhone `TabView` + drawer + floating page tools, with the phone section set (Compete). Size class, never idiom or orientation, picks it, and it is known on the first pass | layout.md "Choose layout from size classes, not device type/idiom or orientation"; "Larger spaces may ... switch a tab bar to a sidebar"; split-views.md iPadOS "design for narrow, compact, and intermediate fluid widths" |
| `NavigationSplitView`, not `sidebarAdaptable` | The sidebar has no tab-bar conversion at regular width (web sidebar parity); compact width switches to the phone tabs instead | tab-bars.md iPadOS "A sidebar without conversion uses `NavigationSplitView`"; sidebars.md "To display only a sidebar, use `NavigationSplitView`" |
| Sidebar rows = web sidebar | `SidebarMenu.browse`: Songs, Suggestions\*, Statistics\*, Rivals\*, Leaderboards, Item Shop (\*player; Item Shop honours Hide Item Shop). Item Shop is its own destination (`FestivalSection.shop`, sidebar only) so it keeps the selected highlight | split-views.md "Persistently highlight the current selection in each pane" |
| Native selectable `List(.sidebar)` | System selection highlight, pointer highlight and arrow-key navigation; replaces the old custom accent-bar rows. No sidebar title (it would be the app name) | keyboards.md "iPadOS navigates text fields, text views, sidebars"; toolbars.md "Never use the app name" |
| Footer = web sidebar footer | Selected player (avatar + name opens their page; **Deselect** with confirmation) or **Select Profile**, then **Settings** | sidebars.md (customizable, compact hierarchy); writing.md Title Case labels |
| Sidebar hide/show | System toggle and edge swipe; shown by default in both orientations | sidebars.md "Consider letting people hide/show the sidebar ... but do not hide it by default" |
| Toolbar | Unchanged root chrome: page tools (Sort, Filter, Quick Links, page menus) then Search, bell, avatar on every root; overflow goes to the system **…** | toolbars.md "macOS/iPadOS add system overflow when items no longer fit—don't add one manually" |
| Songs filter field | Pinned navigation-bar drawer field on iPad too: the automatic placement collapsed it into a second magnifier beside global Search | searching.md "Show current scope with descriptive placeholder" |

Width changes keep state: per-section paths live in the root; `FestivalTabPolicy.adapt` maps Compete ↔ Leaderboards and carries Item Shop onto Songs (`[.shop]`) when the sidebar disappears.

## List/detail

Superseded 2026-10-04 by [split-view.md](split-view.md): no persistent sidebar (the destinations are in the overlay flyout, `ShellPresentation.Navigation.flyout`) and no always-on columns. List pages split **on demand** in a landscape regular window at the exact midpoint (`OnDemandSplitStack`, `OnDemandSplitPolicy`); portrait and compact windows push. Implementation, page table and measurements live in split-view.md.

- Rejected on iPadOS 26.5 for the old three-column layout (still true): a `NavigationSplitView` nested in another split's detail column never reappeared after one stack had been shown there. The on-demand split is an `HStack` of two `NavigationStack`s with no `NavigationSplitView` around it, so each pane keeps its own bar.
- Shop stays a grid that pushes Song Detail.

## Grids and sheets

| Page | iPad behavior | HIG |
|---|---|---|
| Shop | Adaptive art grid (`.adaptive(minimum: 210)`), List/Grid toggle; list at accessibility sizes | collections.md "Prefer the familiar standard horizontal row or grid" |
| Leaderboards, Profile/Statistics instrument cards | Two flexible columns when their column is ≥ 600 pt (column layout above); Leaderboards also keeps each card ≥ 340 pt at the default text size (`LeaderboardsScreen.usesTwoColumns`, scaled with Dynamic Type; Android's 340 dp minimum), so a landscape split's leading pane shows one column (#352) | layout.md (adapt to size classes) |
| Song Detail instrument cards and band previews (#366) | `.adaptive(minimum: 360)`: two columns when the page is ≥ ~730 pt (full-width detail); one in a list/detail detail column | collections.md "make dynamic layout changes sensible and easy to track" |
| Sheets | `festivalSheet` applies `presentationSizing(.form)` (or `.page`) at regular width, centered; compact windows get the phone sheets | sheets.md "Prefer page or form sheet styles in an iPadOS app" |
| Popovers | Not used for page content; menus (Quick Links, metric pickers) are system menus | popovers.md "Avoid popovers in compact views" |

## Multiwindow

**Decision (2026-10-02): support multiple windows on iPad, opened only by the person.** People compare songs, players and rivals side by side, and iPadOS lets one app offer several windows (multitasking.md iPadOS "multiple windows can come from one app"; designing-for-ipados.md "people view multiple apps together"). The app never opens one by itself (windows.md "Choose the right moment to open a new window ... avoid it as default behavior unless it makes sense for your app").

| Part | Detail | HIG |
|---|---|---|
| Opening | System File › New Window and the app switcher; **Open in New Window** in a Songs row's or a ranking player row's context menu (`openInNewWindowMenu`, iPad only, needs `supportsMultipleWindows`) | windows.md "Consider offering a context-menu or File-menu command to view content in a new window" |
| Content | `WindowGroup(for: FestivalWindowRoute.self)`: `.song(songId:)` (looked up in the shared catalogue, opened on Songs) or `.player(accountId:displayName:)` (pushed on Leaderboards). Codable ids only, so the system can restore the window | windows.md (`OpenWindowAction`) |
| State | One process-wide `FestivalSession` (selected profile, publication, caches, first-run arbitration) shared by every window; each window keeps its own selection, paths, sheets and menu-bar commands (`focusedSceneValue`) | multitasking.md "Save and restore context" |
| iPhone | `UIApplicationSupportsMultipleScenes` is true in the universal plist, but iPhone shows one window and the context menu is not attached there | |

Words: user-facing text says "window", never "scene" (windows.md "Say *window* in user-facing content"). Journey: `testOpenInNewWindowSharesProfile`.

## Window sizes

Exact tiles from the window-controls menu (long-press Zoom; driver `tile:`), FST iPad Pro 11" (1194 × 834 pt screen, 1210 pt framebuffer width):

| Tile | Landscape | Portrait | Shell |
|---|---|---|---|
| Full | 1210 pt | 834 pt | Flyout shell; list pages split on demand in landscape only |
| ½ (Left/Right) | 600 pt | 412 pt | Compact → phone tabs |
| ⅓ (Arrange thirds) | 396.5 pt | 375 pt (minimum) | Compact → phone tabs |
| Drag-resized | 375 pt minimum … full; ~830 pt after growing from the minimum (regular) | same | By size class |

iPadOS decides the size class; the app never checks a width for the shell (layout.md "Choose layout from size classes"; multitasking.md "Apps don't control or receive notice of the chosen configuration, so adapt to every window size"). Journey: `testNarrowWindowFallsBackToTabs`.

## Page status (iPad Pro 11", live SFentonX captures in `~/FestivalShowcase/native-ipad/`)

| Page | Landscape (1194 pt) | Portrait (834 pt) | ⅓ / ½ tiles (compact) |
|---|---|---|---|
| Songs → Song Detail | Full width, two cards per row under each header; Song Detail pushes full width, its full boards and score history open in the trailing half | One card per row; everything pushes | iPhone tabs, drawer |
| Leaderboards → Full/Band Rankings → Player/Band | Overview and rankings full width; a player or band opens in the trailing half | Push | iPhone (Compete slot) |
| Rivals → Rival Detail | Rivals full width; a rival opens in the trailing half (Rivalry pushes inside it) | Push | iPhone (Compete) |
| Settings → topic or Licenses | The list stays on the left; with nothing selected, the right half shows the Settings placeholder. A chevron row opens its topic or Licenses there ([split-panes](../../patterns/split-panes.md) R6, #371) | Push | iPhone |
| Statistics, Item Shop, Suggestions, Compete | Full width, existing adaptive grids | Same | iPhone |

## Menu bar

iPadOS 26 reveals a menu bar (pointer at, or swipe down from, the top edge). `FestivalCommands` (`App/Shell/FestivalCommands.swift`, `.commands` on the `WindowGroup`) mirrors the Mac's `MacCommands`; on iPadOS before 26 the same commands fill the ⌘-hold overlay. Order follows the HIG (app, File, Edit, View, app menus, Window, Help; the-menu-bar.md "Support the standard menus and their order").

| Menu | Items | HIG |
|---|---|---|
| FST (app) | system Settings (the app's iPadOS Settings page), then **App Settings…** (the in-app Settings destination) | the-menu-bar.md iPadOS "Reserve Settings for opening your app's page in iPadOS Settings; put internal-preferences ... beneath it, in the same group" |
| File | system New Window / Close (see Windows) | |
| Edit | **Search Festival…** ⌘F | keyboards.md Command-F "Open Find window"; the-menu-bar.md "Determine whether Find menu items belong in the Edit menu" |
| View | Refresh ⌘R, Sort…, Filter…, Rank By ▸ (checkmark on the metric in effect), Instrument ▸ (Full Rankings' board, issue #294), **Show Navigation** ⌃⌘S (opens the flyout; replaces the system sidebar toggle), **Close** Esc (the flyout, else the open trailing pane) | the-menu-bar.md View menu; menus.md checkmarks; "Make sure a submenu remains available even when its items are unavailable" |
| Go | Back ⌘[, every destination (⌘1…⌘9 for the visible ones, others disabled), Search… ⌘K, Next / Previous Section ⌥⌘↓ / ⌥⌘↑ (no Quick Links ▸ submenu: listing the page's sections left the whole menu bar unresponsive in the flyout shell, live A/B 2026-10-05; the toolbar Quick Links menu lists them) | the-menu-bar.md iPadOS "Tab-style navigation: consider a View menu item per tab, and key bindings for each" (kept under Go, as on the Mac); "Disable, don't hide" |
| Song | Paths…, Open in Item Shop | the-menu-bar.md "Provide app-specific menus for custom commands ... the menu bar enables keyboard shortcuts and Full Keyboard Access" |
| Profile | Select / Switch Profile… ⇧⌘P, Deselect Profile, Find Rival…, Notifications | same |
| Help | Festival Score Tracker Website, What's New, Licenses | the-menu-bar.md Help menu |

- **Scene-safe:** each window's root publishes its own `FestivalShellCommands` with `focusedSceneValue`; pages publish Sort/Filter, Rank By, Instrument, Quick Links and Song tools only from the top page of their column (`menuBarColumn(isTop:isList:)`, `MenuBarTopPagePublisher`), so the menu acts on the window and page in front. Every command is also reachable in the UI (the-menu-bar.md iPadOS "Ensure every function is reachable in your UI").
- iPad drops the hidden `KeyCommandButton`s (the menu carries the shortcuts); iPhone keeps them and publishes nothing (`MenuBarCommandsSupport.isAvailable`).
- Evidence: `testMenuBarShortcuts`, `testCommandDigitSelectsDestination`; menu captures `~/FestivalShowcase/native-ipad/2/menu-{go,view,song,profile,help}.png` (rotate 270°). Driver: reveal with `drag:0.5,0.0,0.5,0.12`, open with `systemTap:Go`.

## Keyboard and pointer

| Shortcut | Action | Note |
|---|---|---|
| ⌘F, ⌘K | Global search | keyboards.md: Command-F "Open Find window" |
| ⌘1…⌘9 | Visible destinations in flyout order (tab order when compact); the current one pops to its root | `SidebarMenu.destination(forDigit:in:)`, `FestivalShellCommands.digit(for:)` |
| ⌘[ | Back one page: the trailing pane's pushed page, then the open item (closing the split), then the list page | Repurposes the standard Command-[ "Left-align selection": the app has no text editing (keyboards.md "Only consider it when the standard action doesn't make sense") |
| ⌘R | Refresh the frontmost refreshable page (`RefreshCommandRegistry`, `festivalRefreshable`) | Songs, Leaderboards, Suggestions, Band Detail |
| ⇧⌘P | Select / Switch Profile | keyboards.md "Prefer [Shift] as secondary modifier complementing a related shortcut" |
| ⌥⌘↓ / ⌥⌘↑ | Next / Previous Quick Links section | keyboards.md: Option "for less-common commands" | Pointer: list/detail rows use the highlight effect on their rounded card shape (no scale: rows sit edge to edge), sidebar footer buttons the highlight effect, system bar buttons their defaults (pointing-devices.md "highlight for small elements ... hover for large ones"; "reserve scaling for elements that can grow without crowding neighbors (not table rows)").

## Keyboard-only and Full Keyboard Access (2026-10-03)

HIG keyboards.md: "Support Full Keyboard Access when possible"; "iPadOS navigates text fields, text views, sidebars ... but avoid keyboard navigation for controls"; focus-and-selection.md iPadOS: "Tab moves among groups; arrow keys move directionally only within one".

| Check | Result |
|---|---|
| ⌘ shortcuts and the menu bar | Pass: `testMenuBarShortcuts`, `testCommandDigitSelectsDestination`, `testExactTilesDropUnchosenDetail` (⌘1 in a compact window) |
| Tab / arrows without FKA (fixture, landscape) | Tab focuses the **Filter Songs** field (the first focus group); further Tab, ↓ and Return stay in the field; the sidebar and list never took keyboard focus. The simulator also shows the software keyboard, i.e. it reports no hardware keyboard (`~/FestivalShowcase/native-ipad/2/keyboard-no-fka-tab-arrows.png`) |
| Full Keyboard Access | The iPad simulator lists it (Settings › Accessibility › Keyboards & Typing › Full Keyboard Access, `FKAEnabledSwitch`), but tapping the switch through XCUITest left it off (value 0, no focus rings), probably because no hardware keyboard is attached; Simulator › I/O › Keyboard is a host app preference, left alone. Driver: `appLaunch:`/`appTap:`/`appTree:` |

## Open

- Full Keyboard Access and sidebar/list arrow-key focus need a check with a hardware keyboard (a real iPad, or the simulator with its hardware keyboard connected by the operator).
- Debug: `FST_DEBUG_LIST_DETAIL=1` overlays the window width, sidebar extent and split sections (root shell).
- Never fix row counts or hardcode device sizes: chips wrap (5 + 4 where the web tablet shows 9 in one row) as the detail width changes.
- A Form in a centered sheet may need scrolling to expose Reset above a pinned footer.
- Always exercise Hide Sidebar with a detail visible: badge padding once caused a main-thread layout loop there.
- 2026-10-04: the three-column sidebar|list|detail layout and persistent sidebar are superseded by [split-view.md](split-view.md) (overlay flyout, on-demand split at the exact midpoint in landscape only).
