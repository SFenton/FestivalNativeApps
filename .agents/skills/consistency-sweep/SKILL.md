---
name: consistency-sweep
description: Find every place a UI behavior or component pattern appears across the FestivalNativeApps platforms and the web app, identify the canonical implementation and list divergences. Use before fixing a visual or interaction bug, when reviewing a change, or when asked whether something is consistent across pages or platforms.
---

# Skill: consistency sweep

> **What:** a repeatable search that turns "fix this screen" into "fix this behavior everywhere it lives". **Read when:** step 2 of [fix-reported-issue](../fix-reported-issue/SKILL.md), when reviewing a PR, or when the owner asks "do other pages do this?".

## Steps

1. **Name the behavior**, not the screen: for example "rows fade under a pinned header", "card surface", "row height", "spinner placement", "Close button in a sheet".
2. **Registry first.** `python3 tools/pattern_guard.py index`, then read the matching doc in [patterns](../../patterns/README.md). Its *Canonical implementation* table is the expected answer; its *Known debt* table lists the divergences already known.
2b. **No registered pattern? The web is the pattern.** The web app is the product's design source of truth, so before concluding "nothing shared exists", find how the web builds this behavior:
   - Start from the web page for the screen (`FortniteFestivalWeb/src/pages/…`) and follow its imports to the component or hook that draws the behavior.
   - Shared web building blocks live in `src/components/{common,page,modals,leaderboard,songs,sort,search,shell,display,…}`, `src/hooks/ui/`, `src/styles/` (`theme.css`, `effects.module.css`, `animations.css`, `songRowStyles.ts`), and the design tokens in `packages/theme/src/` at the scraper repo root (spacing, sizes, colors, motion).
   - Count its reuse: `rg -l "<ComponentOrHook>" <web>/FortniteFestivalWeb/src --glob '!**/__test__/**' | wc -l`. Used by two or more pages or modals means it's a **shared web pattern**, even though the native registry doesn't list it yet.
   - Look at the PWA reference captures and notes (`.agents/testing/pwa-reference/`) for how it looks and moves on each platform.
   - Then: the web component's states, constants, copy and tokens are the rules (semantic parity; native chrome stays native). Implement one shared native component per platform, and register the pattern (`.agents/patterns/<id>.md` + `contracts/patterns.json`, status `current`, the web files as *Web source*) in the same change. A behavior that exists neither in the registry nor on the web is a native invention: for navigation, chrome, layout or materials it is an owner decision ([design-proposal](../design-proposal/SKILL.md)).
3. **Search the code on all three platforms** with keywords from the pattern (`keywords` in `contracts/patterns.json`) and the APIs involved:
   - Apple: `rg -n '<keyword>|<API>' apple/Sources`
   - Android: `rg -n '<keyword>|<API>' android/app/src/main`
   - Windows: `rg -n '<keyword>|<API>' windows --glob '!*Tests*'`
   - Web: `rg -n '<keyword>' <web>/FortniteFestivalWeb/src`, where `<web>` is `~/fst-agents/repos/FortniteFestivalLeaderboardScraper` (or `$FST_WEB_SRC`)
4. **Search history** for earlier fixes of the same behavior: `git log --oneline -S '<symbol>' -- apple android windows | head`, and the issue numbers in the pattern's provenance line.
5. **Tabulate** (put this in your root-cause/approach update or review):

| Place (page/modal/platform) | Implementation (file:symbol) | Matches the pattern rules? | Action |
|---|---|---|---|

6. **Decide.** Everything in your scope that diverges gets fixed through the canonical component. Divergences out of scope go in `blast_radius` as `deferred`. A divergence that looks intentional but isn't in the doc means asking the owner (design-proposal), not silently "fixing" it.

## Smells that mean a sweep was skipped

- A new type or modifier named after one screen (`NotificationsHeaderFade`) that does what a shared one does.
- A constant that differs from the web or the pattern doc (28 vs 40, 44 vs 48).
- A fix that reads "only on Songs" while other lists or sheets have the same structure.
- An owner follow-up saying "other pages already do this".
