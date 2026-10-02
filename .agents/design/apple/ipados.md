# iPadOS design

> **What:** iPad shell, sidebar, list/detail, grids, keyboard and pointer decisions, each with the HIG file it follows (`apple-hig` skill, `~/.claude/skills/apple-hig/references/hig/`). **Read when:** building or changing any iPad layout.

The iPadOS app is its own target, **FestivalTablet** (`com.sfenton.festivalscoretracker.ipad`, all orientations, no `UIRequiresFullScreen`); the App Store iPhone app stays iPhone-only and portrait-locked ([build-and-run](../../platforms/apple/build-and-run.md)). Both share `FestivalUI`, so every iPad decision below is a size-class or `sectionChrome == .sidebar` branch that leaves iPhone unchanged.

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

- **Three panes**: Songs, Leaderboards › Full Rankings and Rivals show sidebar | list | detail. `ListDetailStack` nests its `NavigationSplitView` in the root split's detail column (iPadOS 26.5: the inner list floats as its own glass column with its own toolbar and hide button). An `HStack` of two `NavigationStack`s was rejected: both toolbars and the Filter Songs field merged into one bar. HIG split-views.md iPadOS "two vertical panes (Mail) or three (Keynote)".
- **When**: `ListDetailPolicy.usesSplit` for `sectionChrome == .sidebar` measures the section's own container (≥ 760 pt), so hiding the sidebar, rotating or resizing a window reflows live (HIG windows.md "Make sure windows adapt fluidly to different sizes"; multitasking.md "adapt to every window size").
- **Never empty**: the detail restores the last selection, else auto-selects the **top-most** row on screen (rows offer route + `minY`, `ListDetailAutoSelectCollector` picks the smallest after 120 ms; lazy lists call `onAppear` out of order). Selected rows keep the accent highlight (split-views.md "Persistently highlight").
- Shop stays a grid that pushes Song Detail (a grid beside a detail column would leave two cramped columns).

## Grids and sheets

| Page | iPad behavior | HIG |
|---|---|---|
| Shop | Adaptive art grid (`.adaptive(minimum: 210)`), List/Grid toggle; list at accessibility sizes | collections.md "Prefer the familiar standard horizontal row or grid" |
| Leaderboards, Profile/Statistics instrument cards | Two flexible columns at regular width | layout.md (adapt to size classes) |
| Song Detail instrument cards | `.adaptive(minimum: 360)`: two columns when the page is ≥ ~730 pt (full-width detail); one in a list/detail detail column | collections.md "make dynamic layout changes sensible and easy to track" |
| Sheets | `festivalSheet` applies `presentationSizing(.form)` (or `.page`) at regular width, centered; compact windows get the phone sheets | sheets.md "Prefer page or form sheet styles in an iPadOS app" |
| Popovers | Not used for page content; menus (Quick Links, metric pickers) are system menus | popovers.md "Avoid popovers in compact views" |

## Keyboard and pointer

| Shortcut | Action | Note |
|---|---|---|
| ⌘F, ⌘K | Global search | keyboards.md: Command-F "Open Find window" |
| ⌘1…⌘9 | Visible destinations in sidebar order (tab order when compact); the current one pops to its root | `SidebarMenu.destination(forDigit:in:)` |
| ⌘[ | Back in the frontmost column (`ListDetailPolicy.pathAfterBack`) | Repurposes the standard Command-[ "Left-align selection": the app has no text editing (keyboards.md "Only consider it when the standard action doesn't make sense") |
| ⌘R | Refresh the frontmost refreshable page (`RefreshCommandRegistry`, `festivalRefreshable`) | Songs, Leaderboards, Suggestions, Band Detail |

Shortcuts are invisible `KeyCommandButton`s titled for the ⌘-hold overlay. Pointer: list/detail rows use the highlight effect on their rounded card shape (no scale: rows sit edge to edge), sidebar footer buttons the highlight effect, system bar buttons their defaults (pointing-devices.md "highlight for small elements ... hover for large ones"; "reserve scaling for elements that can grow without crowding neighbors (not table rows)").

## Open

- Multiple windows (`UIApplicationSupportsMultipleScenes` is false) and "Open in New Window" (windows.md "Consider offering a context-menu ... command to view content in a new window").
- iPadOS menu-bar `commands` (Go/View menus) instead of hidden shortcut buttons; Full Keyboard Access audit.
- Per-column size classes: Profile/Leaderboards pick two columns from the window's size class, so a narrow list/detail detail column can still show two.
- Never fix row counts or hardcode device sizes: chips wrap (5 + 4 where the web tablet shows 9 in one row) as the detail width changes.
- A Form in a centered sheet may need scrolling to expose Reset above a pinned footer.
- Always exercise Hide Sidebar with a detail visible: badge padding once caused a main-thread layout loop there.
