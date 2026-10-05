---
name: fix-reported-issue
description: End-to-end procedure for fixing a bug or building a feature from a festival-report-tracker issue in FestivalNativeApps. It covers the owner's intent, pattern precedents, blast radius, reproduction, the fix in the canonical component, the sweep, tests, docs and reporting. Use for every tracker issue (bug, feature, follow-up or cross-platform check) before changing code.
---

# Skill: fix a reported issue

> **What:** the order of work for one tracker issue, so a fix matches existing patterns, the web app and platform guidance instead of only the reported screen. **Read when:** starting any tracker issue, before editing code.

## 1. Pin the owner's intent

- Quote the owner's own words (issue body, screenshots, owner comments; newest owner comment wins). The triage summary is an interpretation; when they disagree, the owner's words win.
- Write one sentence: *what the owner will see when this is done*. If you can't, or two readings lead to visibly different designs, go to [design-proposal](../design-proposal/SKILL.md) and stop.

## 2. Find the precedent before the fix

1. `python3 tools/pattern_guard.py index` lists the patterns. Read every pattern doc ([registry](../../patterns/README.md)) that owns the behavior, plus the triage JSON's `patterns`, `precedents` and `blast_radius`.
2. `python3 tools/pattern_guard.py which <file>…` for the files you expect to touch.
3. Run [consistency-sweep](../consistency-sweep/SKILL.md): where else does this behavior exist (other pages, other modals, other platforms, the web)? Which one is canonical, and which ones already solved this exact bug?
4. No pattern matched? Don't stop at the native code: the web's shared components, hooks, styles and `packages/theme` tokens are the pattern ([consistency-sweep](../consistency-sweep/SKILL.md) step 2b).
5. Read the web source for the behavior ([web-parity-check](../web-parity-check/SKILL.md)) and your platform's design guidance (`apple-hig` / `material-3` / `winui-design`), keeping the recommendation strength (must, should, consider).

Classify the change:

| Class | Meaning | Action |
|---|---|---|
| `aligns` | The pattern's rules already describe the fix | Fix it in the canonical component |
| `extends_pattern` | Same rules, one more consumer or state | Extend the canonical component; add the consumer to the doc |
| `diverges_from_pattern` | The ask conflicts with a pattern rule | **Stop**: [design-proposal](../design-proposal/SKILL.md) unless the owner already chose (issue comment or `/choose`) |
| `new_pattern` | No registered pattern owns it and it will recur | Find the web's shared component for it ([consistency-sweep](../consistency-sweep/SKILL.md) step 2b). If the web has one, mirror it as one shared native component and register the pattern (status `current`, web provenance) in the same PR. If the web has none and it touches navigation, chrome, layout or materials, **stop**: [design-proposal](../design-proposal/SKILL.md) |

## 3. Reproduce, then fix the pattern, not the instance

- Reproduce on the reported platform first (simulator/emulator/UIA; fixtures for tests, live public service for evidence).
- Change the **canonical component** so every consumer gets the fix. Never add a second mask, card style, row metric, header or modal treatment in a feature folder. `tools/pattern_guard.py` fails the build for the known regressions.
- Take constants from the web or the pattern doc (one constant per platform), not from what looks right on one screen.

## 4. Sweep the blast radius

- List every consumer of the changed behavior on your platform(s): pages, modals, sheets, demos (first-run replicas), iPad/Duo/macOS variants.
- Fix each one, or record why it is out of scope ("different pattern", "owner limited scope to X").
- Behavior that exists on platforms outside your scope goes in the status file's `blast_radius` with `deferred`. The machine files the cross-platform check from it.

## 5. Test the behavior shift

- Unit tests for new logic; a hosted snapshot or UI journey for visible behavior that would have caught the bug.
- `python3 tools/pattern_guard.py`, `python3 .agents/_tools/check_docs.py --fix`, plus your platform's build and tests.

## 6. Record rules, not history

- Did the pattern's rules change or gain a consumer? Update its doc and `contracts/patterns.json` in the same commit (`python3 tools/pattern_guard.py changed` lists the patterns your diff touched).
- Page/control platform files get a durable rule plus the issue number, never a narrative of attempts.

## 7. Report

Root-cause or approach update: cause, the pattern(s) and precedent you followed, the blast-radius sweep (fixed / deferred), and the platform guidance quote. The status file adds `patterns`, `precedents` and `blast_radius` (see the worker prompt).
