# Docs tooling

> **What:** deterministic checks for the `.agents` structure. **Read when:** a docs check fails, or you add a contract page/control and need its stub and index row.

| Command | Does |
|---|---|
| `python3 .agents/_tools/check_docs.py` | Checks routers, links, contract coverage, platform mixing, headers, generated tables; exit 1 on errors |
| `python3 .agents/_tools/check_docs.py --fix` | Scaffolds missing `spec.md` stubs from `contracts/*.json`, regenerates the `pages/` and `controls/` tables, then checks |
| `python3 -m unittest discover -s .agents/_tools` | Self-tests for the checker |

Rules it enforces: [workflow/docs-conventions.md](../workflow/docs-conventions.md). Source: `check_docs.py` (stdlib only).
