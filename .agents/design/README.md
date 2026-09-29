# Design router

> **What:** design language and per-platform UI decisions. **Read when:** choosing chrome, layout, tokens or motion. Order of precedence: platform HIG first, Fluent second.

| File | Read when |
|---|---|
| [fluent.md](fluent.md) | Tokens, colour, branded content (all platforms) |
| [apple/](apple/README.md) | iPhone (Liquid Glass / classic), iPad, Duo, Mac layout decisions |
| [android.md](android.md) | Compose adaptive navigation per form factor |
| [windows.md](windows.md) | WinUI 3 chrome |

## Capitalization (all platforms, operator 2026-09-28)

**Title Case** for every UI label: page and section titles, buttons, tabs, menu items, filter/sort options, chips, picker values (e.g. "All Instruments", "Sort By", "View Full Leaderboard"). **Sentence case** only for full sentences: subtitles, descriptions, hints, empty-state bodies, alerts' message text. This follows the operator's original Title Case direction and Apple's title-style rule for controls; Android and Windows adopt the same rule for cross-platform consistency (a documented deviation from M3/Fluent sentence case).

