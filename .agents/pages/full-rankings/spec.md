# full-rankings (`/leaderboards/all`) — spec stub

> **What:** generated placeholder; this page has not been investigated. **Read when:** starting work on it — replace this stub with real web behavior first ([port-page skill](../../skills/port-page.md)).

<!-- stub -->

- Guard: `none` · Web source: `FortniteFestivalWeb/src/App.tsx:122` (route declaration)
- Backlog: route `full-rankings` — Apple `absent`, epics `apple-rankings`; gap text via `python3 tools/parity_backlog.py --list`

## Parity gaps (from the pre-2026-09-27 parity audit)

- Web refs (files under `FortniteFestivalWeb/src/pages/**`): `FullRankingsPage.tsx:169-244`
- Native acceptance: Full-scope paginated rankings with selection spotlight and metrics.

## Live data quirk (2026-09-28)

Production rankings can include an **anonymous row**: empty `accountId`, no `displayName` (seen at Lead total-score rank 15). Every platform must decode it, show "Unknown User", make it non-interactive, and give it a unique list identity — never reject the page.
