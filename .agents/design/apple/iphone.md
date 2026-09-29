# iPhone design (iOS 26 Liquid Glass, iOS 17 classic)

> **What:** SwiftUI chrome and layout decisions for iPhone. **Read when:** building any iPhone screen. Page/control specifics live in `pages/<id>/ios.md` and `controls/<id>/ios.md`.

## Chrome

- System `TabView` + `NavigationStack`. iOS 26+: Liquid Glass tab bar and navigation accessories behind availability checks; iOS 17–25 keeps the system classic tab bar. Which surfaces are glass, and the shared components to use: [liquid-glass.md](liquid-glass.md).
- Header: global Search and the profile avatar on every page; page tools (Songs Filter/Sort, Quick Links) float as separate round glass buttons above the tab bar; everything else goes in the top toolbar ([nav-accessories.md](nav-accessories.md), [global-search](../../controls/global-search/ios.md)).
- Other page actions (Item Shop, Paths, metric menus) stay in the **top** toolbar. Never use `.bottomBar` toolbar items with the tab bar: a bottom-toolbar Sort overlapped the floating Liquid Glass tab and activated Leaderboards instead (page tools float in a safe-area inset instead).
- Profile avatar (trailing) and hamburger (leading) come from `festivalRootChrome` on tab roots; the avatar has an accessible name (mirrors the web mobile header).
- Shell (Lane A, landed 2026-09-27): conditional tabs mirroring web `BottomNav`, `festivalRootChrome` on every tab root (leading hamburger drawer, trailing profile), `festivalSheet` dark sheets with detents, white Title Case section headers ([liquid-glass.md](liquid-glass.md)).

## Layout rules learned on iOS 26.5

- **Nothing readable under the floating tab.** Accessibility audits flag rows behind it. Grouped Lists: remove only the unused vertical row insets, keep 16pt horizontal gutters, so final cards clear the tab.
- Text over artwork sits on opaque Fluent cards; text is white (`FestivalText.primary`), never system gray — see the [text colour rule](../../platforms/apple/architecture.md#text-colour-rule-operator-rule-2026-09-28).
- Sheets: full-height system sheet, pinned Cancel/Apply footer, Reset inside the scrolling Form, interactive dismissal disabled while a draft is changed.
- Accessibility text sizes: wrap and stack (full-width title, then art, then content) rather than clip; scroll the nested scroller that owns the content. At AX5, a modal needs an opaque header and a separately clipped Form viewport so text never scrolls behind system glass.
- Do not use device-name breakpoints; use size classes, safe areas and measured widths.

## Motion

- **Marquee, not ellipsis, for single-line content text.** Song titles/artist lines, player, rival and band names in rows, cards and compact headers use `MarqueeText` (`Design/MarqueeText.swift`, web `MarqueeText.tsx`): sized like a plain one-line `Text`; once it overflows by >1pt, a two-copy track scrolls one copy + 28pt every 8 s with a 5% hold at each end. Swap `Text(x)` for `MarqueeText(x)` and keep the `.font`/`.foregroundStyle` modifiers (font is inherited). Wrap a title + subtitle pair in `.marqueeSync()` so both move the same distance (web `useMarqueeSync`). It truncates under system or in-app Reduce Motion, off screen, in an inactive scene and under `FST_DEBUG_STILL_BACKGROUND`. Labels, pills, badges and text that intentionally wraps (Shop rows, Solo hero, profile header) keep their layout.
- Never measure a marquee's container around its scrolling content: the track is wider than the container by definition, so the overflow check flips back to "fits" and it never scrolls (the pre-2026-09-28 bug). The track lives in an overlay of a hidden truncating base.
- Song page backgrounds fade (300 ms CSS `ease`) to the song's art; see [artwork-background](../../controls/artwork-background/ios.md).
