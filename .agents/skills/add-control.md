# Skill: add or port a control

> **What:** the procedure for a control with states, transitions and test IDs. **Read when:** building any control listed in [controls/](../controls/README.md) or a new one.

1. Read the web component and its callers; list every reachable state, what drives it (settings, selection, publication, other controls) and what it drives.
2. Ensure `controls/<id>/spec.md` exists with: source refs, state table (web behavior vs native rule), dependencies, accessibility name/order, test-ID family. For a new control, add it to `contracts/product.json` (`id`, `source`, `states`, `testId`, `spec`) via the orchestrator, then `python3 .agents/_tools/check_docs.py --fix` scaffolds/indexes it.
3. Implement the policy (pure, unit-tested) separately from the view; the view consumes the policy.
4. Accessibility: one accessible element per meaningful unit, state not conveyed by colour alone, stable IDs from the registry.
5. Record platform-specific decisions and open gaps in `controls/<id>/<platform>.md`. Per-state snapshots come in the UX-test phase ([hosted snapshots](../testing/apple/hosted-snapshots.md)).
