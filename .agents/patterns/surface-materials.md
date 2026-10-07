# Surface materials

> **What:** shared policy for translucent content cards, rows and floating controls over artwork. **Read when:** adding or changing a card, row, capsule, sheet fallback or custom glass effect.

Status: **current**, 2026-10-06. Provenance: #291, #312 (R7), #319.

## Intent

Content must remain legible and cheap to scroll over animated artwork. Use one platform-native frosted surface per content role; reserve Liquid Glass and system equivalents for navigation and system chrome.

## Web source (behavior reference)

| Web | Behavior |
|---|---|
| `FortniteFestivalWeb/src/components/common/FrostedCard.tsx` (`FrostedCard`) | Shared frosted content container over the animated backdrop. |
| `FortniteFestivalWeb/src/pages/leaderboards/components/RankingCard.tsx` | Groups ranking rows in a frosted card; row content stays distinct from chrome. |
| `FortniteFestivalWeb/src/pages/player/components/PlayerBandsSection.tsx` (`BandViewAllCard`) | "View all bands (N)" is a full-width frosted card (`frostedCard`, `Layout.entryRowHeight` 48 px), centred semibold label and chevron; not a filled button. |

## Rules

- **R1. Content uses the canonical material surface.** Cards, content rows and non-system floating controls use the shared card/capsule primitive; no feature creates its own frosted, blur, glass or opaque plate stack. A floating control over rows (board pager, A–Z scrubber, switcher pill) wears the same surface as the rows, so it matches them in every accessibility mode.
  - Board pagers (arrow buttons and the page / total badge) float over rows and match them: the same fill, translucency, border and contrast fallback as the row cards, never a pager-only opaque plate or shadow (#319; web `Paginator` spreads `frostedCard`). The Windows board-footer **Your page** buttons, which shared the retired pager plate, moved to the same surface ([agent decision below](#agent-decision-windows-board-footer-your-page-button-319)); none remain since #307 and #318 made each pinned row its own jump. Apple: `RankingsPagerView` draws on `festivalCardCapsule`. Android: `RankingsPager` and `FrostedPagerButton` are `GlassCard`s, which also covers the Rank History and Song History chart pagers. Windows: `LeaderboardsPager` draws each arrow's 40 epx circle and the badge on `FSTCardSurfaceBrush` + `FSTCardStrokeBrush` (a surface `Border` behind a transparent `Button`, like `LeaderboardEntryRow`), so `MainWindow.ApplyTransparency`'s opaque fallback and the contrast-theme brushes reach it as they reach the rows; disabled arrows dim the whole host, surface included, except under a contrast theme, where the host stays fully opaque with its rim (R4) and only the glyph turns GrayText (`Festival.Core/Domain/PagerDimming.cs`, re-applied on a live contrast switch; tests `PagerDimmingTests`, UIA paint journey `tools/windows/journeys/a11y-pager-dim.json` per `--mode`). The bottom-edge fade, not an opaque plate, keeps the pager legible over rows ([scroll-edge](scroll-edge.md)).
- **R2. Apple Liquid Glass is navigation-only.** Content cards and custom controls do not call `glassEffect`; only `Design/GlassSurface.swift` may implement the drawer and Debug A/B glass. HIG Materials: "Don't use Liquid Glass in the content layer."
- **R3. Raw standard material stays in the design layer.** Do not add `.ultraThinMaterial`, `.thinMaterial`, `.regularMaterial` or `.thickMaterial` backgrounds outside `Design/`; the explicit approved variants below retain their contrast and pre-26 behavior.
- **R4. Accessibility replaces translucency.** Reduce Transparency or increased contrast yields an opaque surface with a visible border; text and status information do not rely on the artwork behind them. HIG Accessibility: "If the default does not meet these minimums, provide a higher-contrast scheme when Increase Contrast is on."
- **R5. Preserve the native surface model.** Android `GlassCard` is an M3 `Surface` with a tonal card color and border; Windows cards use `FSTCardSurfaceBrush` rather than per-frame Acrylic. MD3: "Tonal surfaces replace elevation shadows as the primary depth cue."
- **R6. Avoid nesting surfaces.** A group owns one card; its rows, pills, badges and meters use flat fills. System sheets own their own material and must not contain a second glass card.
- **R7. A "View all" call to action takes the web's surface.** Where the web frosts it (player page `BandViewAllCard`), it is a full-width frosted card on the canonical surface: 48 dp/pt/epx minimum height, centred Title Case label and the in-card chevron, one button named by its label. The purple filled leaderboard CTA is an **approved variant** only where the operator chose it over the web's frosted fill (6.29: leaderboard, song, ranking and rivals cards); do not extend it to new View-all rows.
  - Agent decision (#312, 2026-10-06): Android's player-page "View All Bands (N)" is a clickable `GlassCard` (web frosted card), not `ViewFullLeaderboardButton`; owner may override with `/choose`.
  - Windows (#312 review): the profile Bands groups' "View All Bands (N)" is `Controls/ViewAllCard` on its implicit `Themes/Styles.xaml` style (`FSTCardSurfaceBrush`/`FSTCardStrokeBrush`, `FSTViewAllCardMinHeight` 48 epx, card hover/press fills), never `FSTViewAllButtonStyle`; `ViewAllCardTests`, the `windows-profile-purple-view-all` guard and the `profile.py` `bands-section` paint probe (no purple fill, white chevron right of the label) hold it.

## Canonical implementation

| Sub-behavior | Apple | Android | Windows |
|---|---|---|---|
| Content card and row | `FestivalUI/Design/RowCardSurface.swift` `FestivalCardModifier`, `festivalCard`, `festivalRowCard` | `ui/design/DesignPrimitives.kt` `GlassCard` | `Festival.App/Themes/Styles.xaml` `FSTCardSurfaceBrush`; `Controls/SongRowCard.xaml.cs` `SongRowCard` |
| Group and floating capsule | `FestivalUI/Design/GlassSection.swift` `FestivalGlassSection`; `RowCardSurface.swift` `festivalCardCapsule` | `ui/design/DesignPrimitives.kt` `GlassCard` | `Controls/LeaderboardEntryRow.xaml.cs` `LeaderboardEntryRow`; `Controls/LeaderboardsPager.xaml.cs` `LeaderboardsPager`; `Themes/Styles.xaml` `FSTFloatingBackplateBrush` (pinned row only) |
| Glass exception | `FestivalUI/Design/GlassSurface.swift` `FestivalGlassModifier` | Native navigation chrome | Native pane/overlay chrome |
| Frosted View-all card (R7) | — (not yet ported) | `ui/profile/ProfileBands.kt` `ProfileBandsViewAll` (`GlassCard(onClick)` + `RowChevron`) | `Festival.App/Controls/ViewAllCard.cs` `ViewAllCard` (implicit style in `Themes/Styles.xaml`) |
| Purple View-all CTA (approved variant, 6.29) | `Features/Leaderboards/PurpleActionButton.swift` | `ui/design/ViewFullLeaderboardButton.kt` | `Themes/Styles.xaml` `FSTViewAllButtonStyle` |

### Agent decision: Windows notification row cards (#272)

Agent decision (#272, 2026-10-06, owner may override with `/choose`): each Notifications flyout row is the web `NotificationRow` card in exact web content geometry (10 epx radius, 10 epx padding, 1 epx stroke, 8 epx between cards), drawn as an **opaque flat fill** inside the flyout's system material, with Windows theme resources: `Themes/Styles.xaml` `FSTNotificationRowSurfaceBrush` (web `surfaceSubtle` #162133; hover `surfaceElevated`), `FSTNotificationRowStrokeBrush` (web `borderSubtle` #1E2A3A) and, in each contrast theme, `SystemColorWindowColor` with a `SystemColorWindowTextColor` stroke. It's an approved Windows variant of R1/R5 for this one consumer (`Controls/NotificationsBell.xaml` `RowTemplate`/`RowContainerStyle`), not a second card material: no blur or Acrylic, so R6 holds (the flyout owns the only material; its rows are flat fills, like the web dropdown's rows).

| Option | Result | Guidance and precedent |
|---|---|---|
| A. Fluent tokens: `ControlCornerRadius` (4 epx), `CardBackgroundFillColorDefaultBrush` / `CardStrokeColorDefaultBrush`, 12 epx padding | Rounder-cornered translucent white cards; visibly unlike the web and Android rows, and a translucent card over the flyout's Acrylic is a nested material. | winui-code-review checklist (**should**, review item): "Corner radius uses `ControlCornerRadius` / `OverlayCornerRadius` — not hardcoded values"; "Spacing uses 4px grid multiples". winui-design brushes: `CardStrokeColorDefaultBrush` "Border on a content card". |
| **B. Web geometry, flat opaque themed fill (chosen)** | Matches the web `NotificationRow` and Android's row cards (10 dp radius, `#1E2A3A` hairline); contrast themes use system colours only. | Design-ladder precedence: the row is content, not chrome, so the web wins over a native recommendation; no Fluent **must** is broken. winui-design theme-accessibility (**must**): "Only `SystemColor*Brush` resources are allowed inside an HC dictionary" (kept). Android `.agents/controls/notifications/android.md` rows. |
| C. Flat `ListView` rows (no card), the pre-#272 state | Fluent default, but it was the reported #272 defect (no card, stroke or radius). | Rejected by the issue. |

Why B: R6 forbids a second *material*, not a flat fill, and the web's dropdown rows are flat `surfaceSubtle` cards; the Fluent radius and 4 epx grid items are review recommendations that the precedence table ranks below web content geometry, while the binding Fluent rules (themed brushes, system colours in contrast themes, focus rectangle on the item) still hold. `notifications_journey.py` `media-rows` checks the fill, stroke, gap and dot from the window's pixels.

### Agent decision: Windows board-footer Your page button (#319)

Agent decision (#319, 2026-10-06, owner may override with `/choose`). Question: the owner asked that the pager "background, opacity, colors should match row cards", but Windows' **Your page** button (`Controls/LeaderboardsSpotlight.xaml` `Jump` on Full Rankings, since removed by #318 because the pinned row itself jumps per [leaderboard-row](leaderboard-row.md) R7; the `fst.song-leaderboard.spotlight-jump` button in `Pages/LeaderboardsSongPage.xaml`) sat on the same pager-only `FSTPagerButtonBrush` plate (`#FF121826`, `ButtonFace` in contrast themes). Should it keep a footer-specific surface or move with the pager? The web has no equivalent: `LeaderboardPaginationFooter.tsx` renders only `Paginator` and the player footer row, so Your page is a native addition (#307) with no web surface to copy.

| Option | What you'd see | Guidance (strength) | Web / pattern precedent | Trade-offs |
|---|---|---|---|---|
| A. Keep a purpose-specific footer plate (the old `#FF121826` fill, renamed to a footer brush) | The pager circles below it turn translucent like the rows while Your page stays a darker opaque pill, so the footer shows two surfaces. | Fluent Layering (**consider**): "Layering and elevation are powerful visual cues that modernize experiences and help them feel coherent within Windows." winui-design (**should**): "Name resources by purpose … not hue" (a renamed brush would satisfy it). | No web control. R1 (pattern rule): "no feature creates its own frosted, blur, glass or opaque plate stack". | Least visual churn, but keeps a control-specific opaque plate that R1 forbids. It also skips `MainWindow.ApplyTransparency`'s card fallback and keeps a second contrast brush. |
| **B. Row-card surface: `FSTCardSurfaceBrush` / `FSTCardStrokeBrush`, `FSTSecondaryTextBrush` label (chosen)** | Your page, the pager circles, the badge and the rows share one fill, translucency and rim. With transparency off it turns opaque like them, and in contrast themes it's Window/WindowText. | Fluent Layering (**consider**): "The content layer may be on contiguous element, or separated into cards that segment content." winui-design theme-accessibility (**must**): "Only `SystemColor*Brush` resources are allowed inside an HC dictionary" (kept: the card brushes are system colours there). | Apple's jump control is the pinned footer row itself, drawn on the row-card surface (`AccountRankingRow(cardSurface: true)` / `SelectedScoreFooterRow` over `PinnedFooterBacking`; `SelectedRowAction.footer`, [leaderboard-row](leaderboard-row.md) R5). | Lighter than before over bright art. Legibility comes from the bottom-edge fade and R4's opaque fallbacks, as it does for the pager. |
| C. Fluent default `Button` (`ControlFillColorDefaultBrush` + `ControlElevationBorderBrush`) | A near-transparent white-tinted pill with an elevation rim, unlike both the rows and the pager. | winui-design brushes (**consider**, reference table): `ControlFillColorDefaultBrush` "Resting fill for buttons". | None. The app's content controls use the FST card brushes ([design/windows.md](../design/windows.md) Cards). | It's a third surface in the footer, and the fill is too faint over animated art without the card fallback. |

**Chose B.** No platform **must** or owner choice applies and the web has no Your page control, so the precedence table falls to the pattern registry. R1 says non-system floating controls over rows wear the rows' surface, and Apple's native precedent already puts this action on the row card. Option A would only survive as a new opaque plate that R1 forbids.

The change covered every board-footer Your page button: those two, plus the Song Band Leaderboard's `fst.song-band-leaderboard.spotlight-jump` in `Pages/BandsSongLeaderboardPage.xaml` (#306 copied the Solo footer before #319 landed; #326 moved it). They were the only other XAML consumers of the retired `FSTPagerButtonBrush` (the `windows-pager-only-plate` guard keeps it retired). A new board footer copies the card-surface button, never the old plate. The pinned row's `FSTFloatingBackplateBrush` is a backplate under that row's own card surface (#208), not a control surface, so it stays. Since #307 (song and song band boards) and #318 (Full Rankings) no board has a Your page button: each pinned row is the jump-or-open control ([leaderboard-row](leaderboard-row.md) R7); `PagerSurfaceMarkupTests` `SongBoardPinnedRow_IsTheJumpControl` and `FullRankingsPinnedRow_IsItsOwnJumpControl` pin that.

## Known debt

| Debt | Breaks | Plan |
|---|---|---|
| Apple material is measurably darker or more frosted over some bright macOS artwork than the retired glass card. | Exact glass appearance only; legibility and performance are preserved. | Accepted by the owner in #291; retain the fitted material. |

## Guards (`tools/pattern_guard.py`)

- `surface-materials/apple-glass-effect`
- `surface-materials/apple-raw-material-background` — approved allows: `PurpleActionButton`, the pre-26 First Run sheet fallback, and First Run's matching purple demo control.
- `surface-materials/apple-feature-opaque-card` — no feature draws `.background(BrandTokens.cardBackground, in:)`: that opaque plate is `FestivalCardModifier`'s accessibility fallback (#319 removed the pager's private `PagerPlate`).
- `surface-materials/windows-pager-only-plate` — no Windows XAML uses the retired pager-only `FSTPagerButtonBrush` / `FSTPagerBadgeBrush` plates (#319).
- `surface-materials/windows-profile-purple-view-all` — the Windows profile's View All Bands (N) never takes `FSTViewAllButtonStyle` (R7, #312).
