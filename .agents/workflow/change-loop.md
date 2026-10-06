# Change loop

> **What:** the per-change steps every lane follows. **Read when:** starting a feature or fix.

1. **Find the precedent first.** `python3 tools/pattern_guard.py index` / `which <file>`, then the owning [pattern](../patterns/README.md) docs and a [consistency-sweep](../skills/consistency-sweep/SKILL.md): where else does this behavior live, and which component is canonical? Then read the web source for the page/control (`$FST_WEB_SRC`, or `~/fst-agents/repos/FortniteFestivalLeaderboardScraper/FortniteFestivalWeb/src` on agent hosts) and its `.agents` spec ([pages](../pages/README.md), [controls](../controls/README.md)). Identify inputs, states, dependent controls and navigation edges. Apple HIG wins over Fluent where they conflict.
2. Implement in your lane's folders, through the canonical component (fix the pattern, not the instance; sweep its consumers). A change that diverges from a pattern rule or platform guidance is a documented design decision ([design-decision](../skills/design-decision/SKILL.md)); the owner may override. Add unit tests for new non-UX logic as you go; run only new/changed tests while iterating ([testing phases](../testing/strategy.md)).
3. Check visually: `python3 tools/ios_sim.py build`, then `shot --tab … --route …`; compare to the web app at the same viewport ([screenshot-compare](../skills/screenshot-compare/SKILL.md)).
4. Record durable findings as rules in the right file: shared behavior → the pattern doc + `contracts/patterns.json`; page behavior → `spec.md`; platform decisions/gotchas → `<platform>.md`. `python3 tools/pattern_guard.py` must pass. No run logs or pass-count narratives.
5. Commit, integrate with `tools/lane_integrate.sh`, report back.

Make a deterministic tool or fixture for any operation you repeat, rather than more prose. Production access, signing, asset licensing, deployment and publication have separate approval gates.
