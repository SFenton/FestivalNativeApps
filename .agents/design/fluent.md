# Fluent 2 with platform-native chrome

Use Fluent's [global and semantic alias tokens](https://fluent2.microsoft.design/) for content surfaces, typography, spacing, shape, focus and high contrast. Adapt to the Festival palette after reading the website's theme source; don't invent a single flat dark color or hardcode tokens per page. Prefer native SF Symbols where system navigation requires them; map Fluent System Icons to stable semantic IDs for bespoke content and check redistribution rights.

Apple `TabView`, toolbars, sheets and split navigation handle Liquid Glass and Duo reserved regions more reliably than a hand-built tab lane. Android should use native window-size/posture-aware Compose navigation; Windows uses WinUI 3 `NavigationView`, surfaces and system focus conventions. Fluent Apple controls are primarily UIKit/AppKit, not a replacement for SwiftUI navigation. Fluent Android supplies Compose controls; select them when their behavior and accessibility match the platform.

The **difficulty meter and artwork motion** are branded content, not system chrome: replicate the meter's 62×20 geometry and intended foreground states; preserve 5-second images/1-second crossfades, with reduced motion, data saving and invisibility handling. See the original `FortniteFestivalWeb/src/components/songs/metadata/DifficultyBars.tsx:15-37` and `FortniteFestivalWeb/src/components/shell/AnimatedBackground.tsx:7-85`. Do not require byte-identical pixels for Apple/Android/Windows system bars.

Evidence: [Fluent 2](https://fluent2.microsoft.design/), [Apple Duo design](https://developer.apple.com/videos/play/tech-talks/111466/), [Windows development path](https://learn.microsoft.com/en-us/windows/apps/get-started/).
