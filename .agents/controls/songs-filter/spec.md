# Songs Filter (`fst.songs.filter`) — spec

> **What:** platform-neutral web Filter behavior, predicate semantics and native safety rules. **Read when:** changing Songs filtering on any platform. Platform notes: [ios.md](ios.md), [macos.md](macos.md), [android.md](android.md), [windows.md](windows.md).

Source: `FortniteFestivalWeb/src/pages/songs/SongsPage.tsx:587-618,1122-1136`, General section from web `6415d3e3`, `e5624a17`, `ec9f957b`, `aebd02d2` (`FilterModal.tsx` `CatalogBucketToggles`, `useFilteredSongs.ts` `getSongDecade`/`getSongDurationBucket`/`getDurationFilterBuckets`, `songSettings.ts` `migrateShopAvailability`), `FortniteFestivalWeb/src/pages/songs/modals/FilterModal.tsx:77-132,155-270,305-321`, `FortniteFestivalWeb/src/hooks/data/useFilteredSongs.ts:103-182`, `FortniteFestivalWeb/src/utils/songSettings.ts:92-124,155-174`. Audit ref: `FilterModal.tsx:169-373`.

## Web behavior

- The Filter action is always offered. Without a selected profile the modal shows **only General**; with one the order is General, Global Score & FC, Individual Score & FC, then Selected Instrument Filters (season, percentile, stars, intensity), plus band/member with a band. Band conflicts block Apply.
- **General** ("General filters that apply to all songs."): **Year** ("Filter songs by their release decade.": one toggle per catalogue decade, ascending, "1980s"), **Duration** ("Filter songs by their duration.": "Under 1 Minute", "1-2 Minutes" … "9-10 Minutes", plus "10+ Minutes" only when a catalogue song lasts ≥ 10 minutes), both with Select All / Clear All; **Item Shop** ("Filter songs by whether they are available in the Item Shop.": "Available in Item Shop" / "Not Available in Item Shop", only while the Shop is shown); **Double Bass** ("Filter songs that have or don't have double bass charts for Pro Drums.": "Double Bass Support" / "No Double Bass Support"). Every option starts on.
- Draft semantics: changes stay in the modal until Apply; changed Cancel asks to discard; Reset clears the draft and still needs Apply.
- Confirmed deselect clears all filters (General included) and the instrument, and a single-instrument sort reverts to Title (`resetSongSettingsForDeselect` + `normalizeSongSettings`); a player-to-player switch preserves them (`shouldResetSongSettingsForProfileChange` resets only when a profile goes away or changes between player and band). No "paused until a player is selected" notice exists. Hidden Shop omits Shop controls.

## Predicates

- Pipeline: search → chart filter → General (Double Bass, Year, Duration) → Item Shop → selected-player score → Sort.
- Year: decade = ⌊year / 10⌋ × 10 for year > 0; Duration: bucket = min(10, ⌊seconds / 60⌋) for seconds > 0. Once any key is hidden, songs without that metadata are excluded too. Select All clears the hidden set; Clear All hides every listed key.
- Double Bass filters by the catalogue's `doubleBassSupported`: with one option off, keep only songs whose value matches the remaining option (`null` is excluded); both off show nothing.
- Item Shop: "Available" means a current offer (leaving-tomorrow offers count as available); both off show nothing; counts as active only while the Shop is shown. Saved retired In Shop / Leaving Tomorrow choices migrate to Available only. Requires a validated feed from the **same observed publication** as catalogue and session; a genuinely empty feed filters to No Results; an absent/failed feed or mismatch **pauses** with a visible notice (never synthesized empty membership).
- Score/FC: four checks per chart (Has/Missing Score, Has/Missing FC). **AND within one chart, OR across active charted instruments**; global toggles set/clear visible charts only. FC follows the explicit flag. Hidden charts stay saved but inactive (disclosed); applying removes hidden choices like source sanitization.
- Score checks apply only when catalogue, proven player response and session share the observed publication; loading, 202, failure, publication change or unsupported invalid-score substitution pause them. Public Shop filtering stays independent of score loading.
- Saved predicates are bounded, typed, deterministic JSON scoped to visible charts; corrupt saved data blocks the success view until an explicit Reset.

## Native deviations (all platforms)

- A valid 200 **empty** score index still permits Missing Scores (web gates on `allScoreMap.size > 0`): correctness fix.
- On deselect Apple and Android clear score predicates and Selected Instrument Filters but keep the public General choices. Windows follows the web since #359 and resets every filter. A saved Item Shop choice stays while the Shop is hidden (inert; Android shows a paused notice) until Reset. Natives hide the Item Shop group while the Shop is hidden (Apple: a saved choice shows a paused notice). Open parity decisions.
- On deselect, Apple and Windows clear score predicates and Selected Instrument Filters but keep the public General choices; Android follows the web and resets every filter (owner, #359: "follow web pattern of resetting filters/sorts … when profiles or bands are deselected"). A saved Item Shop choice stays while the Shop is hidden (inert; Android shows a paused notice) until Reset. Natives hide the Item Shop group while the Shop is hidden (Apple: a saved choice shows a paused notice). Open parity decisions.
- Web filters nothing when Item Shop is restricted but no Shop snapshot exists; Apple pauses with a visible notice instead (publication invariant).

IDs: `fst.songs.filter{,.form,.title,.reset,.cancel,.apply}` (Apple closes with `.done`), `fst.songs.filter.general`, `fst.songs.filter.{year,duration}[.select-all|.clear-all|.<key>]`, `fst.songs.filter.{shop,shop-available,shop-unavailable}`, `fst.songs.filter.double-bass[.supported|.unsupported]`, `fst.songs.filter.score-sections`, `fst.songs.filter.score.{global,instrument,chart}.*`, `fst.songs.{filter-paused,score-filter-paused,score-filter-hidden}`, `fst.songs.filter-{invalid,reset-invalid}`, `fst.songs.filter.save-error`.
