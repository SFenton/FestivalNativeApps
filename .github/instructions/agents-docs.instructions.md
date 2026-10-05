---
applyTo: ".agents/**,contracts/**,AGENTS.md"
---

# Agent docs and contracts

- Write **rules, not history**. Each design/page/control/pattern doc leads with durable, numbered or bulleted rules. Issue numbers are provenance, never narrative ("first we tried…"). No run logs or pass counts. Use `TODO(orchestrator): …` instead of guessing.
- A behavior shared by two or more pages or platforms belongs in a [pattern](../../.agents/patterns/README.md) (`.agents/patterns/<id>.md` + `contracts/patterns.json`), and page/control docs link to it instead of restating it. Changing a pattern rule needs an owner decision and a `Supersedes:` note. Sweep every platform listed in the pattern.
- Headings must not mix platforms; follow [docs-conventions](../../.agents/workflow/docs-conventions.md). Skills live in `.agents/skills/<name>/SKILL.md` with `name`/`description` frontmatter.
- Run `python3 .agents/_tools/check_docs.py --fix` and `python3 tools/pattern_guard.py` before committing.
