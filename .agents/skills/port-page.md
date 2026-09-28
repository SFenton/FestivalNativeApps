# Skill: port a page

> **What:** the procedure for bringing one web route to a native platform without losing states. **Read when:** starting work on any page in [pages/](../pages/README.md).

1. **Spec first.** Open `pages/<id>/spec.md`. If it is a stub, read the web route (guards, backing API, controls, transitions, modals, page-level preferences) and replace the stub: inputs, states, nav edges, accessibility order, fully qualified source refs ([citation rules](../workflow/source-of-truth.md)). Distinguish read-only requests from side effects ([service safety](../platforms/service-safety.md)).
2. **Contracts.** Add control specs and test IDs to `contracts/product.json` (orchestrator-owned: request it in your report if you are a lane); `python3 tools/verify_product.py` catches duplicates and broken references. Add fixture data for loaded / empty / error and every reachable control state ([fixtures](../testing/fixtures.md)).
3. **Implement** native navigation and semantics in your lane's folders, keeping branded geometry/palette precise and system chrome native ([design](../design/README.md)). Unit-test new logic as you go.
4. **Visual smoke**: [screenshot-compare](screenshot-compare.md) at portrait and landscape; record intentional deviations in `pages/<id>/<platform>.md`.
5. **Docs**: behavior → `spec.md`; platform decisions, gotchas and open gaps → `<platform>.md`; run `python3 .agents/_tools/check_docs.py --fix`.
6. **Later phases** (feature complete → app complete): UX tests, accessibility, VoiceOver ([strategy](../testing/strategy.md)). Mark `implemented` only when every platform has evidence for every state; `--strict` certifies.
