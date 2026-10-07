# Split panes

> **What:** the boundary between the two panes of a list/detail split: the band between them, whether it draws a line, and the one backdrop running across it. **Read when:** changing a split's divider, band, backdrop or pane margins on any platform, or adding a list/detail split.

Status: **current**, 2026-10-07. Provenance: #344 (split from #332; agent decision). Layout, geometry and page classification: [split-view.md](../design/apple/split-view.md) (Apple).

## Intent

A split reads as one page that opened an item beside itself, not as two windows. The panes are separated by space (the band and each pane's full-page margins; on a foldable, the fold), never by a drawn splitter, and the page's one backdrop and top darkening run unbroken across the band.

## Web source (behavior reference)

None: the web app has no list/detail split. This is a native layout pattern decided under the design ladder (decision below).

## Rules

1. **R1. No drawn divider.** The band between the panes draws no line, rule or splitter handle. Its width separates the panes: the fold/hinge on a foldable (Apple `OnDemandSplitPolicy.Geometry.isHinge`), else a 1 pt band at the midpoint plus each pane's full-page margins (20 pt a side on iPad). Owner (#332): "Split View should not have visible vertical splitter component". HIG Layout: "Group related information/functions using negative space, containers, or separators" (should).
2. **R2. Increase Contrast restores a hairline at a midpoint only.** With the system's Increase Contrast on, a midpoint band draws a 1 pt hairline (Apple `Color.white.opacity(0.16)`); a hinge never does, the fold divides the panes. HIG Accessibility: "provide a higher-contrast scheme when Increase Contrast is on" (should).
3. **R3. One backdrop across the band.** The band is clear over the split's single backdrop and carries the panes' top-edge gradient, so image and darkening are continuous from pane to pane (split-view.md "One background, full-page insets").
4. **R4. One component per platform.** Every split draws its band through the canonical layout below; a page never adds its own divider between panes.

Agent decision (#344, 2026-10-07; owner may override with `/choose`): options were (A) no line on the Duo only, keeping the 1 pt hairline on iPad and Mac per HIG Split views macOS "Prefer the 1 pt thin divider" (prefer); (B) no line on any split; (C) B plus the hairline under Increase Contrast at a midpoint. Chose **C**: the owner's words name no platform and an owner choice outranks a platform *prefer*; the macOS clause picks a style for *draggable* dividers, and this split is fixed at the midpoint; Increase Contrast keeps an accessible boundary for people who ask for one. Supersedes: split-view.md "Prefer the 1 pt thin divider (kept)".

## Canonical implementation

| Sub-behavior | Apple | Android | Windows |
|---|---|---|---|
| Line rule (R1, R2) | `apple/Sources/FestivalUI/App/Layout/OnDemandSplitPolicy.swift` `OnDemandSplitPolicy.drawsDividerLine` | — (see debt) | — (no split) |
| Band and backdrop (R3, R4) | `apple/Sources/FestivalUI/App/Layout/OnDemandSplit.swift` `OnDemandSplitLayout` (private `SplitDivider`, `SplitBackdrop`); `SplitPaneChrome.swift` `SplitPaneChrome` | — | — |

Apple consumers: `OnDemandSplitStack` (iPad, iPhone Duo inner landscape) and `MacListDetailStack` (Mac content area): Rivals, All Rivals, Leaderboards (Full/Band Rankings in the trailing pane; profiles cover both panes as full pages, #352), Song Detail (full leaderboard, score history), Settings › Licenses. Tests: `OnDemandSplitPolicyTests.dividerLineOnlyUnderIncreaseContrastAtAMidpoint`; `MacAccessibilityTreeTests` (the band is never an accessibility element).

## Known debt

| Debt | Breaks | Plan |
|---|---|---|
| Android Songs list/detail (`android/app/src/main/java/com/festivalscoretracker/android/ui/shell/FestivalApp.kt`) draws a `VerticalDivider(color = BrandTokens.glassBorder)` between the panes | R1, R2 | Android check (out of #344's Apple scope) |

## Guards (`tools/pattern_guard.py`)

- `split-panes/android-vertical-divider`
