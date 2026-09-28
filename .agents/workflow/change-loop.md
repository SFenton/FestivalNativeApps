# Change loop

> **What:** the per-change steps every lane follows. **Read when:** starting a feature or fix.

1. Read the web source for the page/control (`~/repos/FortniteFestivalLeaderboardScraper/FortniteFestivalWeb/src`) and its `.agents` spec ([pages](../pages/README.md), [controls](../controls/README.md)). Identify inputs, states, dependent controls and navigation edges. Apple HIG wins over Fluent where they conflict.
2. Implement in your lane's folders. Add unit tests for new non-UX logic as you go; run only new/changed tests while iterating ([testing phases](../testing/strategy.md)).
3. Check visually: `python3 tools/ios_sim.py build`, then `shot --tab … --route …`; compare to the web app at the same viewport ([screenshot-compare](../skills/screenshot-compare.md)).
4. Record durable findings in the right file: behavior → `spec.md`; platform decisions/gotchas → `<platform>.md`. No run logs or pass-count narratives.
5. Commit, integrate with `tools/lane_integrate.sh`, report back.

Make a deterministic tool or fixture for any operation you repeat, rather than more prose. Production access, signing, asset licensing, deployment and publication have separate approval gates.
