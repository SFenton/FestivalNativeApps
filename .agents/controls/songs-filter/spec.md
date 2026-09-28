# Songs Filter (`fst.songs.filter`) — spec

> **What:** platform-neutral web Filter behavior, predicate semantics and native safety rules. **Read when:** changing Songs filtering on any platform. Platform notes: [ios.md](ios.md).

Source: `FortniteFestivalWeb/src/pages/songs/SongsPage.tsx:587-618,1122-1136`, `FortniteFestivalWeb/src/pages/songs/modals/FilterModal.tsx:77-132,155-270,305-321`, `FortniteFestivalWeb/src/hooks/data/useFilteredSongs.ts:103-182`, `FortniteFestivalWeb/src/utils/songSettings.ts:92-124,155-174`. Audit ref: `FilterModal.tsx:169-373`.

## Web behavior

- The mobile Filter action requires loaded player data or a selected band.
- Sections: Shop (In Shop, Leaving Tomorrow), score / FC (global + per chart), season, percentile, stars, difficulty/intensity, score threshold, selected instrument, band/member. Band conflicts block Apply.
- Draft semantics: changes stay in the modal until Apply; changed Cancel asks to discard; Reset clears the draft and still needs Apply.
- Confirmed deselect clears all filters; a player-to-player switch preserves them. Hidden Shop omits Shop controls.

## Predicates

- Pipeline: search → chart filter → Shop → selected-player score → Sort.
- Shop: Leaving Tomorrow implies membership; both toggles on keep leaving offers. Requires a validated feed from the **same observed publication** as catalogue and session; a genuinely empty feed filters to No Results; an absent/failed feed or mismatch **pauses** with a visible notice (never synthesized empty membership).
- Score/FC: four checks per chart (Has/Missing Score, Has/Missing FC). **AND within one chart, OR across active charted instruments**; global toggles set/clear visible charts only. FC follows the explicit flag. Hidden charts stay saved but inactive (disclosed); applying removes hidden choices like source sanitization.
- Score checks apply only when catalogue, proven player response and session share the observed publication; loading, 202, failure, publication change or unsupported invalid-score substitution pause them. Public Shop filtering stays independent of score loading.
- Saved predicates are bounded, typed, deterministic JSON scoped to visible charts; corrupt saved data blocks the success view until an explicit Reset.

## Native deviations (all platforms)

- A valid 200 **empty** score index still permits Missing Scores (web gates on `allScoreMap.size > 0`): correctness fix.
- On deselect natives clear only score predicates and keep the public Shop choice (re-applied after an explicit reselection); natives keep disabled Shop toggles + Reset when Shop is hidden so saved choices stay clearable. Open parity decisions.

IDs: `fst.songs.filter{,.form,.title,.in-shop,.leaving,.reset,.cancel,.apply}`, `fst.songs.filter.score-sections`, `fst.songs.filter.score.{global,instrument,chart}.*`, `fst.songs.{filter-paused,score-filter-paused,score-filter-hidden}`, `fst.songs.filter-{invalid,reset-invalid}`, `fst.songs.filter.save-error`.
