# iPhone design (iOS 26 Liquid Glass, iOS 17 classic)

> **What:** SwiftUI chrome and layout decisions for iPhone. **Read when:** building any iPhone screen. Page/control specifics live in `pages/<id>/ios.md` and `controls/<id>/ios.md`.

## Chrome

- System `TabView` + `NavigationStack`. iOS 26+: Liquid Glass tab bar and navigation accessories behind availability checks; iOS 17–25 keeps the system classic tab bar. `festivalGlass` supplies Liquid Glass with a pre-26 fallback.
- Put page actions (Sort, Filter, Item Shop, profile) in the **top** toolbar: a bottom-toolbar Sort overlapped the floating Liquid Glass tab and activated Leaderboards instead.
- Compact profile action is icon-only with an accessible name (mirrors the web mobile header).
- Wave 1 targets (from [PROGRESS.md](../../../PROGRESS.md)): conditional tabs mirroring web `BottomNav`, profile button top-right on every tab root, leading hamburger drawer (Item Shop, Bands, Rivals, Manual, Licenses), dark-glass sheets with native detents and Title Case white section headers.

## Layout rules learned on iOS 26.5

- **Nothing readable under the floating tab.** Accessibility audits flag rows behind it. Grouped Lists: remove only the unused vertical row insets, keep 16pt horizontal gutters, so final cards clear the tab.
- Text over artwork sits on opaque Fluent cards; section headers use `textSecondary`, not system gray.
- Sheets: full-height system sheet, pinned Cancel/Apply footer, Reset inside the scrolling Form, interactive dismissal disabled while a draft is changed.
- Accessibility text sizes: wrap and stack (full-width title, then art, then content) rather than clip; scroll the nested scroller that owns the content. At AX5, a modal needs an opaque header and a separately clipped Form viewport so text never scrolls behind system glass.
- Do not use device-name breakpoints; use size classes, safe areas and measured widths.
