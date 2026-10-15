# suggestions (`/suggestions`) — spec stub

> **What:** generated placeholder; this page has not been investigated. **Read when:** starting work on it — replace this stub with real web behavior first ([port-page skill](../../skills/port-page/SKILL.md)).

<!-- stub -->

- Guard: `selection` · Web source: `FortniteFestivalWeb/src/App.tsx:110` (route declaration)
- Backlog: route `suggestions` — Apple `absent`, epics `apple-suggestions-compete`; gap text via `python3 tools/parity_backlog.py --list`

## Parity gaps (from the pre-2026-09-27 parity audit)

- Web refs (files under `FortniteFestivalWeb/src/pages/**`): `SuggestionsPage.tsx:68-130`
- Native acceptance: Selection-aware suggestion categories and filters.

## Cross-platform rules

- **R1. A card that names one rival lists only that rival (#656).** "FC These to Beat {rival}!" (`song_rival_near_fc`), "Gain Stars & Beat {rival}" (`song_rival_star_gains`) and "Climb Past {rival}" (`song_rival_pct_push`) build their pool as the web does (closest rival per song/chart; star gains and climb past also need that rival ahead), shuffle it, then take the headline rival from the first candidate the session hasn't shown yet (else the first candidate) and keep only candidates whose closest rival is that account. `shouldEmit` (fresh count), `selectNewFirst` and the rows use the narrowed pool, and the rows drop the per-row rival badge like the other single-rival cards (#29). Native fix of a web bug: the web names the first selected song's closest rival but keeps every row's own. "Stale Songs Your Rivals Are Beating You On" names no rival and stays mixed. Apple reference: `SuggestionGenerator.namedRivalCategory`; the shared parity fixture (`tools/windows/suggestion_parity/run_parity.py`) follows it.
