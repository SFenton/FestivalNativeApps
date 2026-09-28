# Source of truth, citations and parity inventory

> **What:** where behavior comes from and how it is pinned. **Read when:** citing web/service source lines, refreshing snapshots, or checking route status.

| Artifact | Role | Command |
|---|---|---|
| Web + service source (`SFenton/FortniteFestivalLeaderboardScraper`) | Behavior truth. Independently owned **dirty** worktree: read only; never reset, commit or amend it | — |
| [contracts/source-snapshot.json](../../contracts/source-snapshot.json) | Hashes of reviewed source files (base list + backlog refs + every fully qualified `.agents` citation) | `python3 tools/source_snapshot.py --source <FST-repo>` (check); `--write` after a re-review |
| [contracts/product.json](../../contracts/product.json) | 24 routes, controls, states, test IDs, `spec` paths | `python3 tools/verify_product.py` (`--strict` = all platforms certified) |
| [contracts/parity-backlog.json](../../contracts/parity-backlog.json) | Per-route native gap + 18 feature epics with deps | `python3 tools/parity_backlog.py --list` |

## Citation rules

- Cite `FortniteFestivalWeb/src/…/File.tsx:12-34` (or `FSTService/…`, `packages/core|theme/…`) **fully qualified**: `source_snapshot.py` collects these from every `.agents/**/*.md` and validates line bounds. Short `src/…` refs are not checked.
- Removing the only citation of a file, or adding a new cited file, changes the pinned set: rerun the snapshot check and `--write` when intended.
- A valid line number does **not** prove the cited semantics; re-read the source. A commit hash alone does not represent the dirty worktree.
- Mark a contract status `pending` until every documented reachable state and nav edge has native evidence. Docs alone never certify a platform.
