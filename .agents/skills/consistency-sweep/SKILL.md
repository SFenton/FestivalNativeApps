---
name: consistency-sweep
description: Find every place a UI behavior or component pattern appears across the FestivalNativeApps platforms and the web app, identify the canonical implementation and list divergences. Use before fixing a visual or interaction bug, when reviewing a change, or when asked whether something is consistent across pages or platforms.
---

# Skill: consistency sweep

> **What:** a repeatable search that turns "fix this screen" into "fix this behavior everywhere it lives". **Read when:** step 2 of [fix-reported-issue](../fix-reported-issue/SKILL.md), when reviewing a PR, or when the owner asks "do other pages do this?".

## Steps (the design ladder)

Work down the ladder in order; each rung either answers the question or hands it to the next.

1. **Name the behavior**, not the screen: for example "rows fade under a pinned header", "card surface", "row height", "spinner placement", "Close button in a sheet".
2. **Registered pattern?** `python3 tools/pattern_guard.py index`, then read the matching doc in [patterns](../../patterns/README.md). Its *Canonical implementation* table is the expected answer and its *Known debt* lists known divergences. If one matches, skip to step 5.
3. **Undocumented native pattern?** Search the code on all three platforms for the behavior's keywords and APIs:
   - Apple: `rg -n '<keyword>|<API>' apple/Sources`
   - Android: `rg -n '<keyword>|<API>' android/app/src/main`
   - Windows: `rg -n '<keyword>|<API>' windows --glob '!*Tests*'`
   - History: `git log --oneline -S '<symbol>' -- apple android windows | head`, plus earlier tracker issues on the same behavior.

   A shared component or modifier used by two or more pages, or the same behavior solved in two or more places, is an **undocumented pattern**. Pick the implementation that best matches the web (step 4) as canonical, and register it in the same change. Several divergent copies of one behavior means consolidating them, never adding one more.
4. **Web pattern?** The web app is the product's design source of truth and the wider pattern library:
   - Start from the web page for the screen (`FortniteFestivalWeb/src/pages/…`) and follow its imports to the component or hook that draws the behavior.
   - Shared web building blocks live in `src/components/{common,page,modals,leaderboard,songs,sort,search,shell,display,…}`, `src/hooks/ui/` and `src/styles/` (`theme.css`, `effects.module.css`, `animations.css`, `songRowStyles.ts`). Design tokens (spacing, sizes, colors, motion) live in `packages/theme/src/` at the scraper repo root (`$FST_WEB_SRC`, or `~/fst-agents/repos/FortniteFestivalLeaderboardScraper`).
   - Count its reuse: `rg -l "<ComponentOrHook>" <web>/FortniteFestivalWeb/src --glob '!**/__test__/**' | wc -l`. Two or more pages or modals means a **shared web pattern**.
   - Check the PWA reference captures and notes (`.agents/testing/pwa-reference/`) for how it looks and moves on each platform.
   - The web's states, constants, copy and tokens define the behavior (semantic parity). Web chrome is never copied onto native chrome.
5. **Align with platform guidance.** Check the result against the platform skill (`apple-hig`, `material-3`, `winui-design`), keeping the strength of each rule (must, should, consider). Resolve conflicts with the precedence table below.
6. **Implement or decide.** Tabulate the findings (in your root-cause/approach update or review):

| Place (page/modal/platform) | Implementation (file:symbol) | Matches the rules? | Action |
|---|---|---|---|

   Fix everything in scope through the one canonical component, and register or update the pattern. Out-of-scope divergences go in `blast_radius` as `deferred`. Anything the precedence table marks *decision* goes to [design-proposal](../design-proposal/SKILL.md).

## Precedence when the rungs disagree

| Conflict | Wins |
|---|---|
| Platform **must** (accessibility minimums, hit targets, Dynamic Type/font scaling, Reduce Motion/Transparency, contrast, App Review) vs anything | The platform requirement, always |
| An explicit owner decision (issue, comment, `/choose`, or an approved variant in a pattern doc) vs web or a platform recommendation | The owner decision |
| Web behavior (states, constants, copy, data) vs an undocumented native implementation | The web; consolidate the native copies to it |
| Web chrome (header, menus, modals, search UI) vs native platform chrome | Native platform conventions |
| Web behavior vs a platform **should/consider** recommendation, with no owner decision | **Decision**: propose options |
| No registry, native or web precedent, in navigation, chrome, layout or materials | **Decision**: propose options |
| No precedent anywhere, in content or logic | Build it shared, register it as a new pattern |

## Smells that mean a sweep was skipped

- A new type or modifier named after one screen (`NotificationsHeaderFade`) that does what a shared one does.
- A constant that differs from the web or the pattern doc (28 vs 40, 44 vs 48).
- A fix that reads "only on Songs" while other lists or sheets have the same structure.
- An owner follow-up saying "other pages already do this".
