# Skills router

> **What:** repeatable step-by-step procedures, stored as agent skills (`<name>/SKILL.md` with `name`/`description` frontmatter, so Copilot CLI loads them on demand from `.agents/skills`). **Read when:** doing one of these tasks; follow the steps rather than re-deriving them.

| Skill | Use for |
|---|---|
| [fix-reported-issue](fix-reported-issue/SKILL.md) | Any tracker issue: intent → precedent → reproduce → fix the pattern → sweep → test → docs → report |
| [consistency-sweep](consistency-sweep/SKILL.md) | Finding every place a behavior lives (all platforms + web) and the canonical one |
| [design-proposal](design-proposal/SKILL.md) | Pausing for an owner decision with prototyped options instead of guessing (Needs Decision) |
| [web-parity-check](web-parity-check/SKILL.md) | Reading the web as the behavior reference: states, constants, copy, timings |
| [port-page](port-page/SKILL.md) | Bringing a web route to a native platform |
| [add-control](add-control/SKILL.md) | Adding or porting a control with states and test IDs |
| [add-endpoint](add-endpoint/SKILL.md) | Adding a keyless service read to the Apple client |
| [screenshot-compare](screenshot-compare/SKILL.md) | Visual smoke check of a native screen against the web app |

TODO(orchestrator): add `add-route` once the `AppRoute` / `AppRouteDestination` seam workflow is settled.
