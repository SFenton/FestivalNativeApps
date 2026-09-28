# Fluent 2 tokens with platform-native chrome

> **What:** the cross-platform design contract: tokens, colours, branded content vs system chrome. **Read when:** adding colours, typography, spacing or any branded visual on any platform. Per-platform chrome lives in [apple/](apple/README.md), [android.md](android.md), [windows.md](windows.md).

## Tokens

- Use Fluent [global and semantic alias tokens](https://fluent2.microsoft.design/) for content surfaces, typography, spacing, shape, focus and high contrast.
- Brand palette is pinned to `packages/theme/src/colors.ts:1-65` in [contracts/fluent-tokens.json](../../contracts/fluent-tokens.json). `python3 tools/generate_tokens.py` generates SwiftUI, Compose and WinUI resources; `--check` detects drift. Never hardcode duplicate colours in pages.
- `python3 -m tools.contrast_gate` requires ≥4.5:1 over worst-case white artwork for **only** `textPrimary`, `textSecondary` and `gold` (primary 8.45:1, secondary 6.24:1, gold 6.03:1 at 0.7 dim), plus the status-chip/badge pairs. Muted text and accent blue **fail** on art: keep them on opaque cards or use `textSecondary`. The gate does not certify rendered labels.
- System high-contrast themes override brand colours wherever contrast would suffer.
- Icons: native system symbols where system navigation needs them; map Fluent System Icons to stable semantic IDs for bespoke content and check redistribution rights. Instrument icons come from the operator's own web app (`public/instruments/`, downscaled to 144 px).

## Branded content vs system chrome

- **Branded content** (replicate precisely): the difficulty meter's 62×20 geometry and states ([difficulty-meter](../controls/difficulty-meter/spec.md)); artwork motion — 5-second images, 1-second crossfades, reduced-motion / data-saving / invisibility handling ([artwork-background](../controls/artwork-background/spec.md)). Source: `FortniteFestivalWeb/src/components/songs/metadata/DifficultyBars.tsx:15-37`, `FortniteFestivalWeb/src/components/shell/AnimatedBackground.tsx:7-85`.
- **System chrome** (use the platform's own): tabs, toolbars, sheets, split views, safe areas, focus. Never require byte-identical pixels for system bars; never copy web device-pixel heuristics.
- Fluent Apple controls are UIKit/AppKit and do not replace SwiftUI navigation; Fluent Android Compose controls may be used when behavior and accessibility match the platform.

Evidence: [Fluent 2](https://fluent2.microsoft.design/), [Apple Duo design](https://developer.apple.com/videos/play/tech-talks/111466/), [Windows development path](https://learn.microsoft.com/en-us/windows/apps/get-started/).
