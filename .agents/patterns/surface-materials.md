# Surface materials

> **What:** shared policy for translucent content cards, rows and floating controls over artwork. **Read when:** adding or changing a card, row, capsule, sheet fallback or custom glass effect.

Status: **current**, 2026-10-05. Provenance: #291.

## Intent

Content must remain legible and cheap to scroll over animated artwork. Use one platform-native frosted surface per content role; reserve Liquid Glass and system equivalents for navigation and system chrome.

## Web source (behavior reference)

| Web | Behavior |
|---|---|
| `FortniteFestivalWeb/src/components/common/FrostedCard.tsx` (`FrostedCard`) | Shared frosted content container over the animated backdrop. |
| `FortniteFestivalWeb/src/pages/leaderboards/components/RankingCard.tsx` | Groups ranking rows in a frosted card; row content stays distinct from chrome. |

## Rules

- **R1. Content uses the canonical material surface.** Cards, content rows and non-system floating controls use the shared card/capsule primitive; no feature creates its own frosted, blur or glass stack.
- **R2. Apple Liquid Glass is navigation-only.** Content cards and custom controls do not call `glassEffect`; only `Design/GlassSurface.swift` may implement the drawer and Debug A/B glass. HIG Materials: "Don't use Liquid Glass in the content layer."
- **R3. Raw standard material stays in the design layer.** Do not add `.ultraThinMaterial`, `.thinMaterial`, `.regularMaterial` or `.thickMaterial` backgrounds outside `Design/`; the explicit approved variants below retain their contrast and pre-26 behavior.
- **R4. Accessibility replaces translucency.** Reduce Transparency or increased contrast yields an opaque surface with a visible border; text and status information do not rely on the artwork behind them. HIG Accessibility: "If the default does not meet these minimums, provide a higher-contrast scheme when Increase Contrast is on."
- **R5. Preserve the native surface model.** Android `GlassCard` is an M3 `Surface` with a tonal card color and border; Windows cards use `FSTCardSurfaceBrush` rather than per-frame Acrylic. MD3: "Tonal surfaces replace elevation shadows as the primary depth cue."
- **R6. Avoid nesting surfaces.** A group owns one card; its rows, pills, badges and meters use flat fills. System sheets own their own material and must not contain a second glass card.

## Canonical implementation

| Sub-behavior | Apple | Android | Windows |
|---|---|---|---|
| Content card and row | `FestivalUI/Design/RowCardSurface.swift` `FestivalCardModifier`, `festivalCard`, `festivalRowCard` | `ui/design/DesignPrimitives.kt` `GlassCard` | `Festival.App/Themes/Styles.xaml` `FSTCardSurfaceBrush`; `Controls/SongRowCard.xaml.cs` `SongRowCard` |
| Group and floating capsule | `FestivalUI/Design/GlassSection.swift` `FestivalGlassSection`; `RowCardSurface.swift` `festivalCardCapsule` | `ui/design/DesignPrimitives.kt` `GlassCard` | `Controls/LeaderboardEntryRow.xaml.cs` `LeaderboardEntryRow`; `Themes/Styles.xaml` `FSTFloatingBackplateBrush` |
| Glass exception | `FestivalUI/Design/GlassSurface.swift` `FestivalGlassModifier` | Native navigation chrome | Native pane/overlay chrome |

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
