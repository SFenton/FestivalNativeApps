# Pattern registry

> **What:** one record per cross-page, cross-platform behavior, such as scroll edges, materials, nav chrome, the modal shell or leaderboard rows: its intent, web source, canonical component on each platform, numbered rules and the known debt. **Read when:** before fixing a bug or building a feature that touches any behavior listed here. Find the precedent first, then extend the canonical component instead of adding a parallel one.

Machine-readable twin: [`contracts/patterns.json`](../../contracts/patterns.json). `python3 tools/pattern_guard.py` checks that both agree, that every canonical file and symbol exists, and that no new code breaks a pattern's guard rules. Skill: [consistency-sweep](../skills/consistency-sweep/SKILL.md).

## How to use a pattern

1. **Find it.** `python3 tools/pattern_guard.py index` lists every pattern, `python3 tools/pattern_guard.py which <path>` names the patterns owning a file, and `grep -l <keyword> .agents/patterns/*.md` searches the docs.
2. **Obey the Rules block.** Each rule is numbered (`R1`…) so issues, PRs and reviews can cite it (`scroll-edge R3`).
3. **Fix the pattern, not the instance.** Change the canonical component so every consumer gets the fix. A new local mechanism for a behavior a pattern already owns is a review failure unless the pattern doc records it as an approved variant.
4. **Changing a rule is a design decision.** Decide and document it ([design-decision](../skills/design-decision/SKILL.md)), and update the doc and `patterns.json` in the same PR (`Agent decision (#n, date)`; the owner may override). Mark the old rule with `Supersedes:` and sweep every platform listed under *Canonical implementation*.
5. **Known debt** lists the places that don't follow the rules yet. The guard allows them until they are fixed; never add new entries without a documented decision.

## When no pattern matches

The registry only lists behaviors the native apps have already needed to share. The **web app is the wider pattern library**: shared components in `FortniteFestivalWeb/src/components/{common,page,modals,…}`, `src/hooks/ui/`, `src/styles/` and the tokens in `packages/theme/src/`. If the behavior you're touching isn't here, climb the design ladder ([consistency-sweep](../skills/consistency-sweep/SKILL.md)): look for an undocumented native pattern on all three platforms, then the web's implementation, then align with platform guidance using the precedence table. If the web reuses it across pages, build one shared native component that mirrors it and add a pattern entry here in the same change (status `current`, the web files as *Web source*). A behavior with no registry entry and no web precedent is a native invention; for navigation, chrome, layout or materials that is a documented design decision.

## Patterns

| Pattern | Owns |
|---|---|
| [scroll-edge](scroll-edge.md) | Content fading under pinned chrome: page headers, sheet headers, pinned section headers and bottom chrome |
| [section-jump-landing](section-jump-landing.md) | Where Quick Links and the A–Z index land a section, and which section counts as current |
| [surface-materials](surface-materials.md) | Liquid Glass vs material vs opaque surfaces; cards, rows and custom controls |
| [page-tools-and-nav-chrome](page-tools-and-nav-chrome.md) | Where page actions, search, Quick Links, the bell and Profile live on each platform |
| [modal-shell](modal-shell.md) | Shared sheet and dialog container: header, Close, detents, top fade, dismissal |
| [leaderboard-row](leaderboard-row.md) | Leaderboard and score rows: height, columns, name marquee, pinned player row and pager |
| [load-transition](load-transition.md) | Fade out, spinner, fade in on page or modal load and reload; graph card list swaps; staggered row fade-in |
| [empty-error-states](empty-error-states.md) | Empty, no-results, unavailable and error states: layout, copy and retry |
| [quick-links](quick-links.md) | The Quick Links menu: order, icons, activation line and placement |
| [section-headers](section-headers.md) | Section titles: style, outside-card placement and pinned/sticky behavior |
| [chart-date-axis](chart-date-axis.md) | Date labels on history bar charts: centred on their bar, visible bars only |
| [song-header](song-header.md) | Song page headers: shared art + title/artist block, full-width one-line marquee, pinned bar song title |
| [view-all-cta](view-all-cta.md) | The full-width purple "View all" button below a card's rows: look, placement, copy and accessible name |
