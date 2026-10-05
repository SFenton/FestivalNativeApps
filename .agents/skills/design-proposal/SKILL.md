---
name: design-proposal
description: Pause unattended work and give the owner a concrete design decision (2–3 prototyped options with screenshots, platform-guideline quotes with their strength, web reference and a recommendation) instead of guessing. Use when the request is ambiguous between visibly different designs, diverges from a pattern rule, changes navigation/chrome/materials, or departs from Apple HIG, Material 3 or Fluent guidance.
---

# Skill: design proposal (Needs Decision)

> **What:** how an unattended worker turns a design question into an owner decision the release machine can resume from. **Read when:** [fix-reported-issue](../fix-reported-issue/SKILL.md) step 1 or 2 says stop, triage set `decision.required`, or you'd otherwise pick between designs yourself.

## When it is required

- Triage JSON has `"decision": {"required": true, …}`.
- The change is `diverges_from_pattern` or alters a pattern rule ([registry](../../patterns/README.md)).
- Navigation chrome, page-tool placement, materials, or a platform-guideline deviation the owner hasn't already chosen in an issue comment.
- Two faithful readings of the owner's words give visibly different results.

The owner choosing something against a platform recommendation is allowed. What isn't allowed is the agent choosing it silently.

## Steps

1. **Frame the question** in one sentence, quoting the owner's words.
2. **Gather the constraints:** the pattern rules involved, the web behavior (file and constants), and platform guidance from the skill (`apple-hig` routed pages, `material-3` references, `winui-design`). Quote each rule and label its strength: **must** (requirement), **should** (recommendation), **consider**.
3. **Prototype 2–3 options** in your worktree (no PR, nothing merged; push only to your `report/<n>` branch if useful). Option A is usually the platform default or existing pattern, option B the literal ask, and option C a compliant middle ground when one exists.
4. **Capture evidence** for each option with the repo tools (`ios_sim.py shot` / Android / Windows capture) against the live public service. Use the same screen and state for every option.
5. **Post the proposal** with `fst-issue-update proposal --issue <n> --role <role> --body-file <md> --media <file>::<caption> …`, using this body:

```markdown
**Decision needed:** <question, quoting the owner>

| Option | What you'd see | Guidance (strength) | Web parity | Trade-offs |
|---|---|---|---|---|
| A | … | HIG Toolbars: "…" (should) | … | … |
| B | … | … | … | … |

**Recommendation:** <A/B/C> because …
Reply `/choose A` (or B, C), optionally followed by notes.
```

6. **Finish blocked:** status file `"state": "blocked"`, with `"blocked_reason": "decision_required: <question>"` and `"decision": {"question": "…", "options": [{"key": "A", "summary": "…"}, …], "recommendation": "A"}`. The machine labels the issue **Needs Decision**. When the owner replies `/choose X`, you are relaunched with the choice.
7. **After the choice:** implement it, then record it as a pattern rule or approved variant (doc and `contracts/patterns.json`), with the owner's choice as provenance.
