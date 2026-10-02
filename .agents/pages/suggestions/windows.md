# Suggestions — Windows notes

> **What:** Windows (WinUI 3) implementation state, parity evidence and decisions for the Suggestions section. **Read when:** changing Suggestions on Windows or its generator port. Behavior reference: [ios.md](ios.md) (the Apple port is the source of truth until [spec.md](spec.md) is promoted).

## Implemented

| Piece | File (under `windows/`) |
|---|---|
| Generator: line-for-line C# port of the Apple `SuggestionGenerator` (Mulberry32, pipeline list order, emit table + skip streaks, `selectNewFirst`, decade variants, `near_max_*`, all ten `song_rival_*` families, late rival splice) | `Festival.Core/Domain/SuggestionGenerator.cs`, `SuggestionRng.cs` |
| Models: category types (Apple raw values as persisted keys), `SuggestionScore` input (decoupled from the wire `PlayerScore`; `SuggestionScore.Index` adapts the session index), items, categories, season fallback | `Festival.Core/Domain/SuggestionModels.cs` |
| `RivalDataIndex.Build` over `GET /api/player/{id}/rivals/all` (win-rivals' `RivalsAllResponse`) | `Festival.Core/Domain/SuggestionRivalData.cs` |
| Persisted filter (instrument visibility, global + per-instrument type toggles, web cascade rules) and `SuggestionCategoryFilter` | `Festival.Core/Domain/SuggestionFilterSettings.cs` |
| Filter persistence as its own file `%LOCALAPPDATA%\FestivalScoreTracker\suggestions-filter.json` (untouched filter = no file; corrupt/oversize = defaults) | `Festival.Core/Data/SuggestionFilterStore.cs` |
| Row metadata by category key (web `getRowLayout`: rival, UNFC accuracy, season, percentile tier, stars, instrument chips) and Narrator names | `Festival.Core/Domain/SuggestionRowPresentation.cs` |
| Page model: web batching (10 first, 6 per trigger, endless `resetForEndless` remix, 1,000-category cap + Start New Mix), one generator per (player, catalogue, score publication), rivals fetched in parallel and spliced when they answer, filter applied without regenerating | `Festival.Core/ViewModels/SuggestionsViewModel.cs`, `SuggestionsFilterDraft.cs` |
| Page: virtualized `ListView` of Fluent cards; third-from-last realized card loads the next batch; filter `DropDownButton` flyout (Instruments / General expanders, collapsed like the web accordions; Instrument-Specific uses the web **Instrument Selector** with `DeferSelection`, nothing selected on opening, the chart's type switches expanding under it; switches apply live; Reset is the web Modal's full-width red button (batch 7.10); gold tint when active). Rows end with an in-card chevron (›, batch 7.3). The title and Filter action stay hidden behind the spinner until the first cards are ready, then fade in with them (web `headerStagger`, batch 6.41). Each card's title, description and category instrument (36 epx) sit above the card; rows follow the web `CategoryCard` (10 × 24 epx padding, separators between rows only, 34 epx instrument chips with 20 epx icons, 20 epx star images for star-gain categories, marquee titles on hover/focus); cards stagger in | `Festival.App/Pages/SuggestionsPage.xaml(.cs)`, `Festival.App/Controls/SuggestionSongRow.cs` |

States: no player, loading, syncing (202), failed (catalogue or profile; Retry), empty (no suggestions / filtered with Reset Filters), loaded, end-of-mix footer. Rows push Song Detail with the row's (or category's) chart.

## Apple parity evidence

- `tools/windows/suggestion_parity/run_parity.py` compiles the **unmodified** Apple `SuggestionGenerator.swift`, `SuggestionModels.swift`, `SuggestionRivalData.swift`, `RivalsAll.swift`, `ScoreFormatting.swift` and the Instrument/Song part of `SongCatalog.swift` with a small `Shim.swift` (`PlayerScore` fields) and `main.swift`, runs six fixed-seed scenarios over `windows/Festival.Core.Tests/Fixtures/suggestions-parity.json` (140 synthetic songs, 555 scores, 3-combo rivals) and writes `suggestions-parity.expected.json`. It runs with the Swift toolchain on Windows (`winget install Swift.Toolchain --scope user`, installed on `sfenton-music` 2026-09-28) or on the Mac; `--check` compares without rewriting.
- `SuggestionParityTests` asserts Mulberry32 doubles/ints for four seeds, the rival index, and every page of every scenario (228 pages, including endless remixes, late rival data, season 0, `uint.MaxValue` seed) match exactly: keys, titles, descriptions, types, instruments, row IDs, stars, percent, FC, percentile labels and rival annotations. Regenerate the fixture with `make_fixture.py`, then `run_parity.py`, whenever either port changes.
- Order-sensitive details the port must keep: `InstrumentInfo.All` = Apple `Instrument.allCases`; stable sorts (`OrderBy`, never `List.Sort`) where Swift's stable `sorted` has ties (rival gap/protect/spotlight); ordinal string ordering for keyed groups.

## Decisions

- Accuracy stays in expanded units (0–1,000,000) inside the generator, like Apple; `SuggestionSongItem.Percent` is 0–100.
- The filter is a separate file rather than an `AppSettings` field so it does not widen the shared settings model; Settings' future "Reset" should also delete it (open issue).
- The filter follows Settings' visible instruments (batch 6.37): hidden charts are not offered, an open filter rebuilds at once when Settings change, and toggles left off on a hidden chart don't count toward the gold accent, the filtered-empty message or Reset (`SuggestionFilterSettings.IsActiveFor`); they return when the chart is shown again.
- A filter that disables every type skips generation entirely (nothing could show) instead of spinning the generator.
- Filter and global search stay put while the cards scroll (issue #52 check, 2026-10-01): the header Grid (title + `fst.suggestions.filter-button`) sits above the `CardList` and only the list scrolls; UIA rects were identical before/after scrolling at compact, Filter opened while scrolled and Esc returned focus. No change needed.
- **Rival name badge, native deviation (2026-10-02, issue #59 check of #29):** single-rival cards (`song_rival_spotlight_`/`gap_`/`protect_`/`slipping_`/`dominate_`) name the rival in their title, so rows drop the web's per-row name pill and show only the signed delta + icon (`SuggestionRowPresentation.ShowsRivalName`, as Apple). Mixed-rival cards (`song_rival_battleground`, `song_rival_pct_push` and the other cross-pollination families) keep the pill. Narrator still names the rival on pill-less rows: the row's `AutomationProperties.Name` ends "2 ranks behind Rival B1" (`RivalDeltaAccessibilityLabel`); mixed rows keep "rival X, behind by 2 ranks" (singular "rank" fixed at the same time). Verified in the running app with `uiwin.py` screenshots and the UIA tree (fixture mode, seed 1).
- Art: one retry on a failed fetch, and a stale `Unloaded` (WinUI re-parenting) no longer cancels a row's in-flight art load.

## Fixture mode

`python tools/windows/suggestions_fixture_server.py` (port 8766) serves the parity fixture as publication/songs/player/rivals-all plus generated abstract art. Launch Debug with `--base-url http://127.0.0.1:8766/`, `FST_DEBUG_PROFILE=fixture-suggest:Fixture Player` (preselects in an in-memory settings store; never touches the shared settings file) and `FST_DEBUG_SUGGESTIONS_SEED=1`. Screenshots: `windows/reports/screenshots/suggestions-{wide,wide-rivals,medium,compact,filter-medium}.png`.

## Open issues

- Compact (500 px): the shell keeps the `NavigationView` pane expanded, leaving ~350 px of content (shell lane).
- Filter reset is not wired into Settings' Reset; no first-run slides; no scroll restoration across launches (the page and its mix are cached for the session).
- Journey `tools/windows/journeys/paths-suggestions.json` covers the filter's Instrument Selector; incremental loading is not yet automated; `uiwin.py scroll` fails when other lanes' windows occlude the app.

## IDs

`fst.suggestions.{filter-button,list,loading,syncing,choose-profile,error,no-results,reset-filters,start-new-mix}`, `fst.suggestions.category.<key>[.<mix>]`, `fst.suggestions.row.<songId|songId|Solo_X>`, `fst.suggestions.filter.{form,title,instruments,general,instrument-specific,instrument-picker.{<Solo_X>,compact,previous,next},instrument.<Solo_X>,type.<type>,type.<Solo_X>.<type>,reset}`.
