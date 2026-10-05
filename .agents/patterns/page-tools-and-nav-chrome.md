# Page tools and navigation chrome

> **What:** where navigation, global search, page actions, Quick Links, notifications and Profile belong. **Read when:** adding, moving or styling a shell or page action.

Status: **current**, 2026-10-05. Provenance: #84, #92, #300.

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
- **R4. Use the current Android placement.** Compact windows put page actions and global search in the shell’s `FloatingToolbar`; regular windows use the top app bar, with notifications then Profile at the trailing end. Material 3’s top-app-bar rule is “Use when: Every screen needs a title and optional actions”; the floating toolbar is the approved compact variant from #84.
- **R5. Use the current Windows placement.** `TitleBar.Content` owns the global `AutoSuggestBox`; page-local Songs search, Sort, Filter and Jump remain in the page actions row. `NavigationView` owns destinations; it has no minimizing bottom-tab accessory (#84).
- **R6. Do not add a parallel command surface.** Pages register Apple tools, register Android shell actions, or use the Windows page-header convention; they do not create a second dock, floating capsule, global-search entry point or custom navigation bar.

## Canonical implementation

| Sub-behavior | Apple | Android | Windows |
|---|---|---|---|
| Page-tool registry and placement | `apple/Sources/FestivalUI/App/Shell/PageToolsAccessory.swift` `PageToolsRegistry`, `PageToolsAccessoryHost` | `android/app/src/main/java/com/festivalscoretracker/android/ui/common/FloatingToolbar.kt` `FloatingToolbar`, `FloatingToolbarContent` | `windows/Festival.App/Pages/SongsPage.xaml` `Actions` |
| Global search | `apple/Sources/FestivalUI/App/Shell/RootChrome.swift` `FestivalRootTrailingItems` | `android/app/src/main/java/com/festivalscoretracker/android/ui/search/GlobalSearch.kt` `GlobalSearchEntry` | `windows/Festival.App/MainWindow.xaml` `GlobalSearchBox` |
| Current-page filter/actions | `apple/Sources/FestivalUI/Features/Songs/SongsScreen.swift` `festivalPageTool` | `android/app/src/main/java/com/festivalscoretracker/android/ui/shell/FestivalApp.kt` `FloatingToolbar` | `windows/Festival.App/Pages/SongsPage.xaml` `SearchBox`, `SortButton`, `FilterButton` |

## Known debt

| Debt | Breaks | Plan |
|---|---|---|
| Placement policy differs by platform: Apple accessory/Search tab/inline filter, Android compact floating toolbar, Windows title/page header. | A single cross-platform placement rule is not approved. | `TODO(orchestrator): Should Android Songs retain the #84 floating-toolbar search/actions rather than converge on the Apple Search-tab plus inline-filter model?` `TODO(orchestrator): Should Windows retain TitleBar search plus page-header actions, or should a shared placement taxonomy be approved?` |

## Guards (tools/pattern_guard.py)

- `page-tools-and-nav-chrome/apple-tab-accessory`
- `page-tools-and-nav-chrome/android-floating-toolbar`
- `page-tools-and-nav-chrome/windows-titlebar-content`
