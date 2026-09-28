# Docs conventions

> **What:** the rules that keep `.agents` small, split by platform and ≤2 hops from the root router. **Read when:** adding, splitting or moving any `.agents` file. Enforced by [`_tools/check_docs.py`](../_tools/README.md).

## Layout

```
.agents/README.md            router (task → file, platform → files)
.agents/<area>/README.md     one table routing to every file/subfolder in the area
.agents/pages/<id>/          spec.md (platform-neutral) + ios.md|ipados.md|duo.md|macos.md|android.md|windows.md
.agents/controls/<id>/       same shape; <id> = product.json control id
.agents/design|platforms|testing/<platform>/…   per-platform material
```

| Rule | Detail |
|---|---|
| Header | Line 1 `# Title`; next non-empty line `> **What:** … **Read when:** …` (1–3 lines) |
| One platform per file | `spec.md` is platform-neutral (web behavior, wire, states, nav edges, test matrix, cross-platform native corrections). Everything Apple/Android/Windows-specific goes in the platform file. Form factors split further (iPhone `ios.md`, `ipados.md`, `duo.md`, `macos.md`) |
| When to make a folder | A platform gets a folder once it has ≥2 files (e.g. `design/apple/`); a single file stays flat (`design/android.md`) with a form-factor table inside |
| Routers | Every folder has `README.md` linking every child. Exception: `pages/<id>/` and `controls/<id>/` are routed by the generated table in `pages/README.md` / `controls/README.md` |
| Generated tables | Do not hand-edit between the `BEGIN/END GENERATED` markers; run `python3 .agents/_tools/check_docs.py --fix` (also scaffolds missing `spec.md` stubs for new contract IDs) |
| Size | Soft budget 200 non-empty lines per file; split by topic before growing |
| Content | Durable rules, decisions, gotchas and open gaps — as tables/bullets. **No run logs**, pass counts (`10/10 on each`) or dated coverage narratives: put measured numbers in one "last measured" row, and rely on git history for the rest |
| Citations | Fully qualified web/service line refs ([source-of-truth](source-of-truth.md)) |
| Safety rules | Live only in [platforms/service-safety.md](../platforms/service-safety.md); link, don't copy |
| Unknowns | Write `TODO(orchestrator): …` rather than guessing |

## Checks (`python3 .agents/_tools/check_docs.py`)

Routers exist and link all children · relative links resolve (also `AGENTS.md`, `README.md`) · every contract page/control has `spec.md` and every `product.json` `spec` path exists · headings do not mix platforms (`spec.md`: none; platform files: own platform only; others: at most one) · header line present · generated tables fresh. Warnings: >200 lines, topic folders not in contracts, unexpected file names.

CI runs `python3 .agents/_tools/check_docs.py` and its self-tests (`.github/workflows/contracts.yml`).
