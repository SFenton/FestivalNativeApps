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
| Unfolded landscape (951×669, regular) | `TabView` stays in the trailing vertical bar, as folded (continuity) | **List/detail** `NavigationSplitView` pages (below); dashboards use 2-column grids | Regular section set: Leaderboards + Rivals replace Compete (web ≥ 600 px). Operator 2026-09-28: only the Duo inner display and iPad get it; large iPhones in landscape keep portrait tabs |
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
- Profile avatar: when `deviceLayout.sectionChrome` is `.verticalBar`, show the symbol `person.crop.circle`/`.fill` titled "Profile: <name>". Keep the monogram avatar in horizontal bars. Bell and profile carry `visibilityPriority(.high)` (iOS 27+), so page actions overflow into `…` first (✅ W1: `RootProfileButton.Presentation`). Capacity measured folded portrait: with a profile (5 tabs) the rail fits only **two** root items plus `…`, so the hamburger lands in `…` as "Menu"; anonymous (3 tabs) shows hamburger, sort, Quick Links, bell and profile. Giving the hamburger `.high` too pushed the profile into `…` instead. TODO(orchestrator): pick hamburger + bell vs bell + profile for the 5-tab rail (the drawer also carries View/Switch/Deselect Profile).
- Page actions that belong in the rail (Player profile "Select Profile"/"Switch To This Profile") add `VerticalBarActionItem` (`App/Shell/RootChrome.swift`): a titled symbol item in its own group right after Back, only while the chrome is a vertical bar; horizontal bars keep the in-content button (in-page design: Lane A2).
- Every toolbar change animates in the rail, so a page must not re-render its toolbar while it is being pushed or popped. Leaderboards › Player › Back (operator bug) was bisected with `drive --record` (`.visual-output/duo-w1/jitter/`): Full Rankings › Back and Settings › Licenses › Back are clean. The popped Player page churned because its Quick Links controller republished as every section left (`report(nil)` → new active section; discovery → empty → `Menu` removed). W1 fixes: `QuickLinksController` ignores teardown (nil frames and zero viewport don't republish; an empty discovery is deferred 0.7 s). Leaderboards no longer reloads all 12 cards when `.task` restarts on reappear. The rail Select item has its own group after Back. **Residual:** an intermittent 2–3 frame dim/collapse of the hamburger and Rank By after some pops (it was ~7 frames, every pop). With a single trailing item on the popped page it was not seen; not yet isolated (W3/W4: re-check on a newer 27.x runtime before more work).
- Also removed in W1 as churn sources: tab roots declare `FestivalRootTrailingItems` synchronously (`festivalRootChrome(providesTrailingItems:)`, per section in `FestivalRootView.rootProvidesTrailingItems`) instead of via the late preference; `OpenProfileAction`/`OpenDrawerAction` are `Equatable`; toolbar `Menu`s bind through comparable bindings (`$storage.keyPath`), never `Binding(get:set:)`.
- Instrument/sort pickers become `Menu`s with a `Label`, not custom capsules.
- Pagination (Full Rankings, band/song leaderboards): with a vertical bar, move First/Previous/Next/Last into `.bottomBar` symbol items with the page label in the overflow title. Otherwise keep the footer, because on iPhone a bottom toolbar collides with the floating tab bar ([iphone.md](iphone.md)).

## Infrastructure

`apple/Sources/FestivalUI/App/Layout/` (Lane W):

| File | Contents |
|---|---|
| `DeviceLayout.swift` | Pure `LayoutSignals` → `DeviceLayout` (`pose`, `orientation`, `widthClass`, `sectionChrome` = `.tabBar` / `.verticalBar(edge)` / `.sidebar`, `contentArrangement` = `.stack` / `.listDetail`, `overlayInsets`, `foldFrame`, `usesRegularSectionSet` = sidebar, or regular width with a non-standard pose) |
| `DeviceLayoutEnvironment.swift` | `\.deviceLayout` (default `.standardPhone`) and `.publishesDeviceLayout(usesSidebarShell:)`: a full-window probe reading size, safe area and (iOS 27.1) `reservedRegions`, `toolbarVerticalEdge` and `onHingeChange` |
| `Tests/FestivalUITests/DeviceLayoutTests.swift` | Every pose, fallbacks without hinge, sidebar precedence, cutout insets |
| `Shell/ShellPresentation.swift` (W1) | Pure `ShellPresentation.resolve(layout:usesSidebarShell:)` → navigation (`.tabs` / `.sidebar`, from the idiom so it never flips on the first geometry pass) + section set; `FestivalShellContent` reads `\.deviceLayout` inside the publisher |
| `Shell/FestivalDrawer.swift` `DrawerPlacement` (W1) | Pure drawer geometry: iPhone keeps its exact original placement; Duo insets the panel by `overlayInsets` and pads the scrim off the vertical bar |
| `Tests/FestivalUITests/ShellPresentationTests.swift` (W1) | Section set per pose (iPhone, large iPhone landscape, 4 folded rotations, inner display, iPad), drawer placement clear of bar/camera in all 4 rotations, profile item per chrome |

`FestivalRootView` already calls `.publishesDeviceLayout(usesSidebarShell: !usesDrawer)`. It is behavior-neutral: nothing reads the value yet. Hosted snapshots can inject `.environment(\.deviceLayout, …)` to render any pose without the device.

## Root integration plan (Lane W1; steps 1, 2, 4, 5 ✅ landed)

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
| B1 | Root chrome, profile selected | ✅ W1. The avatar is a custom-view item, so the system keeps a horizontal top bar just for it (floating beside the "Songs" title) and overflows the bell into `…` |
| B2 | Full Rankings | Instrument/sort capsule is horizontal-only. The custom pagination footer (First/Previous/`1 / 34,770`/Next/Last) takes ≈ 150 of 678 pt, leaving 5 rows visible |
| B3 | Songs, profile selected | 9 instrument chips wrap 5 + 4 in the ≈ 290 pt row width, doubling row height |
| B4 | Songs | ~~The A–Z scrubber (x ≈ 368–392 pt) abuts the vertical bar (from ≈ 396 pt): two adjacent vertical control columns~~ **Fixed 2026-09-28 (Lane S2):** the scrubber now pads its trailing edge by `deviceLayout.overlayInsets.trailing` and no longer stretches to the List's full height (it also chased the large title's collapse, "creeping" up over rows — see [songs-section-index/ios.md](../../controls/songs-section-index/ios.md)). Re-verify the exact clearance once Device Hub can be driven for a fresh folded capture |
| B5 | Drawer (predicted; ✅ W1 `DrawerPlacement`) | A full-height leading overlay. Fine in portrait, but in upside-down and camera-top-left landscape the bar and camera are leading, so it would cover both |
| B6 | Song rows | Accessibility frames span 0–466 pt, under the vertical bar (cards end ≈ 375 pt); audits may flag obscured elements |
| B7 | Shell (from code) | Unfolded Duo is still `.phone` idiom: drawer and one column, so a 951 pt window is wasted. W1: the regular section set now follows the layout (unit-tested); list/detail is W2. Unfolded capture is blocked until Device Hub is unfolded |
| B8 | Tooling | `XCUIDevice` rotation is ignored, so the legacy `testDuoOuterFourRotations` cannot pass as written and should be replaced by Duo journeys. The driver `back` step failed (fixed: taps `BackButton`) |

Working as intended: every tab and toolbar symbol moves into the vertical bar automatically. Back, Quick Links and Paths stack top-down on Song Detail. System bar buttons are 38 × 38 pt; that is a system metric, so do not restyle it.
