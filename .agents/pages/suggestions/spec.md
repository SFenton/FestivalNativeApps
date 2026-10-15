# suggestions (`/suggestions`) — spec stub

> **What:** generated placeholder; this page has not been investigated. **Read when:** starting work on it — replace this stub with real web behavior first ([port-page skill](../../skills/port-page/SKILL.md)).

<!-- stub -->

- Guard: `selection` · Web source: `FortniteFestivalWeb/src/App.tsx:110` (route declaration)
- Backlog: route `suggestions` — Apple `absent`, epics `apple-suggestions-compete`; gap text via `python3 tools/parity_backlog.py --list`

## Parity gaps (from the pre-2026-09-27 parity audit)

- Web refs (files under `FortniteFestivalWeb/src/pages/**`): `SuggestionsPage.tsx:68-130`
- Native acceptance: Selection-aware suggestion categories and filters.

## Cross-platform rules

- **R1. A card that names one rival lists only that rival (#656).** "FC These to Beat {rival}!" (`song_rival_near_fc`), "Gain Stars & Beat {rival}" (`song_rival_star_gains`) and "Climb Past {rival}" (`song_rival_pct_push`) build their pool as the web does (closest rival per song/chart; star gains and climb past also need that rival ahead), shuffle it, then take the headline rival from the first candidate the session hasn't shown yet (else the first candidate) and keep only candidates whose closest rival is that account. `shouldEmit` (fresh count), `selectNewFirst` and the rows use the narrowed pool, and the rows drop the per-row rival badge like the other single-rival cards (#29). Native fix of a web bug: the web names the first selected song's closest rival but keeps every row's own. "Stale Songs Your Rivals Are Beating You On" names no rival and stays mixed. Apple reference: `SuggestionGenerator.namedRivalCategory`.
- **Parity for R1.** `tools/windows/suggestion_parity/fixtures/named-rival-parity.json` (`make_named_rival_fixture.py`: two rivals, each the closest on alternating songs, 14 scenarios) and its Apple output `named-rival-parity.expected.json` are the cross-platform R1 case: the pre-R1 generator mixes rivals in 37 of its 45 named cards, the R1 generator in none. `run_parity.py --check` asserts R1 on both fixtures' Apple output and compares each with its expected file. The shared baseline `windows/Festival.Core.Tests/Fixtures/suggestions-parity.expected.json` stays at the pre-R1 output until Windows and Android port R1, so their parity tests keep passing; `pending-ports.json` pins the R1 Apple output's SHA-256 and `--check` accepts the baseline mismatch only for that exact output (`--strict` refuses it). The last lane to port R1 runs `run_parity.py` with no flag, which rewrites both expected files and deletes the record; ports should also run the named-rival fixture through their parity tests. Logic tests: `tools/tests/test_suggestion_parity.py`.
