# Pattern registry

> **What:** one record per cross-page, cross-platform behavior, such as scroll edges, materials, nav chrome, the modal shell or leaderboard rows: its intent, web source, canonical component on each platform, numbered rules and the known debt. **Read when:** before fixing a bug or building a feature that touches any behavior listed here. Find the precedent first, then extend the canonical component instead of adding a parallel one.

Machine-readable twin: [`contracts/patterns.json`](../../contracts/patterns.json). `python3 tools/pattern_guard.py` checks that both agree, that every canonical file and symbol exists, and that no new code breaks a pattern's guard rules. Skill: [consistency-sweep](../skills/consistency-sweep/SKILL.md).

## How to use a pattern

1. **Find it.** `python3 tools/pattern_guard.py index` lists every pattern, `python3 tools/pattern_guard.py which <path>` names the patterns owning a file, and `grep -l <keyword> .agents/patterns/*.md` searches the docs.
2. **Obey the Rules block.** Each rule is numbered (`R1`…) so issues, PRs and reviews can cite it (`scroll-edge R3`). A number names exactly one rule: when a merge leaves two copies of a rule, merge them into one that keeps every current requirement (record dropped wording with `Supersedes:`), and give a different rule the next free number, updating its references in docs, `contracts/patterns.json`, code comments and tests. `check_docs.py` fails on a number defined twice (#621).
3. **Fix the pattern, not the instance.** Change the canonical component so every consumer gets the fix. A new local mechanism for a behavior a pattern already owns is a review failure unless the pattern doc records it as an approved variant.
4. **Changing a rule is a design decision.** Decide and document it ([design-decision](../skills/design-decision/SKILL.md)), and update the doc and `patterns.json` in the same PR (`Agent decision (#n, date)`; the owner may override). Mark the old rule with `Supersedes:` and sweep every platform listed under *Canonical implementation*.
5. **Known debt** lists the places that don't follow the rules yet. The guard allows them until they are fixed; never add new entries without a documented decision.

## When no pattern matches

The registry only lists behaviors the native apps have already needed to share. The **web app is the wider pattern library**: shared components in `FortniteFestivalWeb/src/components/{common,page,modals,…}`, `src/hooks/ui/`, `src/styles/` and the tokens in `packages/theme/src/`. If the behavior you're touching isn't here, climb the design ladder ([consistency-sweep](../skills/consistency-sweep/SKILL.md)): look for an undocumented native pattern on all three platforms, then the web's implementation, then align with platform guidance using the precedence table. If the web reuses it across pages, build one shared native component that mirrors it and add a pattern entry here in the same change (status `current`, the web files as *Web source*). A behavior with no registry entry and no web precedent is a native invention; for navigation, chrome, layout or materials that is a documented design decision.

## Patterns

| Pattern | Owns |
|---|---|
| [artwork-background](artwork-background.md) | Shared decorative carousel and static song covers: motion, dimming, accessibility, failure recovery and ephemeral caches |
| [scroll-edge](scroll-edge.md) | Content fading under pinned chrome: page headers, sheet headers, pinned section headers and bottom chrome |
| [scroll-indicators](scroll-indicators.md) | Scroll bars: system indicators on every page, no in-app toggle, and the few views allowed to hide them |
| [section-jump-landing](section-jump-landing.md) | Where Quick Links and the A–Z index land a section, and which section counts as current |
| [surface-materials](surface-materials.md) | Liquid Glass vs material vs opaque surfaces; cards, rows and custom controls |
| [page-tools-and-nav-chrome](page-tools-and-nav-chrome.md) | Where page actions, search, Quick Links, the bell and Profile live on each platform |
| [modal-shell](modal-shell.md) | Shared sheet and dialog container: header, Close, detents, top fade, dismissal |
| [leaderboard-row](leaderboard-row.md) | Leaderboard and score rows: height, columns, name marquee, pinned player row and pager |
| [load-transition](load-transition.md) | Fade out, spinner, fade in on page or modal load and reload; graph card list swaps; staggered row fade-in |
| [accordion](accordion.md) | In-place expand/collapse (disclosure groups, switch reveals, selector panels): open then fade in, fade out then close; Reduce Motion and VoiceOver state |
| [reflow-motion](reflow-motion.md) | Layout reflows (split pane open/close, column changes, rewraps): moved content glides, arriving and leaving content fades; never a reload; instant under Reduce Motion |
| [empty-error-states](empty-error-states.md) | Empty, no-results, unavailable and error states: layout, copy and retry |
| [quick-links](quick-links.md) | The Quick Links menu: order, icons, activation line and placement |
| [section-headers](section-headers.md) | Section titles: style, outside-card placement and pinned/sticky behavior |
| [chart-date-axis](chart-date-axis.md) | Date labels on history bar charts: centred on their bar, visible bars only |
| [song-leaderboard-header](song-leaderboard-header.md) | Song-scoped leaderboards (instrument or band size): song-first header, bar title after scroll, song album-art backdrop |
| [song-header](song-header.md) | Song page headers: shared art + title/artist block, full-width one-line marquee, pinned bar song title |
| [view-all-cta](view-all-cta.md) | The full-width purple "View all" button below a card's rows: look, placement, copy and accessible name |
| [back-keeps-place](back-keeps-place.md) | Back to a cached page: no reload, no movement or replayed fade-in, focus back on the opener |
| [songs-profile-panel](songs-profile-panel.md) | Wide Songs rows with a selected player or band: song left, that profile's one-line score cards right |
| [stat-tile-grid](stat-tile-grid.md) | Profile and Band stat tile grids: a tile whose text would wrap in one slot spans two, one height for every tile, web order, wrap never truncate |
| [invalid-scores](invalid-scores.md) | Filter Invalid Scores: effective (raw, valid fallback or none) player scores on Songs and Song Details, the row's invalid-score indicator and Filtered Score alert, Over CHOpt Threshold |
| [settings-value-row](settings-value-row.md) | Read-only Settings title/value rows (Version, Service Info state): inline when it fits, otherwise the value stacks under the title |
| [settings-toggle-row](settings-toggle-row.md) | Settings switches: the whole row is one switch element and touch target (44 pt / 56 dp), one flip per tap, disabled rows ignore taps; the Mac keeps the system switch |
| [rival-rows](rival-rows.md) | Rivals rows: hub rival rows and song comparison rows, the shared red/green status pill and the song rows' album art |
| [hinge-columns](hinge-columns.md) | Foldable book pose: grid and two-up row gutters on the fold, full-width titles kept on their side, flat layout when unfolded |
| [wide-columns](wide-columns.md) | When rows and cards show two columns: wide landscape only (iPad, unfolded Duo, wide Mac), row-major under full-width headings, meeting at the Duo hinge; the page audit |
| [split-panes](split-panes.md) | List/detail split boundary: no drawn divider (a hairline only under Increase Contrast at a midpoint), one backdrop across the band |
| [catalogue-sort](catalogue-sort.md) | Sorting catalogue songs (Songs, Item Shop): the shared Sort sheet/flyout, direction section, comparator, Reset, trigger state, persistence and missing-data pause |
| [experimental-ranks](experimental-ranks.md) | Settings → Experimental Ranks as the one gate: which ranking metrics Rank By offers, fallback of saved/routed metrics to Total Score, and the profile tiles, Rivals, notifications, Mac menu and first-run slide it gates |
| [band-member-lines](band-member-lines.md) | Band card members: one line each, names leading on one shared edge, value and icons trailing, card-wide stack when any member can't fit |
| [metadata-pills](metadata-pills.md) | Season ("S15") and "Top N%" chips: one shared component each, one size on every page, web colours with the current season inverted, spoken "Current season N" |
| [instrument-chip-rows](instrument-chip-rows.md) | Songs row instrument status chips on a narrow row: the fewest balanced, centred lines in service order, never clipped, overlapped or shrunk |
| [shop-offer-status](shop-offer-status.md) | Item Shop New / Leaving Tomorrow on Songs rows, Shop rows and cards: gold outline only for New, a visible indicator only for Leaving, both spoken |
| [search-scopes](search-scopes.md) | Global search's kinds and the profile search's All · Players · Bands on one engine per platform: native All-first scope controls that start on All and only filter, and what a result opens |
