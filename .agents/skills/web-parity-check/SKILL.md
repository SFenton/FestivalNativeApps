---
name: web-parity-check
description: Compare a FestivalNativeApps behavior with the web app (the product source of truth) by locating the web component, extracting its constants, copy, states and timings, and deciding semantic parity under native platform rules. Use when an issue says "like web", when porting, or when a native constant or behavior might differ from the web.
---

# Skill: web parity check

> **What:** how to read the web app as the behavior reference without copying web chrome onto native platforms. **Read when:** an issue mentions the web, a pattern doc cites a web file, or you're about to pick a size, timing, string or state by eye.

## Steps

1. **Locate the web source.** Use `$FST_WEB_SRC`, or `~/fst-agents/repos/FortniteFestivalLeaderboardScraper/FortniteFestivalWeb/src` on agent hosts. The operator's own checkout may be dirty: read it, never modify it. Start from the page (`pages/…`), the component (`components/…`) or the hook (`hooks/ui/…`) named in the pattern doc or page spec.
2. **Extract the facts** into a table: states (loading, empty, error, populated, selected), constants (sizes, durations, easing, thresholds such as `useScrollMask` `DEFAULT_SIZE = 40` or `useScrollFade` `36`), copy (exact strings per state), ordering, and what each input changes. Cite `file:line`.
3. **Compare** with the native implementation on your platform(s) and with the pattern's canonical component.
4. **Decide what parity means here** ([design/fluent.md](../../design/fluent.md)):
   - *Semantic parity* (always): states, data, copy, order, what happens on each action, constants for content behavior (fades, row heights, timings).
   - *Native chrome* (never copied from web): navigation bars, sheets, menus, system search, controls. Platform guidance wins (HIG on Apple, M3 on Android, Fluent on Windows).
5. **Use one constant.** If native needs the web value, put it in the platform's single constant (pattern doc, `generate_tokens.py` tokens, or the canonical component), never inline in a feature.
6. **Record** the web reference in the pattern doc's *Web source* table, or in the page/control `spec.md` when it's page-specific.
