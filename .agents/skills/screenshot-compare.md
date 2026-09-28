# Skill: screenshot compare (visual smoke)

> **What:** quick side-by-side of a native screen and the web app at the same viewport. **Read when:** you changed UI and want the visual-smoke check from the [testing phases](../testing/strategy.md).

1. Native: `python3 tools/ios_sim.py build`, then `python3 tools/ios_sim.py shot --out /tmp/<name>.png --tab <tab> [--route <route>] [--device ipad]` (serialized; add `--env FST_API_BASE_URL=http://127.0.0.1:8765` with a running [mock service](../testing/fixtures.md) for deterministic data).
2. Web: run the matching case in the [PWA harness](../testing/web-reference.md) at 390×844 (phone) or 820×1180 (tablet), or open festivalscoretracker.com at the same viewport for a live look.
3. Compare structure, spacing, hierarchy and states — not system chrome pixels. Apple HIG wins over Fluent; Fluent over web cosmetics.
4. Record intentional deviations in `pages/<id>/<platform>.md`; keep screenshots in private evidence, never in the repo.
