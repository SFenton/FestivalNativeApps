# UIKit port

> **What:** the rules for the UIKit port of the iOS/iPadOS app (`claude/uikit-port`, owner request 2026-10-31: port iOS and iPadOS to Swift logic plus UIKit, UX identical on iPhone, iPad and iPhone Duo, tests updated, performance measured A/B against the SwiftUI app as in Fenton-HASS-Native). **Read when:** writing or reviewing anything under `apple/Sources/FestivalUI/UIKitPort/` or `apple/Apps/iOSUIKit/`.

macOS is sidelined for the port (owner, 2026-10-31): `FestivalDesktop` keeps building from the SwiftUI code, unchanged, and gets no port work.

## Shape

- **One universal app, two front ends.** `FestivalMobile` (SwiftUI, `…native`) was already one universal iPhone + iPad target and is unchanged. `FestivalMobileUIKit` (`…native.uikit`, Home Screen name "FST UIKit") is the same universal app drawn with UIKit and installs beside it. Both run the same `FestivalSession`, `FestivalAPI`, routes, policies, fixtures and launch environment (`FST_*`).
- **Where the code lives.** `apple/Sources/FestivalUI/UIKitPort/<Area>/`, inside `FestivalUI` so the port uses its internal models, routes and policies without making them public. Areas: `Foundation`, `Design` (the `FestivalUI/Design` components), `Common`, `Background`, `App` (root, shell, layout), `Features/<Lane>`, `Diagnostics`.
- **Every file is wrapped in `#if os(iOS)` … `#endif`**: `FestivalUI` also compiles for macOS (`swift build`, `FestivalDesktop`).
- **Every new type is prefixed `UK`** (`UKSongRowCell`, `UKSongsViewController`), so it never collides with the SwiftUI type it ports and a grep finds the whole port.
- **No SwiftUI on screen.** Never `UIHostingController`, `UIHostingConfiguration` or a SwiftUI `View` in the port, and no file under `UIKitPort/` imports SwiftUI. Colours come from `BrandUIColors` (generated beside `BrandTokens` by `tools/generate_tokens.py`). A shared model that exposes a SwiftUI value (`EdgeInsets`, `Color`) gets a UIKit-facing helper outside the port. Swift Charts has no UIKit API: a chart is drawn with Core Graphics / `CAShapeLayer` from the same chart model (`RankHistoryChartModel` …).

## Reuse, never fork

- **Logic is shared.** Models, loaders, policies, formatting, routes (`AppRoute`, `FestivalSection`, `FestivalTabPolicy`, `ShellPresentation`, `DeviceLayout`) and copy are used as they are. When a SwiftUI view computes something inline that the port needs (a label, a colour choice, a state mapping, a load sequence), move it into a `static func` or a small model type in the SwiftUI file's own folder and call it from both, leaving the SwiftUI behaviour unchanged. Never copy-paste logic.
- **Launch.** `FestivalLaunch.resolve()` (`App/FestivalLaunch.swift`) owns the process session and the `FST_DEBUG_*` launch overrides for both roots; `FestivalLaunchResets` the `FST_UI_TEST_RESET_*` resets.
- **Service rules are unchanged** (AGENTS.md, [service-safety.md](../service-safety.md)): the port calls the same `FestivalSession` / `FestivalAPI` methods, never a new endpoint.
- **Identifiers and labels are identical.** Every `accessibilityIdentifier`, label, value, hint and trait the SwiftUI view sets is set on the UIKit view, in the same reading order. The SwiftUI app's XCUITest journeys run unchanged against the port (`FestivalMobileUIKitUITests`, `FestivalMobileUIKitIPadUITests`) and are the parity check.

## Seams (orchestrator-owned)

| File | What |
|---|---|
| `UIKitPort/Foundation/UKContext.swift` | What SwiftUI hands down through `@Environment`: session, navigator, section, shell state, surface. Add a field here rather than a singleton. |
| `UIKitPort/Foundation/UKObservation.swift` | `UKObservation` / `UKObservationBag`: the port's `@Observable` binding. A closure reads observable state and writes it into views; it re-runs once per run-loop turn after anything it read changes. Cells `removeAll()` in `prepareForReuse` and bind again in `configure`. |
| `UIKitPort/Foundation/UKSettings.swift` | `@AppStorage` reads (same `fst.*` keys); observe `UKSettings.didChange` to follow a write. |
| `UIKitPort/App/UKRouteDestination.swift` | `AppRoute` / root section → controller. Lanes fill `Features/<Lane>/UK<Lane>Routes.swift` and never edit the switch. `UIViewController.ukRoute` records each pushed route. |
| `UIKitPort/App/UKRootViewController.swift` | The window root and `UKNavigating`; the Shell lane owns its body. |
| `apple/project.yml`, `tools/ios_sim.py` (`--app uikit`, `--app uikit-ipad`) | Targets, schemes and the simulator tool. |

## Look and motion

- **Same tokens and metrics.** Spacing, radii, colours, row metrics (`LeaderboardRowMetrics` …) and motion durations come from the shared types. Never retype a number that exists as a token or metric.
- **Text.** SwiftUI `.font(.body)` is `UIFont.preferredFont(forTextStyle: .body)` with `adjustsFontForContentSizeCategory = true`; weights and `.monospacedDigit()` through `UIFontDescriptor`. Dynamic Type up to AX5 lays out as the SwiftUI page does (wrap, stack, scroll). Text is white (`FestivalText` rule): `BrandUIColors.textPrimary`.
- **Appearance.** Pages are dark over the shared artwork background (`overrideUserInterfaceStyle = .dark` on the shell).
- **Materials.** Liquid Glass is `UIGlassEffect` in a `UIVisualEffectView` on iOS 26, with the pre-26 fallback the SwiftUI `festivalGlass` uses (blur material plus tint and border); Reduce Transparency and the in-app Less Transparency setting are honoured where the SwiftUI code honours them.
- **Motion.** SwiftUI springs map to `UIView.animate(springDuration:bounce:…)`; eases to `UIViewPropertyAnimator`. Reduce Motion (system and `fst.accessibility.reduceMotion`) is honoured exactly where the SwiftUI code honours it.
- **Layout.** Long lists are `UICollectionView` with a compositional layout and a diffable data source (self-sizing cells, measured at the proposed width); short fixed pages may be a `UIScrollView` with `UIStackView`s. Sheets are `UISheetPresentationController` with the detents and grabber the SwiftUI `.presentationDetents` give.
- **Navigation.** Each section is a `UINavigationController`; the shell is a `UITabBarController` with the Search tab on phones (`ShellPresentation.Navigation.tabs`) and the flyout at regular iPad width (`.flyout`), as `FestivalRootView` decides. Large titles, back buttons, toolbar items and the profile button match the SwiftUI bar. iPhone Duo uses the same `DeviceLayout` poses and hinge columns.

## Tools

| Command | What |
|---|---|
| `python3 tools/ios_sim.py build --app uikit` | Builds the port (both apps share the lane DerivedData). |
| `python3 tools/ios_sim.py shot --app uikit --tab … --route …` | Screenshot of the port; the same command without `--app` shoots the SwiftUI app for comparison. |
| `python3 tools/ios_sim.py uitest --app uikit --only <Class>` | The SwiftUI app's iPhone journeys against the port; `--app uikit-ipad --device ipad` for the iPad journeys. |
| `python3 tools/uikit_perf.py` | A/B frame rate, hitches, main-thread cost, CPU, GPU and memory of both apps on the same surfaces ([testing/apple/uikit-perf.md](../../testing/apple/uikit-perf.md)). |

## Lanes

Each lane works in its own worktree and branch off `claude/uikit-port`, owns the files it creates under its area plus its `UK<Lane>Routes.swift`, and may make the minimal shared-logic extractions described above in the SwiftUI folders it ports (keep the SwiftUI app's behaviour and tests unchanged). The orchestrator merges.

| Lane | Ports | UIKit area |
|---|---|---|
| Design | `Design/`, `Common/` primitives (glass, section header, status, empty and loading states, star rating, instrument icon, marquee, edge fades, modal/sheet chrome) | `UIKitPort/Design`, `UIKitPort/Common` |
| Background | `Background/` (artwork carousel, song backdrop) | `UIKitPort/Background` |
| Shell | `App/Shell`, `App/Layout`, `Features/Search`, `Common/QuickLinks`, `Common/Chrome` (tabs, Search tab, drawer, iPad flyout, profile button, menus, Duo layouts) | `UIKitPort/App` |
| Perf | Measurement probes and the A/B tool | `UIKitPort/Diagnostics`, `FestivalUI/Diagnostics`, `tools/uikit_perf*` |
| Songs | `Features/Songs`, `Shop` | `UIKitPort/Features/Songs` |
| Song Detail | `Features/SongDetail` | `UIKitPort/Features/SongDetail` |
| Leaderboards | `Features/Leaderboards`, `SongLeaderboard` | `UIKitPort/Features/Leaderboards` |
| Profile | `Features/Profile`, `Bands`, `Statistics` | `UIKitPort/Features/Profile` |
| Rivals | `Features/Rivals`, `Compete`, `Suggestions` | `UIKitPort/Features/Rivals` |
| Settings | `Features/Settings`, `FirstRun`, `WhatsNew`, `Notifications` | `UIKitPort/Features/Settings` |

## Shell

Rules for `UIKitPort/App` (Shell lane, 2026-10-31). The shell is `UKRootViewController` (split across `+Layout`, `+Navigation`, `+Chrome`, `+Commands`), one `UKSectionStack` per section, `UKDrawerViewController`, `UKGlobalSearchViewController`, `UKRootChrome`, `UKMenuBar`, `UKWindows`, `UKQuickLinks`.

- **One shell, three layouts.** A `UITabBarController` holds the section stacks plus a trailing `UISearchTab` (`UITab` API, iOS 18+; a classic `viewControllers` fallback before). At regular iPad width (`ShellPresentation.Navigation.flyout`) it is the same controller with `setTabBarHidden(true)` and the drawer as the flyout, so each section stays alive and the responder chain keeps the menu bar working (the SwiftUI shell's reason for the same choice). Compact iPad windows and every phone, iPhone Duo included, keep the tab bar.
- **Layout is published, not read from SwiftUI.** `refreshLayout` builds `LayoutSignals` from the root view (size, size classes, safe area, `traitCollection.verticalBarEdge`, `UIHingeInteraction`, `reservedRegions(kind:)`; iOS 27.1+), applies the `FST_DEBUG_DUO_POSE` / `FST_DEBUG_DUO_WINDOW` overrides, resolves `DeviceLayout` and `ShellPresentation` and writes both into `UKShellState`. Pages read `UIViewController.ukWindowLayout` / `ukLayout` (re-classified by the pane width inside a split). The section set trails a size-class change by a run-loop turn (`ShellPresentation.applying`), the same guard against the 2026-10-04 tab-rebuild crash.
- **The `[AppRoute]` path is the navigation state.** `UKSectionStack.path` is the leading stack's routes plus the trailing pane's; `reshape` lays them out as one pushed stack or, in a landscape regular window with a list page on top, as `OnDemandSplitPolicy.cut` (leading list, trailing detail), moving page controllers between the two navigation controllers instead of rebuilding them. Rows call `navigator.selectDetail(route)` (replaces the open item); `push` appends.
- **Chrome.** Section roots get the drawer button (leading) and the bell and profile (trailing, avatar last) from `UKRootChrome.install`; pages add tools by adopting `UKPageToolsProviding` and calling `ukPageToolsDidChange()`; a pushed page that shows the account group calls `ukInstallAccountItems()`. Identifiers: `fst.shell.drawer.open`, `fst.shell.notifications`, `fst.shell.profile`, `fst.shell.drawer.*`, `fst.split.*`, `fst.global-search.*`, `fst.profile.*`.
- **Drawer.** Display-link driven so the scrim's cut-out follows the panel (`DrawerMotion` is the one source of timing and stage maths). The panel is `UIGlassEffect` with `UICornerConfiguration.containerConcentric` corners on iOS 26 (`UKGlassView(.overlay)` with `concentricMinimumRadius`, so it takes the Reduce Transparency and Increase Contrast fallbacks).
- **Menu bar.** `UKMenuBar.build(with:)` (called from the app delegate's `buildMenu(with:)`) sends `UKShellCommands` selectors down the responder chain; `UKRootViewController.canPerformAction` enables or disables each. Phones get the same shortcuts as `keyCommands`.
- **Refresh and Quick Links.** Refreshable pages register with `UKRefreshCommands.shared`; scrolling pages bind a `QuickLinksController` with `UKQuickLinks` (frames against the visible region below the bars, jump with the corrective re-landing pass).

## Design primitives (Design lane)

Feature lanes build pages from these (`UIKitPort/Design`, `UIKitPort/Common`); see each type's DocC for parameters. `FST_UIKIT_GALLERY=design` (Debug) launches `UKDesignGalleryViewController`, which shows every one in its states, and `UKDesignGalleryJourneyTests` checks it.

| SwiftUI | UIKit | Notes |
|---|---|---|
| `.font(.body.weight(…))`, `FestivalText` | `UKFont.font(_:weight:monospacedDigit:)`, `UKLabel` (white, Dynamic Type) | `UKAccentText.blue` / `.prominentFill` |
| `festivalCard`, `festivalCardCapsule`, group segments | `UKCardView(cornerRadius:segment:capsule:)` | add views to `contentView`, or `embed(_:insets:)` |
| `festivalGlass`, `FestivalGlassGroup` | `UKGlassView(role,…)`, `UKGlassGroupView` | settings from `UKAccessibility`; observe with `UKAccessibilityObserver` |
| `FestivalSectionHeader`, `SectionViewAllLink`, `FestivalGlassSection`, `FestivalFootnote` | `UKSectionHeaderView`, `UKViewAllButton`, `UKGroupSectionView.setRows/setAction`, `UKFootnoteLabel` | |
| `InstrumentIcon`, `StarRating`, `DifficultyMeter` | `UKInstrumentIconView`, `UKInstrumentIconRow`, `UKStarRatingView`, `UKDifficultyMeterView` | spoken labels come from shared statics |
| `InstrumentSelector` | `UKInstrumentSelectorView` (`onSelect`, optional `panel`) | |
| `MarqueeText`, `.marqueeSync()` | `UKMarqueeLabel`, `UKMarqueeSyncGroup` | |
| `FestivalAccordion*`, `FestivalDisclosureGroup` | `UKAccordionView<Value>.follow(_:)`, `UKDisclosureGroupView` | |
| scroll-edge fades | `UKModalTopEdgeFade`, `UKBottomChromeFade`, `UKPinnedHeaderEdgeFade` (mask a non-scrolling container) | |
| `festivalSheet`, `FestivalModal`, `festivalModalPresentation` | `UKSheet.present(_:from:title:closeIdentifier:size:sizing:coverage:)`; pages adopt `UKModalScrollProviding` | |
| `FestivalEmptyState`, `FestivalLoadingView`, `ServiceStatusView/Inline`, `FreshnessDisclosure`, `RefreshErrorBanner` | `UKEmptyStateView`, `UKLoadingView`, `UKServiceStatusView/InlineView`, `UKFreshnessDisclosureView`, `UKRefreshErrorBanner` | fill placements take `hingeProvider` |
| `FestivalReloadGate`, `festivalFadeIn`, `ListJump` | `UKReloadGate`, `UKFadeIn.fadeIn`, `UKListJump.teleport` | |
| `festivalNavigationTitle`, `InstrumentPageTitle`, `SongHeaderText`, `SongBoardLine` | `UIViewController.ukSetPageTitle`, `UKInstrumentPageTitleView`, `UKSongHeaderTextView`, `UKSongBoardLine` | `SongHeaderRow` / `SongBarTitle` need `ArtworkTile` (Background lane) |
| `LeaderboardColumnSlot`, `LeaderboardRowMetrics` | `UKLeaderboardColumnSlot`, `UKLeaderboardRowMetrics` | |
| `HorizontalCarousel` | `UKHorizontalCarouselView` | |
| self-sizing rows | `UKSelfSizingCell`, `UKSelfSizing.fittingHeight(of:width:)` | |

## Profile lane

Rules for `UIKitPort/Features/Profile` (Player profile, Statistics, Player Bands, Bands, Band Detail; 2026-10-31).

- **Shared logic.** Tiles, formatting, link decisions, identity rules and the profile load sequence live in `Features/Profile/PlayerProfileTiles.swift` (`PlayerProfileTiles`, `PlayerProfileLoader`); both front ends call them. `PlayerStatNavigator.follow(_:session:)` is the one link switch.
- **Width is passed down.** UIKit has no custom `Layout`, so width-dependent views conform to `UKWidthDependent` and the page (`UKProfileScrollViewController`) calls `prepare(width:)` before Auto Layout sizes them. `UKProfileColumnGrid` is the stat-grid / two-column / Duo-fold grid.
- **Charts.** `UKRankHistoryChartView` draws the Rank History chart with Core Graphics from `RankHistoryChartScale` / `RankHistoryPaging`; the plot is an accessibility container with one adjustable chart element (Audio Graph through `AXChart`) and three axis elements.
- **Statistics** is `UKPlayerProfileViewController` pointed at the selected player (root or pushed). The Profiles sheet is the Shell lane's `UKProfileSelection`. The dual-source graphs carousel is shelved (`DualSourcePolicy.isEnabled` is false) and not ported.
- **Songs link seam.** A tile that filters Songs saves the preset (`SongsPresetStore`), posts `UKProfileLinks.songsPresetApplied` (instrument in `userInfo`) and selects Songs; the Songs lane may instead set `UKProfileLinks.showSongsHandler`.
- **Service safety.** Calls are exactly the SwiftUI pages': `viewPlayer`, `playerInstrumentRanking`, `playerRankHistory`, `playerBandsPreview`, `playerBands`, `bandProfile`, `bandRankHistory`, `bandSongExtremes`, `catalog`. No band search, band detail by id, stats or sync-status.

## Leaderboards (Leaderboards lane)

Rules for `UIKitPort/Features/Leaderboards` (Leaderboards, Full Rankings incl. combo boards, Band Rankings, Song Leaderboard, Song Band Leaderboard, Score History).

- **One scaffold, one row cell.** Every board is a `UKBoardView`: a `UKReloadGate` around a compositional-layout collection view (head items, rows, tail items) with a bottom chrome stack (the player's footer, then the pager) pinned over the bottom edge, under `UKBottomChromeFade`. Rows are always `UKLeaderboardRowCell`, a segment of its column's group card (`UKCardView` + `FestivalGroupSegment`, hairline above all but the first); the cell hosts one content view chosen by `UKLeaderboardRow.Kind` (`UKRankingRowView`, `UKSongScoreRowView`, `UKSongBandCardView`, `UKScoreHistoryRowView`). Score History sets `separateCards` (each row its own card). Never add a second row cell.
- **Name columns use `ukNameHolder`.** The name marquee sits in a holder with no intrinsic width that takes the row's slack; without it the marquee's inner label (hugging 251) loses to the slots and the songs/value columns stop aligning.
- **Songs-column fit (#38)** is computed from text measurement (`UKRankingRowModels.requiredRowWidth`), not a hidden probe row, and re-run on width, column-count and text-size changes.
- **Song boards** share `UKSongBoardViewController` (song-cover backdrop through `UKBackgroundRegistration(.song)`, scroll-away header, pinned bar title, chrome). The header and bar title come from `UKSongBoardSeam.makeHeader/makePinnedTitle`; the defaults are lane-local stand-ins for `SongHeaderRow` / `SongBarTitle`. When the Song Detail lane's shared header lands, point the seam at it and delete `UKLocalSongHeaderView` / `UKLocalSongBarTitleView`.
- **Paging updates the route**: a board that pages sets `ukRoute` (the shell rebuilds its path from it), the UIKit counterpart of rewriting the last `path` element.
- **Page tools** (Instrument, Rank By, Band Size, Sort, Quick Links) are `UIBarButtonItem`s with menus returned from `ukPageTools`; the band board's switcher also appears in the floating bar's pill except on the Duo vertical bar, where it is a rail item.
- **Gaps**: the Leaderboards "Your Rank History" dual-source pane for iPhone Duo (needs the Profile lane's rank-history page), the Mac-only menu commands, and the multi-row stacked card of a crowded trailing pane on song boards (#364) are not ported.

## Song Detail

Rules for `UIKitPort/Features/SongDetail` (Song Detail lane, 2026-10-31). Entry: `UKSongDetailViewController` (route `.songDetail`).

- **Shape.** One `UIScrollView` with a vertical stack: hero, Intensity, Score History, the instrument cards, the Duos/Trios/Quads previews. A fill spinner shows until the gate (every card's top ten, the selected player's history, the band read, the Shop feed) settles, then the page fades in with `UKFadeIn` stagger. The gate, tools and Quick Links rules are the SwiftUI page's, shared through `SongDetailPlan`, `SongDetailPageTools`, `SongDetailPreloader` and `SongBandPreviewLoader`.
- **Shared extractions (SwiftUI side, behaviour unchanged).** `SongDetailPlan` (charts, path instruments, Quick Links order, card captions), `SongScoreHistoryChartMath` (colour ramp, date and axis labels, spoken rows, score ticks), `SongPathsLoad.swift` (`SongPathsLoadState.fetch`, `SongPathsActivation`). Change a rule there, never in the UIKit copy.
- **Cards.** `UKSongScorePreviewView` adopts the page's preload once and reloads only for a new publication, leeway or Retry. `UKSongDetailCardGridView` is the eager hinge-aware grid (`HingeColumns.spec`); cards are built once, never lazily.
- **Rows are one button.** A score row with a destination is a single accessibility element (label `#2, Name, 99,800, Full combo, accuracy 98%`, hint, button trait), as VoiceOver reads the SwiftUI row. XCUITest cannot query the accuracy text inside it (`previewText` helpers in `SongDetailJourneyTests` find nothing under a UIKit button); assert the row label instead.
- **Score History chart** is Core Graphics (`UKScoreHistoryPlotView`): bars, monotone score line, axes, tap to select the nearest bar, swipe to page. One chart element plus three axis elements, the same labels as the SwiftUI chart.
- **Paths** (`UKSongPathsViewController`) reuses `SongPathsPolicy`, `PathSwitchTransition` and `SongPathsSheet`'s statics; panes load independently and fade through the spinner. Zoom is `UKPathImageScrollView.zoom`, 1x to 3x.
- **Shop action.** `UKSongDetailShopAction.item`: a breathing glyph (Core Animation opacity) in the navigation bar; a still image as a floating tool (floating tools draw bar items from their image); a titled `bag` item in the Duo vertical bar.
- **Debug entry.** `FST_UIKIT_DEBUG_SONGDETAIL=<songId or title>` (Debug only, `UKSongDetailDebug`, called from `UKApp`) pushes the page once the catalogue loads; the Songs lane's `FST_DEBUG_SONG` is separate.
- **Common additions.** `Common/UKScoreRowParts.swift` (`UKAccuracyBadgeView`, `UKSeasonPillView`, `UKPurpleActionButton`, `UKLeaderboardNameView`, `UKSongLeaderboardEntryRowView`) and `Common/UKSongHeaderRow.swift` (`UKSongHeaderRowView`, `UKSongBarTitleView`) are for Song Leaderboard too.
