---
name: design-decision
description: Make a design decision knowingly and document it, instead of guessing silently. Weigh 2–3 concrete options with the design ladder (pattern registry, undocumented native pattern, web, platform guidance) and its precedence table, choose, record the choice and rationale on the issue and in the pattern doc, then implement. Use when a request is ambiguous between visibly different designs, diverges from a pattern rule, changes navigation/chrome/materials, or departs from Apple HIG, Material 3 or Fluent guidance.
---

# Skill: design decision

> **What:** how an unattended worker makes a design call well: options, evidence, choice, record. **Read when:** [fix-reported-issue](../fix-reported-issue/SKILL.md) or [consistency-sweep](../consistency-sweep/SKILL.md) reaches a *decision* row of the precedence table, triage set `decision.required`, or you would otherwise pick between designs without saying so.

**Mode (operator, 2026-10-05): decisions are automated.** You decide; nobody will answer questions. The owner reviews the documented decision and may override it with `/choose <option>`. (The release machine's `decisions.mode: owner` switches to proposing and waiting instead; see step 6.)

## When it applies

- Triage JSON has `"decision": {"required": true, …}`.
- The change is `diverges_from_pattern`, alters a pattern rule ([registry](../../patterns/README.md)), or is a native invention with no native or web precedent in navigation, chrome, layout or materials.
- Web behavior conflicts with a platform **should** or **consider** recommendation.
- Two faithful readings of the owner's words give visibly different results.

An explicit owner choice (issue text, owner comment, `/choose`, or an approved variant in a pattern doc) is already a decision: follow it.

## Steps

1. **Frame the question** in one sentence, quoting the owner's words.
2. **Gather the evidence** from the design ladder: the pattern rules, any undocumented native precedent, the web behavior (file and constants), and platform guidance from the skill (`apple-hig` routed pages, `material-3` references, `winui-design`). Quote each rule and label its strength: **must**, **should** or **consider**.
3. **List 2–3 options.** A is usually the existing pattern or the platform default, B the literal ask, and C a compliant middle ground when one exists. When the difference is visual and cheap to show, prototype the options in your worktree and capture comparable screenshots with the repo tools (same screen and state).
4. **Choose with the precedence table** ([consistency-sweep](../consistency-sweep/SKILL.md#precedence-when-the-rungs-disagree)):
   - A platform *must* always wins.
   - An explicit owner choice wins next.
   - Web behavior beats undocumented native copies.
   - Native chrome beats web chrome.
   - Between a web behavior and a platform recommendation, prefer the option that keeps the owner's stated intent and web semantics while using native, compliant chrome. When still tied, prefer the existing pattern (least churn).
5. **Record and implement:**
   - Post `fst-issue-update decision --issue <n> --role <role> --body-file <md> [--media <file>::<caption> …]` using the body below.
   - Record the choice in the owning pattern doc (rule or *approved variant*) as `Agent decision (#<n>, <date>): …; owner may override`, plus `contracts/patterns.json` when canonical files or guards change.
   - Implement it on your branch and finish `done`.

```markdown
**Decision:** <question, quoting the owner>

| Option | What you'd see | Guidance (strength) | Web / pattern precedent | Trade-offs |
|---|---|---|---|---|
| A | … | HIG Toolbars: "…" (should) | … | … |
| B | … | … | … | … |

**Chose:** <A/B/C> because … (precedence rule that decided it)
Reply `/choose <option>` to override.
```

6. **Owner mode only** (`decisions.mode: owner`): post `fst-issue-update proposal …` with the same table and a recommendation instead, then finish `blocked` with `"blocked_reason": "decision_required: <question>"` and `"decision": {"question": "…", "options": [{"key": "A", "summary": "…"}], "recommendation": "A"}`. The issue waits in **Needs Decision** until `/choose`.
