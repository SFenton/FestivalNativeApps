# iPhone Duo design

> **What:** the per-pose layout decisions for iPhone Duo, which pages get list/detail, the `App/Layout` infrastructure, the root integration plan and the baseline breakages. **Read when:** building or reviewing any Duo layout. Runtime facts, APIs and simulator controls: [platforms/apple/duo.md](../../platforms/apple/duo.md).

## Principles (Apple HIG first, Fluent second)

1. **Size classes, safe areas and reserved regions only.** Compact = outer display, regular = inner display. No device names, fixed widths, `userInterfaceIdiom` or pixel detectors; never port the web's `probableDuoDisplay` heuristic.
2. **Keep the system vertical bar.** Standard `TabView`/`NavigationStack`/`.toolbar` get it for free. Never hand-build a rail or tab lane, and never `toolbarVerticalBehavior(.disabled)`: HIG says "don't override the default bar placement". The web's 3-tab Duo landscape rail (`FortniteFestivalWeb/src/components/shell/mobile/BottomNav.tsx:72-83`) was a browser workaround. Natively, the system's automatic compression keeps the tab bar and overflows toolbar items.
3. **One hierarchy on both displays.** Folded shows one level; unfolded adds a level (list + detail), like Mail. Same tabs, same toolbar actions, same state across fold and unfold. This matches Fluent's dual-screen *list-detail* pattern, with one pane per side of the fold.
4. **Custom overlays avoid reserved regions.** The drawer, scrubbers, pinned footers and banners inset by `DeviceLayout.overlayInsets` (camera occlusion plus safe area) and stay out of `foldFrame`.

## Decisions per pose

| Pose (window) | Section chrome | Pages | Notes |
|---|---|---|---|
| Folded portrait (466×678, compact) | `TabView`, placed by the system in the trailing vertical bar | iPhone layouts, one column, push navigation | Drawer stays (leading). Compact section set (Compete) |
| Folded landscape, either rotation (678×466, compact) | Same, on the camera's edge; the tab bar kept, toolbar items overflow (`.automatic` compression) | One column, wider rows. No custom 3-tab trim | Short height: pinned footers become toolbar items (see Leaderboards) |
| Folded upside down (466×678, bar leading) | Vertical bar on leading edge | As portrait | Drawer must start after `overlayInsets.leading`; camera bottom-left |
| Unfolded landscape (951×669, regular) | `TabView` stays in the trailing vertical bar, as folded (continuity) | **List/detail** `NavigationSplitView` pages (below); dashboards use 2-column grids | Regular section set: Leaderboards + Rivals replace Compete (web ≥ 600 px) |
| Unfolded portrait (669×951, regular) | System horizontal tab bar | List/detail. The system may overlay the list column in portrait; accept it | Horizontal bars allowed by HIG here |
| Partially folded (inner, active division) | As unfolded | `NavigationSplitView` equalises columns at the fold itself; custom grids use an even column count; nothing interactive in `foldFrame` | Laptop pose (horizontal fold): no custom arrangement; system containers adapt |

Why `TabView` rather than a sections sidebar when unfolded: HIG asks that controls keep their relative positions across poses, and the inner display keeps the vertical bar in landscape exactly where the folded tabs were. A permanent sections sidebar would spend a column on navigation instead of content. The iPad sidebar shell is unchanged until the iPadOS phase.

## List/detail pages (regular width)

| Section | List column (horizontal bar: search/sort/filter) | Detail column (vertical bar on Duo) | Deeper pushes |
|---|---|---|---|
| Songs | Songs list | Song Detail (`.songDetail`) | Song leaderboard, Player History, Paths stay in the detail stack |
| Leaderboards | Full Rankings (`.fullRankings`) | Player profile (`.player`) | Player Bands |
| Rivals | Rivals hub / All Rivals (`.allRivals`) | Rival Detail (`.rivalDetail`) | Rivalry |
| Compete, Statistics, Suggestions, Settings, Shop, Bands | — (single page) | — | Use the width: 2-column section grids, adaptive Shop grid, readable-width Settings |

- The selected row is the detail's root route, taken from the same per-section `AppRoute` path. Folding keeps the path, so the detail is simply pushed on the compact stack, and unfolding lifts the first detail route into the column. With nothing selected the detail column shows a quiet "Select a song" style placeholder over the shared background (no auto-selection).
- Controls stay with the pane they affect (HIG, Mail example). List actions go in the list column's bar; detail actions (Quick Links, Paths) go in the detail's vertical bar.

## Toolbar rules (all Duo poses)

- Every toolbar item is a `Label(title, systemImage:)`: vertical placement needs the icon and overflow needs the title. Custom-view items stay horizontal and force a top bar, so avoid them.
- Profile avatar: when `deviceLayout.sectionChrome` is `.verticalBar`, show the symbol `person.crop.circle`/`.fill` titled "Profile: <name>". Keep the monogram avatar in horizontal bars. Give the bell `visibilityPriority(.high)`: it carries an unread badge.
- Instrument/sort pickers become `Menu`s with a `Label`, not custom capsules.
- Pagination (Full Rankings, band/song leaderboards): with a vertical bar, move First/Previous/Next/Last into `.bottomBar` symbol items with the page label in the overflow title. Otherwise keep the footer, because on iPhone a bottom toolbar collides with the floating tab bar ([iphone.md](iphone.md)).

## Infrastructure

`apple/Sources/FestivalUI/App/Layout/` (Lane W):

| File | Contents |
|---|---|
| `DeviceLayout.swift` | Pure `LayoutSignals` → `DeviceLayout` (`pose`, `orientation`, `widthClass`, `sectionChrome` = `.tabBar` / `.verticalBar(edge)` / `.sidebar`, `contentArrangement` = `.stack` / `.listDetail`, `overlayInsets`, `foldFrame`, `usesRegularSectionSet`) |
| `DeviceLayoutEnvironment.swift` | `\.deviceLayout` (default `.standardPhone`) and `.publishesDeviceLayout(usesSidebarShell:)`: a full-window probe reading size, safe area and (iOS 27.1) `reservedRegions`, `toolbarVerticalEdge` and `onHingeChange` |
| `Tests/FestivalUITests/DeviceLayoutTests.swift` | Every pose, fallbacks without hinge, sidebar precedence, cutout insets |

`FestivalRootView` already calls `.publishesDeviceLayout(usesSidebarShell: !usesDrawer)`. It is behavior-neutral: nothing reads the value yet. Hosted snapshots can inject `.environment(\.deviceLayout, …)` to render any pose without the device.

## Root integration plan (Lane W1; after the UX-test lanes finish)

Exact edits, in order, to `App/FestivalRootView.swift` unless noted:

1. Move the body's `ZStack` contents into a new `FestivalShellContent` view (same file) so it can read `@Environment(\.deviceLayout)`. Keep `.publishesDeviceLayout` on the outer view.
2. `visibleSections`: `regularWidth: !usesDrawer || layout.usesRegularSectionSet`, with the regular set gated to `layout.pose != .standard` so iPhone landscape keeps today's tabs. TODO(orchestrator): decide whether large iPhones in landscape (regular width) should adopt the web ≥ 600 px split too. `init`'s initial resolution is unchanged; the existing `onChange(of: visibleSections)` + `FestivalTabPolicy.resolve` already swaps Compete ↔ Leaderboards on fold/unfold.
3. `content(for:)`: for `.songs`, `.leaderboards` and `.rivals`, when `layout.contentArrangement == .listDetail`, wrap the root in a new `App/Layout/ListDetailStack.swift` (`NavigationSplitView` with the list root as `sidebar`, a `NavigationStack` rooted at the first detail route of `paths[section]` as `detail`). Put the path split in a pure, unit-tested `ListDetailPolicy.split(section:path:)` → `(list: [AppRoute], detail: [AppRoute])`. `SongNavigationRoot` needs a `listDetail` flag (Lane S file; W2 edits with ownership handed over).
4. `FestivalDrawer` (`Shell/FestivalDrawer.swift`): pad the panel by `layout.overlayInsets` (leading/top/bottom) and never cover `.verticalBar(.leading)`. Start the panel after the bar, and keep its scrim off the bar.
5. `Shell/RootChrome.swift`: profile/bell vertical representation and priorities (toolbar rules above).
6. Do not touch `tabs`/`TabView` construction: the system vertical bar needs nothing from us.

## Baseline breakages (folded, 2026-09-28)

| # | Where | Observed |
|---|---|---|
| B1 | Root chrome, profile selected | The avatar is a custom-view item, so the system keeps a horizontal top bar just for it (floating beside the "Songs" title) and overflows the bell into `…` |
| B2 | Full Rankings | Instrument/sort capsule is horizontal-only. The custom pagination footer (First/Previous/`1 / 34,770`/Next/Last) takes ≈ 150 of 678 pt, leaving 5 rows visible |
| B3 | Songs, profile selected | 9 instrument chips wrap 5 + 4 in the ≈ 290 pt row width, doubling row height |
| B4 | Songs | The A–Z scrubber (x ≈ 368–392 pt) abuts the vertical bar (from ≈ 396 pt): two adjacent vertical control columns |
| B5 | Drawer (predicted) | A full-height leading overlay. Fine in portrait, but in upside-down and camera-top-left landscape the bar and camera are leading, so it would cover both |
| B6 | Song rows | Accessibility frames span 0–466 pt, under the vertical bar (cards end ≈ 375 pt); audits may flag obscured elements |
| B7 | Shell (from code) | Unfolded Duo is still `.phone` idiom: compact section set, drawer, one column, so a 951 pt window is wasted. Unfolded capture is blocked until Device Hub is unfolded |
| B8 | Tooling | `XCUIDevice` rotation is ignored, so the legacy `testDuoOuterFourRotations` cannot pass as written and should be replaced by Duo journeys. The driver `back` step failed (fixed: taps `BackButton`) |

Working as intended: every tab and toolbar symbol moves into the vertical bar automatically. Back, Quick Links and Paths stack top-down on Song Detail. System bar buttons are 38 × 38 pt; that is a system metric, so do not restyle it.
