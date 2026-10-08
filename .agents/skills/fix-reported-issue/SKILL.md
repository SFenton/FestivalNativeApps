---
name: fix-reported-issue
description: End-to-end procedure for fixing a bug or building a feature from a festival-report-tracker issue in FestivalNativeApps. It covers the owner's intent, pattern precedents, blast radius, reproduction, the fix in the canonical component, the sweep, tests, docs and reporting. Use for every tracker issue (bug, feature, follow-up or cross-platform check) before changing code.
---

# Skill: fix a reported issue

> **What:** the order of work for one tracker issue, so a fix matches existing patterns, the web app and platform guidance instead of only the reported screen. **Read when:** starting any tracker issue, before editing code.

## 1. Pin the owner's intent

- Quote the owner's own words (issue body, screenshots, owner comments; newest owner comment wins). The triage summary is an interpretation; when they disagree, the owner's words win.
- Write one sentence: *what the owner will see when this is done*. If two readings lead to visibly different designs, decide and document which one with [design-decision](../design-decision/SKILL.md).

## 2. Find the precedent before the fix (the design ladder)

Follow [consistency-sweep](../consistency-sweep/SKILL.md) rung by rung, starting from the triage JSON's `patterns`, `precedents` and `blast_radius`:

1. **Registered pattern?** `python3 tools/pattern_guard.py index` / `which <file>`, then the owning [pattern](../../patterns/README.md) docs.
2. **Undocumented native pattern?** Search all three platforms and git history for the same behavior. A shared component, or the same behavior solved in several places, gets consolidated and registered.
3. **Web pattern?** The web page's component, hook, styles and `packages/theme` tokens define the behavior ([web-parity-check](../web-parity-check/SKILL.md)).
4. **Platform guidance.** `apple-hig` / `material-3` / `winui-design`, keeping each rule's strength (must, should, consider). Resolve conflicts with the sweep's precedence table: platform *musts* and owner decisions win, web behavior beats native copies, native chrome beats web chrome, and web-vs-*should* conflicts are documented design decisions (you decide; the owner may override).
5. **Implement**, documenting any design decision ([design-decision](../design-decision/SKILL.md)).

Classify the change:

| Class | Meaning | Action |
|---|---|---|
| `aligns` | The pattern's rules already describe the fix | Fix it in the canonical component |
| `extends_pattern` | Same rules, one more consumer or state | Extend the canonical component; add the consumer to the doc |
| `diverges_from_pattern` | The ask conflicts with a pattern rule | Follow the owner's explicit choice if there is one; otherwise decide and document it with [design-decision](../design-decision/SKILL.md), then implement |
| `new_pattern` | No registered pattern owns it and it will recur | Use the native or web precedent the ladder found (rungs 2–3). If the web has one, mirror it as one shared native component and register the pattern (status `current`, web provenance) in the same PR. If the web has none and it touches navigation, chrome, layout or materials, decide and document it with [design-decision](../design-decision/SKILL.md) |

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
- An **accessibility test** on every platform you changed UI on: labels/roles/state, reading order, target size and text scaling for the changed region, using that platform's mechanism ([accessibility tests with every change](../../testing/strategy.md#accessibility-tests-with-every-change)). Update existing ones when they already cover the behavior. Report the test names in the status file's `tests`. Exempt only logic, data or copy-only changes, with the reason in the PR.
- Your new tests must run in CI (`apple-ci`, `android-device`, `windows-ui`): put them where those workflows pick them up.
- `python3 tools/pattern_guard.py`, `python3 .agents/_tools/check_docs.py --fix`, plus your platform's build and tests.

## 6. Record rules, not history

- Did the pattern's rules change or gain a consumer? Update its doc and `contracts/patterns.json` in the same commit (`python3 tools/pattern_guard.py changed` lists the patterns your diff touched).
- Page/control platform files get a durable rule plus the issue number, never a narrative of attempts.

## 7. Report

Root-cause or approach update: cause, the pattern(s) and precedent you followed, the blast-radius sweep (fixed / deferred), and the platform guidance quote. The status file adds `patterns`, `precedents` and `blast_radius` (see the worker prompt).
