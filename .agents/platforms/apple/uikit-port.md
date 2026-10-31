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
| Songs | `Features/Songs`, `SongDetail`, `Shop` | `UIKitPort/Features/Songs` |
| Leaderboards | `Features/Leaderboards`, `SongLeaderboard` | `UIKitPort/Features/Leaderboards` |
| Profile | `Features/Profile`, `Bands`, `Statistics` | `UIKitPort/Features/Profile` |
| Rivals | `Features/Rivals`, `Compete`, `Suggestions` | `UIKitPort/Features/Rivals` |
| Settings | `Features/Settings`, `FirstRun`, `WhatsNew`, `Notifications` | `UIKitPort/Features/Settings` |

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
