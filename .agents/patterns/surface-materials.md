# Surface materials

> **What:** shared policy for translucent content cards, rows and floating controls over artwork. **Read when:** adding or changing a card, row, capsule, sheet fallback or custom glass effect.

Status: **current**, 2026-10-06. Provenance: #291, #312 (R7).

## Intent

Content must remain legible and cheap to scroll over animated artwork. Use one platform-native frosted surface per content role; reserve Liquid Glass and system equivalents for navigation and system chrome.

## Web source (behavior reference)

| Web | Behavior |
|---|---|
| `FortniteFestivalWeb/src/components/common/FrostedCard.tsx` (`FrostedCard`) | Shared frosted content container over the animated backdrop. |
| `FortniteFestivalWeb/src/pages/leaderboards/components/RankingCard.tsx` | Groups ranking rows in a frosted card; row content stays distinct from chrome. |
| `FortniteFestivalWeb/src/pages/player/components/PlayerBandsSection.tsx` (`BandViewAllCard`) | "View all bands (N)" is a full-width frosted card (`frostedCard`, `Layout.entryRowHeight` 48 px), centred semibold label and chevron; not a filled button. |

## Rules

- **R1. Content uses the canonical material surface.** Cards, content rows and non-system floating controls use the shared card/capsule primitive; no feature creates its own frosted, blur or glass stack.
- **R2. Apple Liquid Glass is navigation-only.** Content cards and custom controls do not call `glassEffect`; only `Design/GlassSurface.swift` may implement the drawer and Debug A/B glass. HIG Materials: "Don't use Liquid Glass in the content layer."
- **R3. Raw standard material stays in the design layer.** Do not add `.ultraThinMaterial`, `.thinMaterial`, `.regularMaterial` or `.thickMaterial` backgrounds outside `Design/`; the explicit approved variants below retain their contrast and pre-26 behavior.
- **R4. Accessibility replaces translucency.** Reduce Transparency or increased contrast yields an opaque surface with a visible border; text and status information do not rely on the artwork behind them. HIG Accessibility: "If the default does not meet these minimums, provide a higher-contrast scheme when Increase Contrast is on."
- **R5. Preserve the native surface model.** Android `GlassCard` is an M3 `Surface` with a tonal card color and border; Windows cards use `FSTCardSurfaceBrush` rather than per-frame Acrylic. MD3: "Tonal surfaces replace elevation shadows as the primary depth cue."
- **R6. Avoid nesting surfaces.** A group owns one card; its rows, pills, badges and meters use flat fills. System sheets own their own material and must not contain a second glass card.
- **R7. A "View all" call to action takes the web's surface.** Where the web frosts it (player page `BandViewAllCard`), it is a full-width frosted card on the canonical surface: 48 dp/pt/epx minimum height, centred Title Case label and the in-card chevron, one button named by its label. The purple filled leaderboard CTA is an **approved variant** only where the operator chose it over the web's frosted fill (6.29: leaderboard, song, ranking and rivals cards); do not extend it to new View-all rows.
  - Agent decision (#312, 2026-10-06): Android's player-page "View All Bands (N)" is a clickable `GlassCard` (web frosted card), not `ViewFullLeaderboardButton`; owner may override with `/choose`.

## Canonical implementation

| Sub-behavior | Apple | Android | Windows |
|---|---|---|---|
| Content card and row | `FestivalUI/Design/RowCardSurface.swift` `FestivalCardModifier`, `festivalCard`, `festivalRowCard` | `ui/design/DesignPrimitives.kt` `GlassCard` | `Festival.App/Themes/Styles.xaml` `FSTCardSurfaceBrush`; `Controls/SongRowCard.xaml.cs` `SongRowCard` |
| Group and floating capsule | `FestivalUI/Design/GlassSection.swift` `FestivalGlassSection`; `RowCardSurface.swift` `festivalCardCapsule` | `ui/design/DesignPrimitives.kt` `GlassCard` | `Controls/LeaderboardEntryRow.xaml.cs` `LeaderboardEntryRow`; `Themes/Styles.xaml` `FSTFloatingBackplateBrush` |
| Glass exception | `FestivalUI/Design/GlassSurface.swift` `FestivalGlassModifier` | Native navigation chrome | Native pane/overlay chrome |
| Frosted View-all card (R7) | — (not yet ported) | `ui/profile/ProfileBands.kt` `ProfileBandsViewAll` (`GlassCard(onClick)` + `RowChevron`) | — (not yet ported) |
| Purple View-all CTA (approved variant, 6.29) | `Features/Leaderboards/PurpleActionButton.swift` | `ui/design/ViewFullLeaderboardButton.kt` | — |

## Known debt

| Debt | Breaks | Plan |
|---|---|---|
| Apple material is measurably darker or more frosted over some bright macOS artwork than the retired glass card. | Exact glass appearance only; legibility and performance are preserved. | Accepted by the owner in #291; retain the fitted material. |

## Guards (`tools/pattern_guard.py`)

- `surface-materials/apple-glass-effect`
- `surface-materials/apple-raw-material-background` — approved allows: `PurpleActionButton`, the pre-26 First Run sheet fallback, and First Run's matching purple demo control.
