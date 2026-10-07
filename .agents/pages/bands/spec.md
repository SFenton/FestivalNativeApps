# bands (`/bands`) — spec stub

> **What:** generated placeholder; this page has not been investigated. **Read when:** starting work on it — replace this stub with real web behavior first ([port-page skill](../../skills/port-page/SKILL.md)).

<!-- stub -->

- Guard: `none` · Web source: `FortniteFestivalWeb/src/App.tsx:125` (route declaration)
- Backlog: route `bands` — Apple `absent`, epics `apple-band-flows`; gap text via `python3 tools/parity_backlog.py --list`

## Parity gaps (from the pre-2026-09-27 parity audit)

- Native acceptance: Band lookup. Band search is read-only since the #320 service fix and allowlisted under [service safety](../../platforms/service-safety.md) conditions; Apple, Android and Windows global search use it (Bands and All scopes open the band page). Band detail and the bare band team ranking GETs still write and stay blocked.
