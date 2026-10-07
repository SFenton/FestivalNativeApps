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
  - Board pagers (arrow buttons and the page / total badge) float over rows and match them: the same fill, translucency, border and contrast fallback as the row cards, never a pager-only opaque plate or shadow (#319; web `Paginator` spreads `frostedCard`). Apple: `RankingsPagerView` draws on `festivalCardCapsule`. Android: `RankingsPager` and `FrostedPagerButton` are `GlassCard`s, which also covers the Rank History and Song History chart pagers. Windows: `LeaderboardsPager` draws each arrow's 40 epx circle and the badge on `FSTCardSurfaceBrush` + `FSTCardStrokeBrush` (a surface `Border` behind a transparent `Button`, like `LeaderboardEntryRow`), so `MainWindow.ApplyTransparency`'s opaque fallback and the contrast-theme brushes reach it as they reach the rows; disabled arrows dim the whole host, surface included. The bottom-edge fade, not an opaque plate, keeps the pager legible over rows ([scroll-edge](scroll-edge.md)).
- **R2. Apple Liquid Glass is navigation-only.** Content cards and custom controls do not call `glassEffect`; only `Design/GlassSurface.swift` may implement the drawer and Debug A/B glass. HIG Materials: "Don't use Liquid Glass in the content layer."
- **R3. Raw standard material stays in the design layer.** Do not add `.ultraThinMaterial`, `.thinMaterial`, `.regularMaterial` or `.thickMaterial` backgrounds outside `Design/`; the explicit approved variants below retain their contrast and pre-26 behavior.
- **R4. Accessibility replaces translucency.** Reduce Transparency or increased contrast yields an opaque surface with a visible border; text and status information do not rely on the artwork behind them. HIG Accessibility: "If the default does not meet these minimums, provide a higher-contrast scheme when Increase Contrast is on."
- **R5. Preserve the native surface model.** Android `GlassCard` is an M3 `Surface` with a tonal card color and border; Windows cards use `FSTCardSurfaceBrush` rather than per-frame Acrylic. MD3: "Tonal surfaces replace elevation shadows as the primary depth cue."
- **R6. Avoid nesting surfaces.** A group owns one card; its rows, pills, badges and meters use flat fills. System sheets own their own material and must not contain a second glass card.
- **R7. A "View all" call to action takes the web's surface.** Where the web frosts it (player page `BandViewAllCard`), it is a full-width frosted card on the canonical surface: 48 dp/pt/epx minimum height, centred Title Case label and the in-card chevron, one button named by its label. The purple filled leaderboard CTA is an **approved variant** only where the operator chose it over the web's frosted fill (6.29: leaderboard, song, ranking and rivals cards); do not extend it to new View-all rows.
  - Agent decision (#319, 2026-10-06, owner may override with `/choose`): Windows' board-footer **Your page** button (`LeaderboardsSpotlight`, Song Leaderboard) also moved from the old pager-only `#121826` plate to `FSTCardSurfaceBrush` / `FSTCardStrokeBrush` with `FSTSecondaryTextBrush` text, so no pager-only brush remains (R1). The pinned row's opaque `FSTFloatingBackplateBrush` (#208) is unchanged.
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
