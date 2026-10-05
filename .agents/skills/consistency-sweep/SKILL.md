---
name: consistency-sweep
description: Find every place a UI behavior or component pattern appears across the FestivalNativeApps platforms and the web app, identify the canonical implementation and list divergences. Use before fixing a visual or interaction bug, when reviewing a change, or when asked whether something is consistent across pages or platforms.
---

# Skill: consistency sweep

> **What:** a repeatable search that turns "fix this screen" into "fix this behavior everywhere it lives". **Read when:** step 2 of [fix-reported-issue](../fix-reported-issue/SKILL.md), when reviewing a PR, or when the owner asks "do other pages do this?".

## Steps

1. **Name the behavior**, not the screen: for example "rows fade under a pinned header", "card surface", "row height", "spinner placement", "Close button in a sheet".
2. **Registry first.** `python3 tools/pattern_guard.py index`, then read the matching doc in [patterns](../../patterns/README.md). Its *Canonical implementation* table is the expected answer; its *Known debt* table lists the divergences already known.
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
