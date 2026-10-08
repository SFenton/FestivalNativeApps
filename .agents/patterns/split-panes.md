# Split panes

> **What:** the boundary between the two panes of a list/detail split: the band between them, whether it draws a line, and the one backdrop running across it. **Read when:** changing a split's divider, band, backdrop or pane margins on any platform, or adding a list/detail split.

Status: **current**, 2026-10-08. Provenance: #344 (split from #332; agent decision); owner rule #361 (where the band sits on iPhone Duo); owner-approved Settings variant #371 (R6). Layout, geometry and page classification: [split-view.md](../design/apple/split-view.md) (Apple).

## Intent

A split reads as one page that opened an item beside itself, not as two windows. The panes are separated by space (the band and each pane's full-page margins; on a foldable, the fold), never by a drawn splitter, and the page's one backdrop and top darkening run unbroken across the band.

## Web source (behavior reference)

None: the web app has no list/detail split. This is a native layout pattern decided under the design ladder (decision below).

## Rules

1. **R1. No drawn divider.** The band between the panes draws no line, rule or splitter handle. Its width separates the panes: the fold/hinge on a partially folded foldable (Apple `OnDemandSplitPolicy.Geometry.isHinge`; R5), else a 1 pt band at the midpoint plus each pane's full-page margins (20 pt a side on iPad). Owner (#332): "Split View should not have visible vertical splitter component". HIG Layout: "Group related information/functions using negative space, containers, or separators" (should).
2. **R2. Increase Contrast restores a hairline at a midpoint only.** With the system's Increase Contrast on, a midpoint band draws a 1 pt hairline (Apple `Color.white.opacity(0.16)`); a hinge never does, the fold divides the panes. HIG Accessibility: "provide a higher-contrast scheme when Increase Contrast is on" (should).
3. **R3. One backdrop across the band.** The band is clear over the split's single backdrop and carries the panes' top-edge gradient, so image and darkening are continuous from pane to pane (split-view.md "One background, full-page insets").
4. **R4. One component per platform.** Every split draws its band through the canonical layout below; a page never adds its own divider between panes.
5. **R5. The band is on the hinge only in book pose (owner-approved, #361, 2026-10-07).** Owner: "When completely unfolded, midpoint should still be midpoint of free space, not hinge. When partially folded, midpoint should be hinge. This is an override from me, app-wide." In book pose (Apple `pose == .partiallyFolded`, `DeviceLayout.splitHinge`; Android a separating `FoldingFeature`) the panes meet at the fold. Fully unfolded (flat) the split is laid out as on any window of that size, never on a flat hinge line: Apple's on-demand split divides at the midpoint of its free space, the part of its container inside the window's safe area (`DeviceLayout.freeSpan`, the vertical bar excluded; `OnDemandSplitPolicy.freeMidX`), so the two panes' content is equal and the bar stays inside the trailing pane; it is a midpoint band, so R2's Increase Contrast hairline applies. Android uses its ordinary list-detail widths, from the free content area. Folding or unfolding re-places the band and reflows the same panes in place, without a reload or a black screen (#346, Apple `OnDemandSplitPolicy.defersWindowChange`). [hinge-columns](hinge-columns.md) R7 is the shared rule. Supersedes split-view.md's flat hinge divider. HIG Designing for iPhone Duo: "Folding region | Present when partially open"; Material 3 foldable postures: "Flat (unfolded): Treat as Medium or Expanded window class based on width"; "Half-opened (book): Split content at the hinge — list on one side, detail on the other".
6. **R6. Owner-approved variant: Settings is always split, with a placeholder (#371, 2026-10-08; iPad and iPhone Duo inner landscape only).** Every other list page starts full width and opens its trailing pane on demand. Wherever Settings can split, it keeps the trailing pane open. With nothing selected, that pane shows a vertically centred placeholder: the Settings icon (`gearshape`), "Settings", then "Select a setting to see more options here". The placeholder uses the shared empty state (`FestivalEmptyState`, [empty-error-states](empty-error-states.md)) and has no Close button. The list keeps the full page's order, and its plain toggles and buttons act in place without changing the right pane: Show Instrument Icons, Enable Independent Song Row Visual Order, Filter Invalid Scores with its leeway slider (one value tied to its toggle), Experimental Ranks, Report an Issue, Request a Feature, Diagnostics (Debug) and Reset.

   Every group with more options is a chevron row, styled like the Licenses link, that opens on the right, highlighted while open. Selecting another row replaces the open one, and Close returns to the placeholder. The chevron groups are:

   - Song Row Visual Order (while Independent Visual Order is on)
   - CHOpt Paths (default view and the draggable column order)
   - Accessibility
   - Item Shop
   - Show Instruments
   - Show Instrument Metadata
   - Version
   - Service Info
   - First Run Guides
   - Licenses
   - Privacy Policy (shown inline; a sheet everywhere else)

   A topic page reuses the full page's rows, keys and identifiers. Its card is untitled because the pane's title names the topic, and the description sits above the card. Quick Links stay on the list.

   This variant does not apply to iPhone, a folded Duo, portrait, compact tiles or the Mac Settings window: they keep the single page, or the Mac's toolbar panes. Owner: "Settings should align to left and right side should have vertical centered {Settings Icon} under that "Settings" under that "Select a setting to see more options here" … Toggles don't do anything on right side and stay left side only … iPhone layout stays the same".

   HIG Split views: "Persistently highlight the current selection in each pane leading to a detail view" (should). iOS: "Prefer split views in a regular environment" (should). HIG Lists and tables: "for drill-down, use a disclosure indicator" (should). HIG Settings (macOS): "Choosing Settings from the App menu opens a window, typically a toolbar of related panes" (kept). Implemented by `OnDemandSplitPolicy.ListPage.placeholder` and `trailingContent(cut:allowsSplit:)`, `OnDemandSplitStack.placeholderPane`, `SettingsTopic` and `SettingsScreen(topic:)`. It replaces [wide-columns](wide-columns.md) R7 on iPad and the Duo. Tests: `OnDemandSplitPolicyTests.settingsAcceptsTopicsBesideItsList`, `onlySettingsShowsAPlaceholder`, `trailingContentFollowsSelectionAndPlaceholder`, `SettingsTopicTests`, `IPadShellAccessibilityTests.testSplitReadingOrderSelectionAndFocus` (`settings`, `settings-licenses`) and `IPadAccessibilityAuditTests` `settings-topic-split`.

Agent decision (#344, 2026-10-07; owner may override with `/choose`): options were (A) no line on the Duo only, keeping the 1 pt hairline on iPad and Mac per HIG Split views macOS "Prefer the 1 pt thin divider" (prefer); (B) no line on any split; (C) B plus the hairline under Increase Contrast at a midpoint. Chose **C**: the owner's words name no platform and an owner choice outranks a platform *prefer*; the macOS clause picks a style for *draggable* dividers, and this split is fixed at the midpoint; Increase Contrast keeps an accessible boundary for people who ask for one. Supersedes: split-view.md "Prefer the 1 pt thin divider (kept)".

## Canonical implementation

| Sub-behavior | Apple | Android | Windows |
|---|---|---|---|
| Line rule (R1, R2) | `apple/Sources/FestivalUI/App/Layout/OnDemandSplitPolicy.swift` `OnDemandSplitPolicy.drawsDividerLine` | — (see debt) | — (no split) |
| Band and backdrop (R3, R4) | `apple/Sources/FestivalUI/App/Layout/OnDemandSplit.swift` `OnDemandSplitLayout` (private `SplitDivider`, `SplitBackdrop`); `SplitPaneChrome.swift` `SplitPaneChrome` | — | — |
| Settings placeholder and topics (R6) | `apple/Sources/FestivalUI/App/Layout/OnDemandSplitPolicy.swift` `ListPage.placeholder`, `trailingContent(cut:allowsSplit:)`; `apple/Sources/FestivalUI/App/Layout/OnDemandSplit.swift` `OnDemandSplitStack` (`placeholderPane`); `apple/Sources/FestivalUI/Features/Settings/SettingsTopic.swift` `SettingsTopic`; `apple/Sources/FestivalUI/Features/Settings/SettingsScreen.swift` (`listPage`, `topicContent`) | — (deferred; out of #371's Apple scope) | — (deferred) |
| Fold position (R5) | `apple/Sources/FestivalUI/App/Layout/OnDemandSplitPolicy.swift` `OnDemandSplitPolicy` (`DeviceLayout.splitHinge` in book pose, `freeMidX` flat) | `android/app/src/main/java/com/festivalscoretracker/android/ui/shell/FestivalApp.kt` separating `verticalHinge` with `android/app/src/main/java/com/festivalscoretracker/android/core/nav/FestivalSection.kt` `listPaneWidth`; `android/app/src/main/java/com/festivalscoretracker/android/ui/settings/HingeSplit.kt` `rememberHingeSplit`; `android/app/src/main/java/com/festivalscoretracker/android/core/bands/BandLayout.kt` `BandLayout.panes` (Band Detail) | — (no foldable) |

Apple consumers: `OnDemandSplitStack` (iPad, iPhone Duo inner landscape) and `MacListDetailStack` (Mac content area): Rivals, All Rivals, Compete (its rival rows → Rival Detail, #369), Leaderboards (Full/Band Rankings in the trailing pane; profiles cover both panes as full pages, #352), Song Detail (full leaderboard, score history), Settings (every topic and Licenses beside the list, a placeholder while none is open; R6, #371). Tests: `OnDemandSplitPolicyTests.dividerLineOnlyUnderIncreaseContrastAtAMidpoint`, `duoSplitsAtTheFreeSpaceMidpointFlatAndTheHingeInBookPose`; Compete fixture journeys `IPadShellJourneyTests.testCompeteRivalOpensBesideCompete` / `testCompeteRivalPushesFullPageWithoutSplit` and the iPhone push path `RivalsJourneyTests.testCompeteRivalRowPushesFullPageOnPhone` (#369); `MacAccessibilityTreeTests` (the band is never an accessibility element).

## Known debt

| Debt | Breaks | Plan |
|---|---|---|
| Android Songs list/detail (`android/app/src/main/java/com/festivalscoretracker/android/ui/shell/FestivalApp.kt`) draws a `VerticalDivider(color = BrandTokens.glassBorder)` between the panes | R1, R2 | Android check (out of #344's Apple scope) |

## Guards (`tools/pattern_guard.py`)

- `split-panes/android-vertical-divider`
