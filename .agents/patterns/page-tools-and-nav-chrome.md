# Page tools and navigation chrome

> **What:** where navigation, global search, page actions, Quick Links, notifications and Profile belong. **Read when:** adding, moving or styling a shell or page action.

Status: **current**, 2026-10-05. Provenance: #52, #72, #84, #92, #160, #271, #300, #309.

## Intent

Navigation preserves location; page tools act on the current content. The web is the behavior reference, while each native shell uses its platform's navigation and command placement rather than reproducing web pixels.

## Web source (behavior reference)

| Web | Behavior |
|---|---|
| `FortniteFestivalWeb/src/components/shell/mobile/BottomNav.tsx` (`BottomNav`, `BOTTOM_NAV_TAB_MIN_HEIGHT`, `SPACIOUS_BOTTOM_NAV_QUERY`) | Top-level destinations retain their selected state and adapt the compact destination set. |
| `FortniteFestivalWeb/src/components/shell/HeaderActions.tsx` (`HeaderActions`) | Search, notifications and profile are separately labelled shell actions. |
| `FortniteFestivalWeb/src/pages/songs/components/SongsToolbar.tsx` (`SongsToolbar`) | Songs has a local query plus distinct Sort and Filter controls. |

## Rules

- **R1. Separate destinations from page actions.** Navigation remains in the platform shell; Sort, Filter, Quick Links and similar tools are supplied by the current page through its canonical shell hook.
- **R2. Follow the Apple placement ADR, not a copied toolbar.** [Navigation accessories](../design/apple/nav-accessories.md) is the detailed, owner-approved Apple ADR (#92, #300): iPhone page tools register with `PageToolsRegistry` for the system tab-bar accessory; Profile remains the trailing header action; global Search is a Search tab; Songs has the inline `Filter Songs` field; Duo and iPad keep tools as trailing bar items. This is an approved deviation from HIG Tab bars, which says to use tabs for navigation and a toolbar for current-view actions; HIG Toolbars says, “Trailing: important always-available items.”
- **R3. Keep the accessory stable.** Apple accessory slots are fixed at 44 pt, page tools remain in page order, the bell stays trailing, and a width/type-size fold is decided from window width rather than the accessory’s live morphing width (#300). HIG Buttons: “the hit region is at least 44x44 pt.”
- **R4. Use the current Android placement.** Global search is a top app bar action (`GlobalSearchEntry`, a full-screen search view on compact windows) on every window size, before notifications then Profile at the trailing end. Compact windows put page tools (Sort, Filter, Quick Links) in the shell’s `FloatingToolbar`; regular windows put them in the top app bar. A page's own list filter (Songs) is a search field pinned inline above the list at every size, never a toolbar item. Material 3’s top-app-bar rule is “Use when: Every screen needs a title and optional actions”; search is “Compact: Full-screen search view”; toolbars display “frequently used actions relevant to current page context”. **Agent decision (#309, 2026-10-05): option C, top app bar search + inline Songs filter + floating toolbar for Sort/Filter/Quick Links (replaces #84's toolbar search pill); owner may override.** It matches Apple's inline filter and bottom page-tools grouping and the web's `SongsToolbar`/`HeaderActions` split, and keeps five bottom destinations. It departs from Apple only by not adding a Search tab, which would push Statistics out of M3's 3–5 destination limit.
- **R5. Use the current Windows placement.** `TitleBar.Content` owns the global `AutoSuggestBox`; page-local Songs search, Sort, Filter and Jump remain in the page actions row. `NavigationView` owns destinations; it has no minimizing bottom-tab accessory (#84).
- **R6. Do not add a parallel command surface.** Pages register Apple tools, register Android shell actions, or use the Windows page-header convention; they do not create a second dock, floating capsule, global-search entry point or custom navigation bar.
- **R7. Android page tools stay reachable while the content scrolls (#52, #160).** Songs and Suggestions pass `FestivalScreen(pinActions = true)`: the compact floating toolbar never hides or minimizes on scroll, Songs' inline filter stays pinned above the list, the top app bar never scrolls, and scrolling back to the top restores the same bounds. Long or endless lists also pass `actionsReadFirst = true`, so TalkBack reads top bar → toolbar → content. On a list pane too narrow for the title, `AdaptiveTopBarActions` moves the page tools behind ⋮; its menu closes once the sheet or menu one of its tools opened has closed (window refocus). Material 3 toolbars: “Displays frequently used actions relevant to current page context”; keeping them pinned instead of hide-on-scroll is the owner's #52 choice. Device evidence: `journeys/PinnedPageControlsDeviceTest` on `FST_Phone` (toolbar) and `FST_Book_Fold --posture half` (⋮).
- **R8. Windows nav-bar and page-tool targets are at least 40x40 epx, and the whole target is clickable (#72, #271).** Each title-bar button (Search, bell, profile) and each page tool (Sort, Filter, Jump, Quick Links, Rank By, the Full/Band Rankings pickers, Song Detail Paths/Item Shop and the pinned Paths) uses `Themes/Styles.xaml` `FSTMinTargetSize`. Icon-only buttons also use it as `MinWidth`. Every new `DropDownButton` uses it too (`HitTargetMarkupTests.EveryDropDownButton_UsesMinTarget`). After any dynamic title-bar change, the shell queues `TitleBar.RecomputeDragRegions()` (`MainWindow.TitleBar.cs` `QueueDragRegionRefresh`). Those changes are: window width, the right header's size (the bell appears), the search box/button swap, and the title cleared at large text. Without the recompute, the stale passthrough rectangles make taps on the new Search control drag the window. Do not use `AutoRefreshDragRegions`: the WinUI spec says it "triggers a visual tree walk on every layout pass". Fluent targeting: "a minimum target size of 40x40 epx". Evidence: `journeys/a11y-hit-targets.json`.

## Canonical implementation

| Sub-behavior | Apple | Android | Windows |
|---|---|---|---|
| Page-tool registry and placement | `apple/Sources/FestivalUI/App/Shell/PageToolsAccessory.swift` `PageToolsRegistry`, `PageToolsAccessoryHost` | `android/app/src/main/java/com/festivalscoretracker/android/ui/common/FloatingToolbar.kt` `FloatingToolbar`, `FloatingToolbarContent` | `windows/Festival.App/Pages/SongsPage.xaml` `Actions` |
| Global search | `apple/Sources/FestivalUI/App/Shell/RootChrome.swift` `FestivalRootTrailingItems` | `android/app/src/main/java/com/festivalscoretracker/android/ui/search/GlobalSearch.kt` `GlobalSearchEntry` | `windows/Festival.App/MainWindow.xaml` `GlobalSearchBox` |
| Current-page filter/actions | `apple/Sources/FestivalUI/Features/Songs/SongsScreen.swift` `festivalPageTool` | `android/app/src/main/java/com/festivalscoretracker/android/ui/shell/FestivalApp.kt` `FloatingToolbar` | `windows/Festival.App/Pages/SongsPage.xaml` `SearchBox`, `SortButton`, `FilterButton` |
| Narrow-pane overflow (⋮) | — | `android/app/src/main/java/com/festivalscoretracker/android/ui/common/TopBarActions.kt` `AdaptiveTopBarActions` | — |
| Hit targets (R8) | — | — | `windows/Festival.App/Themes/Styles.xaml` `FSTMinTargetSize`, `windows/Festival.App/MainWindow.TitleBar.cs` `QueueDragRegionRefresh` |

## Known debt

| Debt | Breaks | Plan |
|---|---|---|
| Placement policy differs by platform: Apple accessory/Search tab/inline filter, Android top-bar search/inline filter/compact floating toolbar (#309), Windows title/page header. | A single cross-platform placement rule is not approved. | Android settled by the #309 agent decision (R4). `TODO(orchestrator): Should Windows retain TitleBar search plus page-header actions, or should a shared placement taxonomy be approved?` |

## Guards (tools/pattern_guard.py)

- `page-tools-and-nav-chrome/apple-tab-accessory`
- `page-tools-and-nav-chrome/android-floating-toolbar`
- `page-tools-and-nav-chrome/windows-titlebar-content`
- Windows hit targets: `windows/Festival.Core.Tests/HitTargetMarkupTests.cs` (markup) and `tools/windows/journeys/a11y-hit-targets.json` (UIA sizes, off-glyph caption checks, overlap)
