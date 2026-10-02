# macOS design

> **What:** the Mac shell and page-layout decisions, each with the `apple-hig` file it rests on. **Read when:** changing the Mac window, sidebar, toolbar, menus, Settings window or a page's Mac layout. Host limits and the evidence tool: [platforms/apple/macos.md](../../platforms/apple/macos.md).

Code: `apple/Apps/macOS/FestivalDesktopApp.swift` (scenes) and `apple/Sources/FestivalUI/Mac/**` (`MacRootView`, `MacNavigation`, `MacListDetailStack`, `MacCommands`, `MacSettingsView`, `MacDebugHooks`). The iPhone/iPad `FestivalRootView` is not used on the Mac; pages, `AppRouteDestination`, `ListDetailPolicy` and `FestivalSession` are shared. HIG files are `~/.claude/skills/apple-hig/references/hig/<file>.md`.

## Shell decisions

| Decision | HIG basis (file › clause) |
|---|---|
| One primary `Window` (no File › New Window, tabbing off) holding a `NavigationSplitView`: sidebar + detail | windows › "Choose the right moment to open a new window … avoid it as default behavior"; designing-for-macos › "fewer nested levels and less modality" |
| Sidebar rows follow the web pinned sidebar: Songs, Suggestions\*, Statistics\*, Rivals\*, Compete\*, Leaderboards, Item Shop (\* selected player; Item Shop hidden by Settings › Hide Item Shop). SF Symbols tinted by the accent | sidebars › "Consider using familiar SF Symbols … in macOS, honor the accent color people choose" |
| Sidebar collapsible (toolbar button + View › Show/Hide Sidebar via `SidebarCommands`), shown by default; width 190–300 pt (ideal 220) | sidebars › "do not hide it by default … macOS a show/hide button or View-menu commands" |
| Selected player in the sidebar footer (name → Statistics, **Deselect**; **Select Profile** when anonymous). The same actions are in the Profile menu and the toolbar avatar | sidebars › macOS "Keep critical information/actions away from the bottom, which may be offscreen" (hence the duplicates) |
| **Settings is a Settings window** (App menu › Settings…, ⌘,), not a sidebar row; it hosts the shared Settings page in its own stack (Licenses opens inside) | settings › macOS "Put Settings in the App menu, not a window toolbar"; keyboards › "Command-Comma … Open app settings window" |
| One shell-owned trailing toolbar group: Search, bell (selected player only, unread badge), profile avatar. Pages omit their copies via `\.shellOwnsGlobalToolbar`, because both columns of a split contribute to the one unified toolbar | toolbars › "generally use no more than three groups"; "Trailing: important always-available items … optional search" |
| Page tools stay page toolbar items (Songs Sort/Filter, Leaderboards Rank By, Quick Links, Song Detail Item Shop/Paths); Songs' inline "Filter Songs" `.searchable` sits at the toolbar's trailing end | search-fields › iPadOS and macOS "put search at the trailing side of the toolbar, especially in split views where people search across columns while keeping the selected item visible in detail" |
| Global search stays the Search sheet (⌘K, Edit › Search Festival… ⌘F), not a second toolbar field beside Songs' filter field | search-fields › "Use an inline field when adjacency clarifies that it filters one view rather than searches globally" |
| Window: default 1280×820 pt, minimum 760×540 pt; frame kept with an autosave name; AppKit restoration **off** (`isRestorable = false`) so a crash or forced quit never leads to the "reopen windows" prompt; the last sidebar destination is restored from `fst.mac.destination` | windows › "Make sure windows adapt fluidly to different sizes"; launching › "Restore as much granular prior state as possible on restart" |

## Menu bar (`MacCommands`)

| Menu | Items |
|---|---|
| App | About, **Settings… ⌘,** (system) |
| File | New items removed (one window) |
| Edit | Standard text editing + **Search Festival… ⌘F** |
| View | **Refresh ⌘R** (the frontmost page's own refresh via the shared `RefreshCommandRegistry`, else rebuilds the detail column), **Sort…**, **Filter…** (page-published via `macPageCommands`, disabled when the page has none), Show/Hide Sidebar, toolbar items |
| Go | **Back ⌘[**, every destination (⌘1…⌘n for the n-th visible row; hidden rows disabled, never removed), **Search… ⌘K** |
| Profile | Select/Switch Profile… ⇧⌘P, Deselect Profile, Notifications |
| Window | System (Minimize, Zoom, Bring All to Front) |
| Help | Festival Score Tracker Website, What's New, Licenses |

Basis: the-menu-bar › "Disable, don't hide, unavailable items", "Provide app-specific menus for custom commands", "Provide a Window menu even if your app has only one window"; toolbars › macOS "Every toolbar item must also be a menu-bar command"; keyboards › "Define custom keyboard shortcuts for only the most frequently used app-specific commands" (Sort, Filter and Notifications have none) and "List modifier keys in the correct order". Back with two columns never empties a root list's detail (it would only auto-select again): `MacSidebarPolicy.backPath`.

## Layout at Mac widths

| Rule | Basis |
|---|---|
| **Two populated columns** (`MacListDetailStack`) for Songs, Full Rankings → Player and Rivals lists from 820 pt of content: list 38% within 340–560 pt beside a 1 pt divider, detail ≥ 480 pt. Detail is never empty: last selection, else the **topmost** visible row auto-selects (rows offer their top edge to the shared `ListDetailAutoSelectCollector`); a list with no row after 2.5 s collapses to one column and splits again when its first row appears. One toolbar **Back** (`MacSidebarPolicy.backPath`) serves both columns | split-views › macOS "set reasonable minimum/maximum defaults so the divider stays visible", "Prefer the 1 pt thin divider"; split-views › "Persistently highlight the current selection" (`listDetailSelectable`) |
| Every Mac column publishes its own `DeviceLayout`; width class is **regular from 720 pt** (`MacLayoutPolicy`), so Leaderboards/Compete cards and Profile instrument tiles use two columns and Settings/Licenses use the 680 pt readable width (web detail-card grid: two 420 px columns from 844 px) | layout (foundation); designing-for-macos › "show more content … while keeping information density comfortable" |
| Songs **Sort is a popover** from its toolbar button (no modal chrome; closes on an outside click); **Filter is a sheet** (long form) with grouped form style and a 560×640 pt default (`macSheetFrame`) | popovers › "Limit a popover to a little information or functionality"; popovers › "Use a Close … only for confirmation"; sheets › macOS "Present a sheet in a reasonable default size" |
| Profile, Search, Notifications and What's New are window sheets (Close in the sheet's bottom bar) | sheets › "Display only one sheet at a time" (menu items disable while one is open) |
| Toolbar buttons and sidebar rows carry `.help` tooltips naming their shortcut | pointing-devices › macOS pointer conventions (system hover/selection states on standard controls) |

## Page status (2026-10-02, live SFentonX at 1280×820 and 800×600)

| Page | Mac layout | State |
|---|---|---|
| Songs + Song Detail (history, Intensity, instrument cards) | Two columns, first song auto-selected; Sort popover, Filter sheet; row context menu | Done |
| Song leaderboards, Player History, Paths | Pushed in the detail column (Song Detail links, row context menu) | Shared pages; not separately captured |
| Leaderboards / Compete | Two card columns (Compete: Leaderboards beside Rivals) from 720 pt | Done |
| Full / Band Rankings + pager | Full Rankings: two columns, top-ranked player auto-selected; Band Rankings one column with the floating pager | Done |
| Statistics / Player Profile / Player Bands | Two instrument columns, top-aligned | Done |
| Rivals, All Rivals, Rival Detail, Rivalry | Two columns from the Rivals list | Done (live service was frozen during capture) |
| Suggestions, Item Shop | One centred column ≤ 1400 pt; Shop 4-column art grid ≤ 2170 pt | Done |
| Notifications, Search, Profile, What's New, first-run | Window sheets with Mac default sizes | Done |
| Settings, Licenses | Settings window; Licenses inside it and from Help | Done (one long page, not panes) |
| Bands (`/bands`) | Shared page, reached from search and band rows | Not separately captured |

Evidence: hosted `MacShellHostedTests` (sidebar states, footer Deselect, minimum size, list/detail auto-select/narrow/collapse) and `MacPagesHostedTests` (column width class, Leaderboards two columns, Full Rankings auto-selects rank 1); unit `MacNavigationTests`; live window shots in `~/FestivalShowcase/native-mac/` (never committed).

## Implementation gotchas

- Inside the window's `NavigationSplitView`, a page pushed in a **nested** `NavigationStack` (the split's columns) is presented over both columns (list column) or not at all (detail column). Each split column therefore draws its top route as its root and turns pushes into path writes (`MacListDetailStack.pushes(after:)`); only the one-column arrangement uses real pushes. An `HSplitView` also lost its divider position when a pushed list page split after first layout (detail at zero width), so the columns are an `HStack`; a draggable divider is open.
- Toolbar items attached outside a `NavigationStack` disappear once a page is pushed: the global group is added to every page of the primary column (`MacGlobalToolbar`).
- A lazy list's first `onAppear` is not its first row (Full Rankings auto-selected #6), hence topmost-by-geometry.

## Open gaps

- Context menus on Song/ranking rows, custom hover states on glass rows and keyboard focus traversal of glass cards are not done; `TODO(orchestrator)` decides the row context-menu set (context-menus › "Make every command available in the main interface too").
- Settings is one long page; HIG settings › macOS prefers a toolbar of panes that restores the last pane.
- Song Detail, Player Profile and Suggestions use the full column width (no readable-width cap); Song Detail's instrument cards should follow the web's two-column card grid at regular width.
- Real Liquid Glass appearance and VoiceOver/Full Keyboard Access on the Mac are unverified (Automation Mode needs operator authentication).
